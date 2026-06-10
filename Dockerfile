# syntax=docker/dockerfile:1
#
# Native arm64 (aarch64) build of code_aster (sequential).
#
# Two stages:
#   1) build   – compile the prerequisites bundle + code_aster from source
#   2) runtime – slim image carrying only the install + runtime libraries
#
# Build ONLY on a native arm64 engine (Apple Silicon / Colima / ARM Linux):
#   docker build --platform linux/arm64 -t code-aster-arm64 .

############################  build stage  ############################
FROM debian:bookworm AS build

ARG PREREQ_VERSION=20251026
ARG ASTER_TAG=17.4.18
ARG ARCH=gcc-openblas-seq
ARG GMSH_VERSION=4.13.1
ARG PREREQ_URL=https://gitlab.com/api/v4/projects/codeaster-opensource-documentation%2Fopensource-installation-development/packages/generic/codeaster-prerequisites/${PREREQ_VERSION}/codeaster-prerequisites-${PREREQ_VERSION}-oss.tar.gz

ENV DEBIAN_FRONTEND=noninteractive
ENV USE_PIXI=0

# Native Debian toolchain (GCC/GFortran 12, OpenBLAS) + build deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gfortran gcc g++ make cmake patch bison flex swig \
        python3 python3-dev python3-venv python3-numpy python3-scipy cython3 python3-pip \
        pybind11-dev python3-pybind11 \
        libopenblas-dev liblapack-dev \
        libbz2-dev liblzma-dev \
        zlib1g-dev libxml2-dev tk tk-dev libtirpc-dev \
        libboost-all-dev \
        wget curl git ca-certificates locales binutils file \
    && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8

# --- 1. Prerequisites (sequential): HDF5, MED, METIS, SCOTCH, MUMPS(seq),
#        MFront/MGIS, HOMARD, MISS3D, MEDCoupling, ecrevisse, asrun.
#        PETSc/ParMETIS/ScaLAPACK/mpi4py self-skip in sequential mode.
#        gmsh is dropped (upstream ships an x86-64-only binary).
WORKDIR /opt/repo
RUN curl -fSL "${PREREQ_URL}" -o /tmp/prereq.tar.gz \
    && tar xzf /tmp/prereq.tar.gz --strip-components=1 -C /opt/repo \
    && rm /tmp/prereq.tar.gz

# The public '-oss' bundle ships METIS as a no-op (its real source lives on EDF's
# internal GitLab). Build the classic self-contained METIS 5.1.0 ourselves into
# the exact DEST path MUMPS expects, matching the upstream recipe (i64/r64).
ARG METIS_URL=https://src.fedoraproject.org/lookaside/extras/metis/metis-5.1.0.tar.gz/5465e67079419a69e0116de24fce58fe/metis-5.1.0.tar.gz
RUN DEST=/opt/aster/prerequisites/20251026/${ARCH} \
    && mkdir -p "${DEST}" \
    && curl -fSL "${METIS_URL}" -o /tmp/metis.tar.gz \
    && tar xzf /tmp/metis.tar.gz -C /tmp \
    && cd /tmp/metis-5.1.0 \
    && make config CFLAGS="-fPIC" prefix="${DEST}/metis-5.1.0" shared=1 i64=1 r64=1 \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/metis*

# The bundle leaves MUMPS's LMETIS line commented out (it expects METIS from the
# internal mirror); re-enable it so MUMPS links the METIS we just built.
RUN sed -i 's|^#LMETIS     = -L${DEST}/metis-${METIS}/lib -lmetis|LMETIS     = -L${DEST}/metis-${METIS}/lib -lmetis|' src/mumps.sh

# miss3d's GNU template uses the x86-only flag '-mcmodel=medium'; strip it on arm64.
RUN sed -i '/^make -j /i sed -i "s/-mcmodel=medium//g" src/Makefile.inc' src/miss3d.sh

# On aarch64 'char' is unsigned by default; medcoupling has negative char
# literals that then trip -Wnarrowing. Force signed char (x86 semantics).
RUN sed -i '/^cmake \.\. \\$/a\    -DCMAKE_CXX_FLAGS="-fsigned-char" \\' src/medcoupling.sh

# gmsh is dropped from PRODUCTS (x86-only binary), so the env-file generator
# must not require it either — remove gmsh from the generated environment.
RUN sed -i '/coll.add("GMSH"/d' utils/generate_env.py

RUN export PRODUCTS="hdf5 med metis parmetis mfront mgis homard scotch scalapack mumps petsc miss3d medcoupling ecrevisse mpi4py grace asrun" \
    && export FCFLAGS="-fallow-argument-mismatch" FFLAGS="-fallow-argument-mismatch" \
    && ./builder.sh --root=/opt/aster/prerequisites --gpl --mpi=seq --install

