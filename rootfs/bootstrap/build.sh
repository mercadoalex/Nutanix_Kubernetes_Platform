#!/usr/bin/env bash
# rootfs/bootstrap/build.sh
# Builds nkp-bootstrap.ext4 — the rootfs image for vm1 (bootstrap / operator workstation)
#
# Prerequisites:
#   - Docker running on the build host
#   - nkp binary placed at rootfs/bootstrap/nkp (downloaded from portal.nutanix.com)
#   - Run from the rootfs/bootstrap/ directory, or use the top-level Makefile
#
# Output: ../../dist/nkp-bootstrap.ext4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/../../dist"
IMAGE_NAME="nkp-bootstrap-builder"
OUTPUT="${DIST_DIR}/nkp-bootstrap.ext4"
# Size in MB — Ubuntu + Docker + tools + kind images pre-pulled
EXT4_SIZE_MB=8192

cd "${SCRIPT_DIR}"

# ── preflight ─────────────────────────────────────────────────────────────────
if [[ ! -f "nkp" ]]; then
    echo ""
    echo "ERROR: nkp binary not found at rootfs/bootstrap/nkp"
    echo ""
    echo "  1. Go to https://portal.nutanix.com/page/downloads?product=nkp"
    echo "  2. Download 'NKP for Linux' (the CLI tarball)"
    echo "  3. Extract: tar xz -C rootfs/bootstrap/ --strip-components=1 -f nkp-*.tar.gz nkp"
    echo ""
    exit 1
fi

mkdir -p "${DIST_DIR}"
mkdir -p labs  # populated by lesson content; empty is fine for initial build

# ── build container image ─────────────────────────────────────────────────────
echo "→ Building Docker image ${IMAGE_NAME}..."
docker build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --progress=plain \
    -t "${IMAGE_NAME}:latest" \
    .

# ── pre-pull kind node image into the container ──────────────────────────────
# This runs docker-in-docker to pull the kind node image so it is available
# offline when the VM boots. The kind node image version must match the
# NKP bootstrap cluster's expected Kubernetes version (1.34.x).
KIND_NODE_IMAGE="kindest/node:v1.34.3"
echo "→ Pre-pulling kind node image ${KIND_NODE_IMAGE} (this may take a few minutes)..."
docker run --rm --privileged \
    -v /var/lib/docker \
    "${IMAGE_NAME}:latest" \
    bash -c "
        dockerd &>/tmp/dockerd.log &
        sleep 5
        docker pull ${KIND_NODE_IMAGE}
        docker save ${KIND_NODE_IMAGE} -o /tmp/kind-node.tar
    "

# ── export container filesystem to ext4 ──────────────────────────────────────
echo "→ Exporting container filesystem..."
CONTAINER_ID=$(docker create "${IMAGE_NAME}:latest")
TMP_TAR=$(mktemp /tmp/nkp-bootstrap-XXXXXX.tar)

docker export "${CONTAINER_ID}" > "${TMP_TAR}"
docker rm "${CONTAINER_ID}"

echo "→ Creating ext4 image (${EXT4_SIZE_MB} MB)..."
dd if=/dev/zero of="${OUTPUT}" bs=1M count="${EXT4_SIZE_MB}" status=progress
mkfs.ext4 -F -L "nkp-bootstrap" "${OUTPUT}"

# Mount and populate
TMP_MNT=$(mktemp -d)
sudo mount -o loop "${OUTPUT}" "${TMP_MNT}"
sudo tar -xf "${TMP_TAR}" -C "${TMP_MNT}" --numeric-owner
sudo umount "${TMP_MNT}"
rmdir "${TMP_MNT}"
rm "${TMP_TAR}"

echo ""
echo "✓ Built: ${OUTPUT}"
echo "  Size: $(du -sh "${OUTPUT}" | cut -f1)"
