#!/usr/bin/env bash
# rootfs/worker/build.sh
# Convenience wrapper — builds and pushes nkp-worker to GHCR.
# Prefer: cd rootfs && make worker
#
# Must run from rootfs/ root so downloads/rke2/ is in context.
# This single image is used for vm3, vm4, AND vm5.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
RELEASE="${RELEASE:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

if [[ ! -f "downloads/rke2/install.sh" ]]; then
    echo "ERROR: downloads/rke2/ not found. Ensure RKE2 files are pre-downloaded."
    echo "  ls downloads/rke2/"
    exit 1
fi

docker buildx build \
    --platform linux/amd64 \
    --push \
    -t "${REGISTRY}/nkp-worker:${RELEASE}" \
    -t "${REGISTRY}/nkp-worker:latest" \
    --progress=plain \
    -f worker/Dockerfile \
    .
echo "✓ ${REGISTRY}/nkp-worker:latest"
