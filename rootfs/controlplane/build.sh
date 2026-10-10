#!/usr/bin/env bash
# rootfs/controlplane/build.sh
# Builds nkp-controlplane.ext4 — rootfs for vm2 (RKE2 control plane)
#
# Prerequisites: Docker on build host, internet access for image pulls
# Output: ../../dist/nkp-controlplane.ext4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/../../dist"
IMAGE_NAME="nkp-controlplane-builder"
OUTPUT="${DIST_DIR}/nkp-controlplane.ext4"
# 12 GB — Rocky base + RKE2 binary + airgap image bundles (~4 GB compressed)
EXT4_SIZE_MB=12288

cd "${SCRIPT_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p labs  # populated by lesson content; empty is fine for initial build

echo "→ Building Docker image ${IMAGE_NAME}..."
docker build \
    --progress=plain \
    -t "${IMAGE_NAME}:latest" \
    .

echo "→ Exporting container filesystem..."
CONTAINER_ID=$(docker create "${IMAGE_NAME}:latest")
TMP_TAR=$(mktemp /tmp/nkp-controlplane-XXXXXX.tar)
docker export "${CONTAINER_ID}" > "${TMP_TAR}"
docker rm "${CONTAINER_ID}"

echo "→ Creating ext4 image (${EXT4_SIZE_MB} MB)..."
dd if=/dev/zero of="${OUTPUT}" bs=1M count="${EXT4_SIZE_MB}" status=progress
mkfs.ext4 -F -L "nkp-controlplane" "${OUTPUT}"

TMP_MNT=$(mktemp -d)
sudo mount -o loop "${OUTPUT}" "${TMP_MNT}"
sudo tar -xf "${TMP_TAR}" -C "${TMP_MNT}" --numeric-owner
sudo umount "${TMP_MNT}"
rmdir "${TMP_MNT}"
rm "${TMP_TAR}"

echo ""
echo "✓ Built: ${OUTPUT}"
echo "  Size: $(du -sh "${OUTPUT}" | cut -f1)"
