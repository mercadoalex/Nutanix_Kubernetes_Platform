# rootfs/controlplane/Dockerfile
# vm2 — NKP Management Cluster control plane node
#
# Base: Rocky Linux 9.7 (pinned — matches NKP 2.17 production node OS exactly)
# Role: Runs RKE2 server (kube-apiserver, etcd, kube-controller-manager,
#       kube-scheduler, kubelet). NOT pre-started — students run 'rke2 server'
#       during Lesson 06.
#
# Build: see build.sh  (from rootfs/ root so downloads/ is in context)
# Target image: ghcr.io/mercadoalex/nkp-controlplane:latest

# ── downloads stage — pre-fetched files copied in (no curl inside QEMU) ──────
FROM scratch AS downloads
COPY rke2/install.sh                         /install.sh
COPY rke2/rke2-images.linux-amd64.tar.zst   /rke2-images.linux-amd64.tar.zst
COPY rke2/rke2-images-core.linux-amd64.tar.zst /rke2-images-core.linux-amd64.tar.zst
COPY rke2/rke2-images-cilium.linux-amd64.tar.zst /rke2-images-cilium.linux-amd64.tar.zst

# Pin to exact minor — never use the floating rockylinux:9 tag
FROM rockylinux/rockylinux:9.6

# ── versions (pinned to NKP 2.17 / K8s 1.34.x) ───────────────────────────────
ARG RKE2_VERSION=v1.34.3+rke2r1
# kubectl is installed separately so students can use it before RKE2 is up
ARG KUBECTL_VERSION=1.34.3

# ── base packages ─────────────────────────────────────────────────────────────
RUN dnf install -y --setopt=install_weak_deps=False \
        curl \
        git \
        tmux \
        jq \
        bash-completion \
        vim \
        less \
        iproute \
        iputils \
        bind-utils \
        nc \
        socat \
        iptables \
        nftables \
        # Longhorn dependency — open-iscsi
        iscsi-initiator-utils \
        # RKE2 / containerd dependencies
        container-selinux \
        libseccomp \
        nfs-utils \
    && dnf clean all

# ── enable iscsid (required by Longhorn) ──────────────────────────────────────
RUN systemctl enable iscsid

# ── kubectl (standalone, for pre-flight use before RKE2 is running) ──────────
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# ── RKE2 server install ───────────────────────────────────────────────────────
# Uses pre-downloaded installer from rke2/install.sh (COPY is faster
# than curl inside QEMU emulation on Apple Silicon).
# To refresh: curl -fsSL https://get.rke2.io -o rke2/install.sh
COPY --from=downloads /install.sh /tmp/rke2-install.sh
RUN INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
    INSTALL_RKE2_TYPE="server" \
    sh /tmp/rke2-install.sh && rm /tmp/rke2-install.sh

# ── RKE2 airgap image bundles ────────────────────────────────────────────────
# Pre-downloaded to rke2/ — copied in directly (no in-build curl).
# To refresh: see rke2/ directory or rootfs/README.md
RUN mkdir -p /var/lib/rancher/rke2/agent/images/
COPY --from=downloads \
    /rke2-images.linux-amd64.tar.zst \
    /rke2-images-core.linux-amd64.tar.zst \
    /rke2-images-cilium.linux-amd64.tar.zst \
    /var/lib/rancher/rke2/agent/images/

# ── RKE2 server config ────────────────────────────────────────────────────────
# Writes the default server config. The token is set at runtime by the lab
# setup script (or manually by the student) so VMs can join the cluster.
RUN mkdir -p /etc/rancher/rke2
COPY controlplane/config-server.yaml /etc/rancher/rke2/config.yaml

# ── shell setup ───────────────────────────────────────────────────────────────
# RKE2 writes its kubeconfig to /etc/rancher/rke2/rke2.yaml after first start.
# Add a convenience symlink so kubectl picks it up automatically.
RUN echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> /etc/bashrc \
    && echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/bashrc \
    && echo 'source <(kubectl completion bash)' >> /etc/bashrc \
    && echo 'alias k=kubectl' >> /etc/bashrc

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs
COPY --chown=1000:1000 controlplane/labs/ /home/laborant/labs/

WORKDIR /root
