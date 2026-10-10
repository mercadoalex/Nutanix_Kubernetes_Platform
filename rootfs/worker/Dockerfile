# rootfs/worker/Dockerfile
# vm3, vm4, vm5 — NKP worker nodes
#
# Base: Rocky Linux 9.7 (pinned — same OS as production NKP nodes)
# Role: Runs RKE2 agent (kubelet + kube-proxy). Joins the RKE2 server on vm2.
#       NOT pre-started — students run 'rke2 agent' during Lesson 06.
#
# Build: see build.sh  (single image used for all three worker VMs)
# Target image: nkp-worker.ext4

FROM rockylinux:9.7

# ── versions (pinned to NKP 2.17 / K8s 1.34.x) ───────────────────────────────
ARG RKE2_VERSION=v1.34.3+rke2r1

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

# ── RKE2 agent install ────────────────────────────────────────────────────────
RUN curl -sfL https://get.rke2.io | \
    INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
    INSTALL_RKE2_TYPE="agent" \
    sh -

# ── pre-pull RKE2 agent container images (airgap prep) ───────────────────────
RUN mkdir -p /var/lib/rancher/rke2/agent/images/ \
    && curl -fsSL \
       "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-amd64.tar.zst" \
       -o /var/lib/rancher/rke2/agent/images/rke2-images.linux-amd64.tar.zst \
    && curl -fsSL \
       "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-core.linux-amd64.tar.zst" \
       -o /var/lib/rancher/rke2/agent/images/rke2-images-core.linux-amd64.tar.zst \
    && curl -fsSL \
       "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-cilium.linux-amd64.tar.zst" \
       -o /var/lib/rancher/rke2/agent/images/rke2-images-cilium.linux-amd64.tar.zst

# ── RKE2 agent config ─────────────────────────────────────────────────────────
# server URL and token are set at runtime by the student (or lab setup script)
RUN mkdir -p /etc/rancher/rke2
COPY config-agent.yaml /etc/rancher/rke2/config.yaml

# ── shell setup ───────────────────────────────────────────────────────────────
RUN echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/bashrc \
    && echo 'alias crictl="crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock"' \
       >> /etc/bashrc

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs
COPY --chown=1000:1000 labs/ /home/laborant/labs/

WORKDIR /root
