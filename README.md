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

## Using the image as a script / CLI

The image has an entrypoint that loads the code_aster environment and then runs
whatever command you pass, so you can treat it like the `run_aster` executable.
It also defaults the CPU thread count to the cores available to the container.

**Run a study from the current directory** (mount it, then point `run_aster` at
your `.export`):

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/mickg10/code-aster-arm64:latest run_aster study.export
```

**Make a reusable wrapper** so `code_aster` feels like a local command — drop
this in `~/bin/code_aster` and `chmod +x` it:

```bash
#!/usr/bin/env bash
# Usage: code_aster study.export        (run from the study's directory)
exec docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/mickg10/code-aster-arm64:latest run_aster "$@"
```

Then: `cd my_study && code_aster study.export`.

**Run a Python study directly** (no `.export` needed):

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/mickg10/code-aster-arm64:latest run_aster study.py
```

**Control CPU threads** (defaults to all cores the container sees):

```bash
docker run --rm -e OMP_NUM_THREADS=4 -v "$PWD:/work" -w /work \
  ghcr.io/mickg10/code-aster-arm64:latest run_aster study.export
```

**Pipe a quick command / inspect interactively:**

```bash
docker run --rm ghcr.io/mickg10/code-aster-arm64:latest run_aster --version
docker run --rm -it ghcr.io/mickg10/code-aster-arm64:latest      # shell
```

> The container runs as the non-root user `aster`. Output files are written into
> the mounted `/work` directory; on Linux hosts add `--user "$(id -u):$(id -g)"`
> if you need them owned by your host user (not needed on Docker Desktop/Colima
> for macOS, which maps ownership automatically).

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
- **gmsh** (native arm64, with MED + OpenCASCADE) under `/opt/gmsh`, on `PATH`
- Prerequisites under `/opt/aster/prerequisites/20251026/gcc-openblas-seq`
- Runs as non-root user `aster` (home `/home/aster`)
- Environment auto-sourced via the entrypoint and `/etc/profile.d/aster.sh`

## Meshing with gmsh (built in)

A native-arm64 **gmsh 4.13** is bundled, compiled from source with **MED** and
**OpenCASCADE** support (Debian's gmsh package has no MED, and there is no arm64
PyPI wheel). It links the *same* MED/HDF5 libraries the solver reads, so meshes
are directly compatible — no host tooling needed.

Mesh a CAD/`.geo` model to MED and solve, all in the container:

```bash
# mesh model.geo -> model.med, then run the study, in one mounted workdir
docker run --rm -v "$PWD:/work" -w /work code-aster-arm64 \
  bash -lc 'gmsh -3 model.geo -o model.med -format med && run_aster study.export'
```

Read it in the study with `LIRE_MAILLAGE(FORMAT="MED", UNITE=20)` and define
gmsh **Physical Groups** so they become code_aster `GROUP_MA` / `GROUP_NO`.
gmsh's native `.msh` (v2) is also readable via `FORMAT="GMSH"`.

## Notes / scope

- **Sequential only.** PETSc, ParMETIS, ScaLAPACK and MPI are intentionally
  omitted (not needed for the sequential MUMPS solver). An MPI variant could be
  added later.
- This is a community native-arm64 build, not an official EDF release.

## Licensing

code_aster is distributed under the **GNU GPL v3**. This repository contains
only build tooling (Dockerfile and scripts); the source code and prerequisites
are downloaded from the official EDF GitLab during the build. See
<https://www.code-aster.org/> and <https://gitlab.com/codeaster/src>.
