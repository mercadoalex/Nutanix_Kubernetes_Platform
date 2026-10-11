#!/usr/bin/env bash
# downloads/bootstrap/fetch.sh
#
# Pre-download all binaries needed to build the nkp-bootstrap rootfs image.
# Run this ONCE before building — subsequent builds are fully offline.
#
# Usage:
#   cd downloads/bootstrap && bash fetch.sh
#   cd rootfs && bash bootstrap/build.sh
#
# All files land in downloads/bootstrap/ alongside this script.
# The Dockerfile copies them in via a scratch downloads stage — no curl at build time.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

NKP_VERSION=2.17.1
KUBECTL_VERSION=1.34.3
HELM_VERSION=3.17.3
FLUX_VERSION=2.5.1
KIND_VERSION=0.27.0
K9S_VERSION=0.32.5

echo "── Fetching bootstrap tool binaries ─────────────────────────────────────────"

# ── nkp CLI ──────────────────────────────────────────────────────────────────
if [[ ! -f "nkp_v${NKP_VERSION}_linux_amd64.tar.gz" ]]; then
    echo "→ nkp v${NKP_VERSION}"
    # Check if already downloaded at the top-level downloads/ directory
    if [[ -f "../nkp_v${NKP_VERSION}_linux_amd64.tar.gz" ]]; then
        cp "../nkp_v${NKP_VERSION}_linux_amd64.tar.gz" .
        echo "  (copied from downloads/)"
    else
        curl -fsSL \
            "https://downloads.d2iq.com/dkp/v${NKP_VERSION}/nkp_v${NKP_VERSION}_linux_amd64.tar.gz" \
            -o "nkp_v${NKP_VERSION}_linux_amd64.tar.gz"
    fi
else
    echo "✓ nkp v${NKP_VERSION} already present"
fi

# ── kubectl ───────────────────────────────────────────────────────────────────
if [[ ! -f "kubectl" ]]; then
    echo "→ kubectl v${KUBECTL_VERSION}"
    curl -fsSL \
        "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o kubectl
    chmod +x kubectl
else
    echo "✓ kubectl already present"
fi

# ── helm ──────────────────────────────────────────────────────────────────────
if [[ ! -f "helm-v${HELM_VERSION}-linux-amd64.tar.gz" ]]; then
    echo "→ helm v${HELM_VERSION}"
    curl -fsSL \
        "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
        -o "helm-v${HELM_VERSION}-linux-amd64.tar.gz"
else
    echo "✓ helm already present"
fi

# ── flux CLI ──────────────────────────────────────────────────────────────────
if [[ ! -f "flux_${FLUX_VERSION}_linux_amd64.tar.gz" ]]; then
    echo "→ flux v${FLUX_VERSION}"
    curl -fsSL \
        "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" \
        -o "flux_${FLUX_VERSION}_linux_amd64.tar.gz"
else
    echo "✓ flux already present"
fi

# ── kind ──────────────────────────────────────────────────────────────────────
if [[ ! -f "kind" ]]; then
    echo "→ kind v${KIND_VERSION}"
    curl -fsSL \
        "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64" \
        -o kind
    chmod +x kind
else
    echo "✓ kind already present"
fi

# ── k9s ───────────────────────────────────────────────────────────────────────
if [[ ! -f "k9s_Linux_amd64.tar.gz" ]]; then
    echo "→ k9s v${K9S_VERSION}"
    curl -fsSL \
        "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
        -o "k9s_Linux_amd64.tar.gz"
else
    echo "✓ k9s already present"
fi

echo ""
echo "── Verify checksums (optional) ──────────────────────────────────────────────"
echo "  kubectl:  $(sha256sum kubectl | cut -d' ' -f1)"
echo "  kind:     $(sha256sum kind | cut -d' ' -f1)"
echo ""
echo "✓ All bootstrap binaries ready in $(pwd)"
echo "  Next: cd ../../rootfs && bash bootstrap/build.sh"
