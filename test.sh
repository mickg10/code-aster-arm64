#!/usr/bin/env bash
# Smoke-test a built code_aster arm64 image.
set -euo pipefail
IMAGE="${1:-code-aster-arm64}"

echo ">>> 1/3 architecture is arm64 (no emulation)"
docker run --rm "$IMAGE" bash -lc 'uname -m' | grep -qx 'aarch64' \
  && echo "    OK: aarch64"

echo ">>> 2/3 run_aster is on PATH and reports a version"
docker run --rm "$IMAGE" bash -lc 'run_aster --version'

echo ">>> 3/3 solve the minimal verification study (axial bar, MUMPS) and check TEST_RESU"
docker run --rm -v "$(cd "$(dirname "$0")/tests" && pwd):/work:ro" \
  "$IMAGE" bash -lc '
    set -e
    cp -r /work /tmp/run && cd /tmp/run
    run_aster smoke.export | tee run.out
    grep -q "DIAGNOSTIC JOB : OK" run.out \
      && grep -qE "OK +ANALYTIQUE" smoke.mess \
      && echo "    OK: study solved and TEST_RESU matched the analytical value" \
      || { echo "    FAILED:"; tail -40 smoke.mess 2>/dev/null; exit 1; }
  '
echo ">>> all checks passed for $IMAGE"
