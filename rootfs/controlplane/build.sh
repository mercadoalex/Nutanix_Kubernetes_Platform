#!/usr/bin/env bash
# rootfs/controlplane/build.sh
# Convenience wrapper — builds and pushes nkp-controlplane to GHCR.
# Prefer: cd rootfs && make controlplane

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
RELEASE="${RELEASE:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

docker buildx build \
    --platform linux/amd64 \
    --push \
    -t "${REGISTRY}/nkp-controlplane:${RELEASE}" \
    -t "${REGISTRY}/nkp-controlplane:latest" \
    --progress=plain \
    .
echo "✓ ${REGISTRY}/nkp-controlplane:latest"
