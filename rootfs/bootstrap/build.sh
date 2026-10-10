#!/usr/bin/env bash
# rootfs/bootstrap/build.sh
# Convenience wrapper — builds and pushes nkp-bootstrap to GHCR.
# Prefer: cd rootfs && make bootstrap
#
# The nkp binary is downloaded automatically during docker build from the D2iQ CDN.
# No portal account or pre-placed binary required.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
RELEASE="${RELEASE:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

docker buildx build \
    --platform linux/amd64 \
    --push \
    -t "${REGISTRY}/nkp-bootstrap:${RELEASE}" \
    -t "${REGISTRY}/nkp-bootstrap:latest" \
    --progress=plain \
    .
echo "✓ ${REGISTRY}/nkp-bootstrap:latest"
