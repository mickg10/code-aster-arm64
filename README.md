# code_aster — native arm64 (aarch64) Docker image

A **natively-compiled arm64/aarch64** Docker image of
[code_aster](https://www.code-aster.org/), the open-source finite-element
solver developed by EDF.

Unlike the upstream [`simvia/code_aster`](https://simvia.tech/software/code-aster)
images (which are `linux/amd64` and run under emulation on Apple Silicon /
Graviton / other ARM hosts), this image is built **from source for arm64**, so
it runs at full native speed with no QEMU/Rosetta translation layer.

| | |
|---|---|
| code_aster version | **17.4** (stable maintenance line) |
| Prerequisites bundle | `codeaster-prerequisites-20251026-oss` |
| Build | **sequential** (MUMPS sequential + METIS/SCOTCH), OpenBLAS |
| Base image | `debian:bookworm` (Python 3.11) |
| Architecture | `linux/arm64` (native) |
| Toolchain | Debian system GCC/GFortran 12, OpenBLAS (native aarch64) |

## Why

The official and third-party code_aster containers are x86-64 only. On Apple
Silicon and ARM servers they run through emulation, which is several times
slower for a CPU-bound solver. There is no published native arm64 build, so this
project compiles code_aster and its full prerequisite chain (HDF5, MED,
MEDCoupling, METIS, SCOTCH, MUMPS, MFront/MGIS, HOMARD, MISS3D, …) directly for
aarch64.

## Quick start

```bash
# pull (once published) or build locally (see below)
docker run --rm -it ghcr.io/mickg10/code-aster-arm64:latest

# inside the container:
run_aster --version
```

Run a study (`.export` driving a `.comm` command file):

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/mickg10/code-aster-arm64:latest \
  run_aster mystudy.export
```

## Building locally

Requires a **native arm64 Docker engine** (Apple Silicon with Docker Desktop or
Colima, or an ARM Linux host). The build compiles everything from source and
takes roughly **1–2 hours**.

```bash
./build.sh                 # builds ghcr.io/mickg10/code-aster-arm64:latest
# or directly:
docker build -t code-aster-arm64 .
```

To verify the resulting image:

```bash
./test.sh code-aster-arm64
```

## What's inside

- code_aster sequential install under `/opt/aster/install/seq`
- `run_aster`, `as_run`, `astk` on `PATH`
- Prerequisites under `/opt/aster/prerequisites/20251026/gcc-openblas-seq`
- Runs as non-root user `aster` (home `/home/aster`)
- Environment auto-sourced via `/etc/profile.d/aster.sh`

## Notes / scope

- **Sequential only.** PETSc, ParMETIS, ScaLAPACK and MPI are intentionally
  omitted (not needed for the sequential MUMPS solver). An MPI variant could be
  added later.
- **gmsh** is omitted — upstream ships an x86-64-only gmsh binary in the
  prerequisites bundle, which is not usable on arm64. Mesh with Salome/gmsh on
  the host and import the `.med`/`.mmed` mesh.
- This is a community native-arm64 build, not an official EDF release.

## Licensing

code_aster is distributed under the **GNU GPL v3**. This repository contains
only build tooling (Dockerfile and scripts); the source code and prerequisites
are downloaded from the official EDF GitLab during the build. See
<https://www.code-aster.org/> and <https://gitlab.com/codeaster/src>.
