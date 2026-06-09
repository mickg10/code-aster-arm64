#!/usr/bin/env bash
# Build the native arm64 code_aster image.
# Requires a native arm64 Docker engine (Apple Silicon / Colima / ARM Linux).
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/mickg10/code-aster-arm64:latest}"

# Refuse to build under emulation — a native build is the whole point.
arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
case "$arch" in
  aarch64|arm64) ;;
  *)
    echo "ERROR: Docker engine architecture is '$arch', not arm64/aarch64." >&2
    echo "       This image must be built on a native arm64 engine." >&2
    exit 1
    ;;
esac

echo ">>> Building $IMAGE (native arm64; this takes ~1-2 hours)…"
exec docker build --platform linux/arm64 -t "$IMAGE" "$@" .
