#!/bin/bash
# code_aster container entrypoint.
#
#  1. Load the code_aster + prerequisites environment (LD_LIBRARY_PATH,
#     PYTHONPATH, run_aster on PATH) so the image works when a command is
#     passed directly (not only in an interactive login shell).
#  2. Default CPU thread counts to the cores available to the container.
#     Override at run time, e.g.  docker run -e OMP_NUM_THREADS=4 ...
#  3. exec the requested command (defaults to an interactive shell).
set -e

. /opt/aster/prerequisites/env_std.sh 2>/dev/null || true
export PATH=/opt/aster/install/seq/bin:$PATH

# CPU threading (OpenBLAS + MUMPS OpenMP). Respect user-provided values.
: "${OMP_NUM_THREADS:=$(nproc)}"
: "${OPENBLAS_NUM_THREADS:=${OMP_NUM_THREADS}}"
export OMP_NUM_THREADS OPENBLAS_NUM_THREADS

exec "$@"
