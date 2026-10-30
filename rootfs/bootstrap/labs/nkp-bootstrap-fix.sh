#!/usr/bin/env bash
# nkp-bootstrap-fix.sh
#
# Fix for: nkp create bootstrap fails on iximious Firecracker microVMs with:
#   "connection refused" on cert-manager-webhook.cert-manager.svc:443
#
# ROOT CAUSE:
#   kindnet's kube-network-policies sidecar requires /proc/net/netfilter/nfnetlink_queue
#   which does not exist in the Firecracker kernel. kindnet pods come up degraded,
#   breaking pod IP reachability. cert-manager-webhook's ClusterIP becomes unreachable.
#   nkp retries CAPI init 10 times — not enough for the webhook to recover on its own.
#
# FIX:
#   Run this script instead of 'nkp create bootstrap' directly.
#   It runs nkp in the background, patches kindnet the moment the kind cluster exists,
#   then recycles ALL cert-manager pods (not just webhook) so they get fresh network
#   rules from the fixed kindnet. Only after cert-manager-webhook is Ready does nkp
#   proceed to CAPI init — which then succeeds.
#
# Usage (on vm1):
#   bash ~/labs/nkp-bootstrap-fix.sh
#   -- or if labs/ not present: --
#   curl -fsSL https://raw.githubusercontent.com/mercadoalex/Nutanix_Kubernetes_Platform/main/rootfs/bootstrap/labs/nkp-bootstrap-fix.sh | bash
#
# After success, verify with:
#   kubectl get pods -n capi-system
#   kubectl get pods -n capx-system

set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/config"
export KUBECONFIG="$KUBECONFIG_PATH"

# ── Step 1: start nkp in the background ───────────────────────────────────────
echo "==> Starting nkp create bootstrap (background)..."
nkp create bootstrap &
NKP_PID=$!

# ── Step 2: wait for kind cluster API to be reachable ─────────────────────────
echo "==> Waiting for kind cluster API server..."
for i in $(seq 1 120); do
    if kubectl get nodes &>/dev/null 2>&1; then
        echo "    API server up (attempt $i)"
        break
    fi
    sleep 3
done

# ── Step 3: wait for kindnet DaemonSet ────────────────────────────────────────
echo "==> Waiting for kindnet DaemonSet..."
for i in $(seq 1 60); do
    if kubectl get daemonset kindnet -n kube-system &>/dev/null 2>&1; then
        echo "    kindnet DaemonSet found (attempt $i)"
        break
    fi
    sleep 3
done

# ── Step 4: patch kindnet to disable network policy plugin ────────────────────
echo "==> Patching kindnet: DISABLE_NETWORK_POLICY=true..."
kubectl patch daemonset kindnet -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"DISABLE_NETWORK_POLICY","value":"true"}]}]' \
    2>/dev/null \
|| kubectl patch daemonset kindnet -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"DISABLE_NETWORK_POLICY","value":"true"}}]'

echo "==> Recycling kindnet pod..."
kubectl delete pod -n kube-system -l app=kindnet --grace-period=0 2>/dev/null || true

echo "==> Waiting for kindnet to be Ready..."
kubectl wait pod \
    --for=condition=Ready \
    --selector=app=kindnet \
    -n kube-system \
    --timeout=90s

echo "==> kindnet is healthy."

# ── Step 5: wait for cert-manager namespace, then recycle ALL cert-manager pods ─
echo "==> Waiting for cert-manager namespace..."
for i in $(seq 1 60); do
    if kubectl get namespace cert-manager &>/dev/null 2>&1; then
        echo "    cert-manager namespace found (attempt $i)"
        break
    fi
    sleep 3
done

echo "==> Waiting 10s for cert-manager pods to be scheduled..."
sleep 10

echo "==> Recycling ALL cert-manager pods (fresh network rules from fixed kindnet)..."
kubectl delete pods -n cert-manager --all --grace-period=0 2>/dev/null || true

echo "==> Waiting for cert-manager-webhook to be Ready (up to 3 min)..."
kubectl wait pod \
    --for=condition=Ready \
    --selector=app.kubernetes.io/component=webhook \
    -n cert-manager \
    --timeout=180s

echo "==> cert-manager-webhook is Ready."

# ── Step 6: wait for nkp to finish ────────────────────────────────────────────
echo "==> Waiting for nkp create bootstrap to complete..."
wait $NKP_PID
NKP_EXIT=$?

if [[ $NKP_EXIT -eq 0 ]]; then
    echo ""
    echo "✓ Bootstrap cluster ready!"
    echo ""
    kubectl get pods -n capi-system
    kubectl get pods -n capx-system
else
    echo ""
    echo "✗ nkp create bootstrap exited with code $NKP_EXIT"
    echo "  Run: kubectl get pods -A | grep -v Running"
    exit $NKP_EXIT
fi
