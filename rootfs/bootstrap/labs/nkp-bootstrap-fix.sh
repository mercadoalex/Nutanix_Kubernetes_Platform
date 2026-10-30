#!/usr/bin/env bash
# nkp-bootstrap-fix.sh
#
# Workaround for Firecracker microVM kernel missing nfnetlink_queue.
#
# kindnet's kube-network-policies plugin requires /proc/net/netfilter/nfnetlink_queue
# which does not exist in the iximious Firecracker kernel. This causes the
# cert-manager-webhook pod to fail its liveness/readiness probes (kubelet cannot
# reach pod IPs), which causes nkp create bootstrap to fail at CAPI init with:
#   "connection refused" on cert-manager-webhook.cert-manager.svc:443
#
# This script:
#   1. Starts nkp create bootstrap in the background
#   2. Watches for the kind cluster to become available
#   3. Immediately patches kindnet to disable the broken network policy plugin
#   4. Waits for cert-manager-webhook to become Ready
#   5. nkp's own retry loop then succeeds at CAPI init
#
# Usage (on vm1):
#   bash ~/labs/nkp-bootstrap-fix.sh
#
# After success, verify with:
#   kubectl get pods -n capi-system
#   kubectl get pods -n capx-system

set -euo pipefail

NKP=${NKP:-nkp}
KUBECONFIG_PATH=${KUBECONFIG:-$HOME/.kube/config}

echo "==> Starting nkp create bootstrap (background)..."
$NKP create bootstrap &
NKP_PID=$!

echo "==> Waiting for kind cluster kubeconfig to appear..."
for i in $(seq 1 60); do
    if kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes &>/dev/null 2>&1; then
        echo "    kind cluster is up (attempt $i)"
        break
    fi
    sleep 3
done

echo "==> Waiting for kindnet DaemonSet to exist..."
for i in $(seq 1 30); do
    if kubectl --kubeconfig "$KUBECONFIG_PATH" get daemonset kindnet -n kube-system &>/dev/null 2>&1; then
        echo "    kindnet DaemonSet found (attempt $i)"
        break
    fi
    sleep 3
done

echo "==> Patching kindnet to disable nfnetlink_queue-dependent network policy plugin..."
kubectl --kubeconfig "$KUBECONFIG_PATH" patch daemonset kindnet -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"DISABLE_NETWORK_POLICY","value":"true"}]}]' \
    2>/dev/null || \
kubectl --kubeconfig "$KUBECONFIG_PATH" patch daemonset kindnet -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"DISABLE_NETWORK_POLICY","value":"true"}}]'

echo "==> Recycling kindnet pod to pick up the patch..."
kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod -n kube-system -l app=kindnet --grace-period=0 2>/dev/null || true

echo "==> Waiting for kindnet to come back..."
sleep 5
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod \
    --for=condition=Ready \
    --selector=app=kindnet \
    -n kube-system \
    --timeout=60s

echo "==> Recycling cert-manager-webhook pod..."
kubectl --kubeconfig "$KUBECONFIG_PATH" delete pod \
    -n cert-manager \
    -l app.kubernetes.io/component=webhook \
    --grace-period=0 2>/dev/null || true

echo "==> Waiting for cert-manager-webhook to become Ready..."
kubectl --kubeconfig "$KUBECONFIG_PATH" wait pod \
    --for=condition=Ready \
    --selector=app.kubernetes.io/component=webhook \
    -n cert-manager \
    --timeout=120s

echo "==> cert-manager-webhook is Ready — nkp CAPI init should succeed on its next retry"
echo "==> Waiting for nkp create bootstrap to complete..."
wait $NKP_PID
NKP_EXIT=$?

if [[ $NKP_EXIT -eq 0 ]]; then
    echo ""
    echo "✓ Bootstrap cluster ready!"
    echo ""
    kubectl --kubeconfig "$KUBECONFIG_PATH" get pods -n capi-system
else
    echo ""
    echo "✗ nkp create bootstrap exited with code $NKP_EXIT"
    echo "  Check: kubectl get pods -A | grep -v Running"
    exit $NKP_EXIT
fi