# --- 2. code_aster itself, built sequentially against the prerequisites above.
# A depth-1 checkout has no history for waf's git-based version detection, so we
# provide code_aster/pkginfo.py explicitly (note: 7th field must be a list) and
# pass --without-repo. C++ is compiled with -fsigned-char (x86 char semantics).
WORKDIR /opt/src
RUN git clone --depth 1 --branch "${ASTER_TAG}" https://gitlab.com/codeaster/src.git . \
    && SHA="$(git rev-parse HEAD)" \
    && DATE="$(git log -1 --format=%cd --date=format:%d/%m/%Y)" \
    && rm -rf .git \
    && printf 'pkginfo = [(17, 4, 18), "%s", "v17.4", "%s", "v17.4", 0, []]\n' "${SHA}" "${DATE}" \
       > code_aster/pkginfo.py \
    && . "$(ls /opt/aster/prerequisites/${PREREQ_VERSION}/${ARCH}/*_std.sh | head -1)" \
    && export CXXFLAGS="-fsigned-char ${CXXFLAGS:-}" \
    && ./waf_std configure --prefix=/opt/aster/install/seq --without-repo \
    && ./waf_std install -j "$(nproc)"

# --- 3. gmsh (native arm64) built from source with MED + OpenCASCADE.
# Debian's gmsh package is compiled WITHOUT MED support, and there is no arm64
# PyPI wheel, so build it ourselves — linked against the SAME MED/HDF5 the solver
# uses, so meshes written here are byte-compatible with what code_aster reads.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libocct-foundation-dev libocct-modeling-data-dev \
        libocct-modeling-algorithms-dev libocct-data-exchange-dev \
        libocct-ocaf-dev libgmp-dev \
    && rm -rf /var/lib/apt/lists/*
RUN D="/opt/aster/prerequisites/${PREREQ_VERSION}/${ARCH}" \
    && MED_DIR="$(ls -d ${D}/med-*/ | head -1)" \
    && HDF5_DIR="$(ls -d ${D}/hdf5-*/ | head -1)" \
    && curl -fSL "https://gmsh.info/src/gmsh-${GMSH_VERSION}-source.tgz" -o /tmp/gmsh.tgz \
    && mkdir -p /tmp/gmsh && tar xzf /tmp/gmsh.tgz --strip-components=1 -C /tmp/gmsh \
    && cmake -S /tmp/gmsh -B /tmp/gmsh/build -DCMAKE_INSTALL_PREFIX=/opt/gmsh \
        -DENABLE_FLTK=OFF -DENABLE_GRAPHICS=OFF \
        -DENABLE_OCC=ON -DENABLE_MED=ON -DENABLE_HXT=ON -DENABLE_BUILD_DYNAMIC=ON \
        -DMED_LIB="${MED_DIR}lib/libmedC.so" -DMED_INC="${MED_DIR}include" \
        -DHDF5_ROOT="${HDF5_DIR}" \
        -DCMAKE_INSTALL_RPATH="${MED_DIR}lib;${HDF5_DIR}lib" \
    && cmake --build /tmp/gmsh/build -j "$(nproc)" --target install \
    && rm -rf /tmp/gmsh /tmp/gmsh.tgz

# Stamp the prerequisites env profile into a stable location for the runtime stage.
RUN cp "$(ls /opt/aster/prerequisites/${PREREQ_VERSION}/${ARCH}/*_std.sh | head -1)" \
       /opt/aster/prerequisites/env_std.sh

############################  runtime stage  ##########################
FROM debian:bookworm-slim AS runtime

ARG PREREQ_VERSION=20251026
ENV DEBIAN_FRONTEND=noninteractive

# Runtime shared libraries only (no -dev, no compilers).
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-numpy python3-scipy \
        libopenblas0 liblapack3 libgfortran5 libstdc++6 libgomp1 \
        libbz2-1.0 liblzma5 \
        zlib1g libxml2 libtirpc3 tk \
        libboost-python1.74.0 libboost-filesystem1.74.0 libboost-regex1.74.0 \
        libocct-foundation-7.6 libocct-modeling-data-7.6 \
        libocct-modeling-algorithms-7.6 libocct-data-exchange-7.6 \
        libocct-ocaf-7.6 libocct-visualization-7.6 \
        libfreeimage3 libtbb12 libgmp10 \
        locales bash less procps \
    && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8

COPY --from=build /opt/aster /opt/aster
COPY --from=build /opt/gmsh /opt/gmsh
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Also auto-source the environment for interactive login shells (e.g. exec'ing
# into a running container), in addition to the entrypoint.
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && printf '%s\n' \
      '# code_aster environment' \
      '. /opt/aster/prerequisites/env_std.sh 2>/dev/null || true' \
      'export PATH=/opt/aster/install/seq/bin:/opt/gmsh/bin:$PATH' \
      > /etc/profile.d/aster.sh

# Non-root user.
RUN useradd -ms /bin/bash aster
USER aster
WORKDIR /home/aster

# The entrypoint loads the environment and sets thread defaults, then runs the
# given command (default: an interactive shell). Override threads with
#   -e OMP_NUM_THREADS=N
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash", "-l"]
