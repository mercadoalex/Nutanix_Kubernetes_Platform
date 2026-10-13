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
# NOTE: airgap image bundles intentionally excluded — the iximiuz playground
# has full internet access so RKE2 will pull container images at runtime.
# Bundles are 1.7 GB and would exceed the platform's rootfs bake size limit.

FROM rockylinux/rockylinux:9.7

# ── versions (pinned to NKP 2.17 / K8s 1.34.x) ───────────────────────────────
ARG RKE2_VERSION=v1.34.3+rke2r1

# ── base packages ─────────────────────────────────────────────────────────────
RUN dnf install -y epel-release || true
RUN dnf install -y --setopt=install_weak_deps=False \
        systemd \
        openssh-server \
        curl git tmux jq bash-completion \
        vim-minimal less iproute iputils \
    && dnf install -y --setopt=install_weak_deps=False \
        bind-utils nmap-ncat socat \
        iptables nftables \
    && dnf install -y --setopt=install_weak_deps=False iscsi-initiator-utils || true \
    && dnf install -y --setopt=install_weak_deps=False libseccomp || true \
    && dnf install -y --setopt=install_weak_deps=False nfs-utils || true \
    && dnf clean all

# ── sshd setup (required by iximiuz platform — bake tool SSHes in to verify liveness) ──
RUN ssh-keygen -A \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && systemctl enable sshd 2>/dev/null || ln -sf /usr/lib/systemd/system/sshd.service \
        /etc/systemd/system/multi-user.target.wants/sshd.service

# ── disable SELinux (iximiuz ext4 bake cannot handle xattrs) ─────────────────
RUN echo 'SELINUX=disabled' > /etc/selinux/config \
    && echo 'SELINUXTYPE=targeted' >> /etc/selinux/config

# ── enable iscsid (required by Longhorn) ──────────────────────────────────────
# Only create the symlink if the service unit actually exists.
RUN if [ -f /usr/lib/systemd/system/iscsid.service ]; then \
        mkdir -p /etc/systemd/system/multi-user.target.wants && \
        ln -sf /usr/lib/systemd/system/iscsid.service \
            /etc/systemd/system/multi-user.target.wants/iscsid.service; \
    fi

# ── RKE2 agent install ────────────────────────────────────────────────────────
COPY --from=downloads /install.sh /tmp/rke2-install.sh
RUN INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
    INSTALL_RKE2_TYPE="agent" \
    sh /tmp/rke2-install.sh && rm /tmp/rke2-install.sh

# ── sanitize filesystem for iximiuz ext4 bake ────────────────────────────────
# Remove anything the bake tool cannot represent in a flat ext4 image:
#   - dangling symlinks
#   - hardlinks (Rocky RPMs create thousands via .build-id and terminfo)
#   - sockets/pipes/devices (gpg-agent sockets left by RPM %post scriptlets)
RUN find / -xdev -xtype l -delete 2>/dev/null || true \
    && find / -xdev \( -type s -o -type p -o -type b -o -type c \) -delete 2>/dev/null || true \
    && find / -xdev -type f -links +1 2>/dev/null | while read f; do \
        cp -a "$f" /tmp/_hl_break && mv /tmp/_hl_break "$f" || true; \
       done

# ── RKE2 agent config ─────────────────────────────────────────────────────────
# server URL and token are set at runtime by the student (or lab setup script)
RUN mkdir -p /etc/rancher/rke2
COPY worker/config-agent.yaml /etc/rancher/rke2/config.yaml

# ── shell setup ───────────────────────────────────────────────────────────────
RUN echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/bashrc \
    && echo 'alias crictl="crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock"' \
       >> /etc/bashrc

# ── laborant user (required by iximiuz platform) ─────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash laborant \
    && echo 'laborant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs
COPY --chown=1000:1000 worker/labs/ /home/laborant/labs/

WORKDIR /root

CMD ["/sbin/init"]
