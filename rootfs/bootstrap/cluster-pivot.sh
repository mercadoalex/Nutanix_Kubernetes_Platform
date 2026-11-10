#!/bin/bash
# cluster-pivot.sh
# Runs as laborant via cluster-pivot.service at boot.
# Polls controlplane (172.16.0.11) until all 4 RKE2 nodes are Ready,
# then copies the kubeconfig and fixes the server address.
# After this script completes, kubectl works for laborant without any setup.
#
# Students can watch progress:
#   journalctl -u cluster-pivot.service -f

set -euo pipefail

CONTROL_PLANE_IP="172.16.0.11"
KUBECONFIG_DIR="/home/laborant/.kube"
KUBECONFIG_PATH="${KUBECONFIG_DIR}/mgmt.kubeconfig"
MAX_WAIT=300   # 5 minutes max
INTERVAL=10

# SSH options — key-based auth (lab_key baked into both rootfs images)
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i /home/laborant/.ssh/lab_key"

log() { echo "[cluster-pivot] $*"; }

# ── wait for SSH to be available on controlplane ──────────────────────────────
log "Waiting for controlplane SSH..."
elapsed=0
while ! ssh ${SSH_OPTS} root@${CONTROL_PLANE_IP} true 2>/dev/null; do
    sleep ${INTERVAL}
    elapsed=$((elapsed + INTERVAL))
    if [ ${elapsed} -ge ${MAX_WAIT} ]; then
        log "ERROR: controlplane SSH not available after ${MAX_WAIT}s"
        exit 1
    fi
    log "  ...waiting for SSH (${elapsed}s)"
done
log "controlplane SSH ready"

# ── wait for RKE2 server to write its kubeconfig ─────────────────────────────
log "Waiting for RKE2 kubeconfig on controlplane..."
elapsed=0
while ! ssh ${SSH_OPTS} root@${CONTROL_PLANE_IP} \
        'test -f /etc/rancher/rke2/rke2.yaml' 2>/dev/null; do
    sleep ${INTERVAL}
    elapsed=$((elapsed + INTERVAL))
    if [ ${elapsed} -ge ${MAX_WAIT} ]; then
        log "ERROR: RKE2 kubeconfig not written after ${MAX_WAIT}s"
        exit 1
    fi
    log "  ...waiting for rke2.yaml (${elapsed}s)"
done
log "RKE2 kubeconfig ready"

# ── copy kubeconfig and fix server address ────────────────────────────────────
mkdir -p "${KUBECONFIG_DIR}"
scp ${SSH_OPTS} \
    root@${CONTROL_PLANE_IP}:/etc/rancher/rke2/rke2.yaml \
    "${KUBECONFIG_PATH}"
sed -i "s/127.0.0.1/${CONTROL_PLANE_IP}/" "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"
log "kubeconfig copied to ${KUBECONFIG_PATH}"

# ── wait for all 4 nodes to be Ready ─────────────────────────────────────────
log "Waiting for 4 nodes Ready..."
elapsed=0
while true; do
    READY=$(kubectl --kubeconfig="${KUBECONFIG_PATH}" get nodes \
            --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)
    if [ "${READY}" -ge 4 ]; then
        log "All 4 nodes Ready ✓"
        break
    fi
    sleep ${INTERVAL}
    elapsed=$((elapsed + INTERVAL))
    if [ ${elapsed} -ge ${MAX_WAIT} ]; then
        log "WARNING: Only ${READY}/4 nodes Ready after ${MAX_WAIT}s — continuing anyway"
        break
    fi
    log "  ...${READY}/4 nodes Ready (${elapsed}s)"
done

log "Cluster pivot complete. Run: kubectl get nodes"
