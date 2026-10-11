# rootfs/worker/Dockerfile
# vm3, vm4, vm5 — NKP worker nodes
#
# Base: Rocky Linux 9.7 (pinned — same OS as production NKP nodes)
# Role: Runs RKE2 agent (kubelet + kube-proxy). Joins the RKE2 server on vm2.
#       NOT pre-started — students run 'rke2 agent' during Lesson 06.
#
# Build: see build.sh  (from rootfs/ root so downloads/ is in context)
# Target image: ghcr.io/mercadoalex/nkp-worker:latest

# ── downloads stage — pre-fetched files copied in (no curl inside QEMU) ──────
FROM scratch AS downloads
COPY rke2/install.sh                              /install.sh
COPY rke2/rke2-images.linux-amd64.tar.zst        /rke2-images.linux-amd64.tar.zst
COPY rke2/rke2-images-core.linux-amd64.tar.zst   /rke2-images-core.linux-amd64.tar.zst
COPY rke2/rke2-images-cilium.linux-amd64.tar.zst /rke2-images-cilium.linux-amd64.tar.zst

FROM rockylinux/rockylinux:9.7

# ── versions (pinned to NKP 2.17 / K8s 1.34.x) ───────────────────────────────
ARG RKE2_VERSION=v1.34.3+rke2r1

# ── base packages ─────────────────────────────────────────────────────────────
RUN dnf install -y epel-release || true
RUN dnf install -y --setopt=install_weak_deps=False \
        curl git tmux jq bash-completion \
        vim-minimal less iproute iputils \
    && dnf install -y --setopt=install_weak_deps=False \
        bind-utils nmap-ncat socat \
        iptables nftables \
    && dnf install -y --setopt=install_weak_deps=False iscsi-initiator-utils || true \
    && dnf install -y --setopt=install_weak_deps=False container-selinux || true \
    && dnf install -y --setopt=install_weak_deps=False libseccomp || true \
    && dnf install -y --setopt=install_weak_deps=False nfs-utils || true \
    && dnf clean all

# ── enable iscsid (required by Longhorn) ──────────────────────────────────────
# systemctl doesn't work inside a Docker build — create the symlink directly
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /usr/lib/systemd/system/iscsid.service \
        /etc/systemd/system/multi-user.target.wants/iscsid.service

# ── RKE2 agent install ────────────────────────────────────────────────────────
COPY --from=downloads /install.sh /tmp/rke2-install.sh
RUN INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
    INSTALL_RKE2_TYPE="agent" \
    sh /tmp/rke2-install.sh && rm /tmp/rke2-install.sh

# ── RKE2 airgap image bundles ────────────────────────────────────────────────
RUN mkdir -p /var/lib/rancher/rke2/agent/images/
COPY --from=downloads \
    /rke2-images.linux-amd64.tar.zst \
    /rke2-images-core.linux-amd64.tar.zst \
    /rke2-images-cilium.linux-amd64.tar.zst \
    /var/lib/rancher/rke2/agent/images/

# ── RKE2 agent config ─────────────────────────────────────────────────────────
# server URL and token are set at runtime by the student (or lab setup script)
RUN mkdir -p /etc/rancher/rke2
COPY worker/config-agent.yaml /etc/rancher/rke2/config.yaml

# ── shell setup ───────────────────────────────────────────────────────────────
RUN echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/bashrc \
    && echo 'alias crictl="crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock"' \
       >> /etc/bashrc

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs
COPY --chown=1000:1000 worker/labs/ /home/laborant/labs/

WORKDIR /root
