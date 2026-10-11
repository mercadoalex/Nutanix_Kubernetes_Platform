#!/usr/bin/env bash
# rootfs/controlplane/build.sh
# Convenience wrapper — builds and pushes nkp-controlplane to GHCR.
# Prefer: cd rootfs && make controlplane
#
# Must run from rootfs/ root (not controlplane/) so downloads/rke2/ is in context.

set -euo pipefail
# Always run from rootfs/ root
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
RELEASE="${RELEASE:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

if [[ ! -f "rke2/install.sh" ]]; then
    echo "ERROR: rke2/ not found. Run from rootfs/ root and ensure RKE2 files are pre-downloaded."
    echo "  ls rke2/"
    exit 1
fi

docker buildx build \
    --platform linux/amd64 \
    --push \
    -t "${REGISTRY}/nkp-controlplane:${RELEASE}" \
    -t "${REGISTRY}/nkp-controlplane:latest" \
    --progress=plain \
    -f controlplane/Dockerfile \
    .
echo "✓ ${REGISTRY}/nkp-controlplane:latest"
