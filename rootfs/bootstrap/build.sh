#!/usr/bin/env bash
# rootfs/bootstrap/build.sh
# Convenience wrapper — builds and pushes nkp-bootstrap to GHCR.
# Prefer: cd rootfs && make bootstrap
#
# Must run from rootfs/ root so downloads/bootstrap/ is in context.
#
# Pre-requisite: all binaries must be pre-downloaded first:
#   cd downloads/bootstrap && bash fetch.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."   # always run from rootfs/ root

REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
RELEASE="${RELEASE:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

# ── preflight: verify downloads are present ───────────────────────────────────
MISSING=0
for f in \
    downloads/bootstrap/kubectl \
    downloads/bootstrap/kind \
    downloads/bootstrap/nkp_v2.17.1_linux_amd64.tar.gz \
    downloads/bootstrap/helm-v3.17.3-linux-amd64.tar.gz \
    downloads/bootstrap/flux_2.5.1_linux_amd64.tar.gz \
    downloads/bootstrap/k9s_Linux_amd64.tar.gz
do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: missing $f"
        MISSING=1
    fi
done
if [[ $MISSING -eq 1 ]]; then
    echo ""
    echo "Run first:  cd downloads/bootstrap && bash fetch.sh"
    exit 1
fi

docker buildx build \
    --platform linux/amd64 \
    --push \
    -t "${REGISTRY}/nkp-bootstrap:${RELEASE}" \
    -t "${REGISTRY}/nkp-bootstrap:latest" \
    --progress=plain \
    -f bootstrap/Dockerfile \
    .
echo "✓ ${REGISTRY}/nkp-bootstrap:latest"
