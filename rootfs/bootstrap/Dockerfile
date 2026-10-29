# rootfs/bootstrap/Dockerfile
# vm1 — NKP Bootstrap / operator workstation
#
# Base: Ubuntu 24.04 (matches iximious ubuntu-24-04 catalog image)
# Role: Runs the NKP Bootstrap Cluster (kind), hosts operator tooling
#       (nkp CLI, kubectl, helm, flux). Does NOT run RKE2.
#       k9s is NOT pre-installed (saves 91 MB) — install at runtime if needed:
#         curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar xz -C /usr/local/bin k9s
#       ansible is NOT pre-installed — no course content uses it yet.
#
# Build: run from rootfs/ root so downloads/bootstrap/ is in context
#   cd rootfs && bash bootstrap/build.sh
#
# Pre-requisite: all binaries must be pre-downloaded first:
#   cd downloads/bootstrap && bash fetch.sh
#
# Target image: ghcr.io/mercadoalex/nkp-bootstrap:latest

# ── global ARGs (must be before first FROM to be usable in FROM instructions) ─
ARG UBUNTU_VERSION=24.04

# ── downloads stage — pre-fetched binaries copied in (no curl inside build) ──
FROM scratch AS downloads
COPY downloads/bootstrap/kubectl                           /kubectl
COPY downloads/bootstrap/kind                              /kind
COPY downloads/bootstrap/nkp_v2.17.1_linux_amd64.tar.gz   /nkp.tar.gz
COPY downloads/bootstrap/helm-v3.17.3-linux-amd64.tar.gz  /helm.tar.gz
COPY downloads/bootstrap/flux_2.5.1_linux_amd64.tar.gz    /flux.tar.gz

# ── main image ────────────────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION}

# ── versions (pinned — must match fetch.sh) ───────────────────────────────────
ARG NKP_VERSION=2.17.1
ARG KUBECTL_VERSION=1.34.3
ARG HELM_VERSION=3.17.3
ARG FLUX_VERSION=2.5.1
ARG KIND_VERSION=0.27.0
# Docker CE installed from upstream apt repo — internet required for apt at build time
# (apt packages are not practical to pre-stage; Docker is the only online dependency)
ARG DOCKER_VERSION=5:29.0.3-1~ubuntu.24.04~noble

# ── base packages ─────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        sudo \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        tmux \
        jq \
        unzip \
        bash-completion \
        vim \
        less \
        iproute2 \
        iputils-ping \
        dnsutils \
        netcat-openbsd \
        socat \
        openssh-client \
        openssh-server \
    && rm -rf /var/lib/apt/lists/*

# ── Docker CE (apt repo — only remaining online step) ─────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo \
       "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce=${DOCKER_VERSION} \
        docker-ce-cli=${DOCKER_VERSION} \
        containerd.io \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ── Docker daemon config for Firecracker microVM kernels ─────────────────────
# Firecracker kernels are minimal — two iptables limitations apply:
#   1. nf_tables module missing  → use iptables-legacy backend
#   2. 'raw' table missing       → Docker's DIRECT ACCESS FILTERING and
#      LOOPBACK FILTERING rules both insert into the raw table and fail with
#      "Table does not exist". Setting "allow-direct-routing": true tells
#      Docker to skip both raw-table rules entirely. Confirmed working on
#      Firecracker via iximious platform testing.
RUN update-alternatives --set iptables  /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
    && mkdir -p /etc/docker \
    && printf '{\n  "allow-direct-routing": true,\n  "userland-proxy": true,\n  "exec-opts": ["native.cgroupdriver=systemd"]\n}\n' \
       > /etc/docker/daemon.json

# ── kubectl (from downloads stage) ───────────────────────────────────────────
COPY --from=downloads /kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

# ── helm (from downloads stage) ───────────────────────────────────────────────
COPY --from=downloads /helm.tar.gz /tmp/helm.tar.gz
RUN tar xz --strip-components=1 -C /usr/local/bin \
        linux-amd64/helm < /tmp/helm.tar.gz \
    && rm /tmp/helm.tar.gz

# ── flux CLI (from downloads stage) ──────────────────────────────────────────
COPY --from=downloads /flux.tar.gz /tmp/flux.tar.gz
RUN tar xz -C /usr/local/bin flux < /tmp/flux.tar.gz \
    && rm /tmp/flux.tar.gz

# ── kind (from downloads stage) ───────────────────────────────────────────────
COPY --from=downloads /kind /usr/local/bin/kind
RUN chmod +x /usr/local/bin/kind

# ── nkp CLI (from downloads stage) ───────────────────────────────────────────
COPY --from=downloads /nkp.tar.gz /tmp/nkp.tar.gz
RUN tar xz -C /usr/local/bin/ nkp < /tmp/nkp.tar.gz \
    && chmod +x /usr/local/bin/nkp \
    && rm /tmp/nkp.tar.gz

# ── shell setup ───────────────────────────────────────────────────────────────
RUN echo 'source <(kubectl completion bash)' >> /etc/bash.bashrc \
    && echo 'source <(nkp completion bash)'  >> /etc/bash.bashrc \
    && echo 'source <(helm completion bash)' >> /etc/bash.bashrc \
    && echo 'alias k=kubectl'               >> /etc/bash.bashrc

# ── laborant user (required by iximiuz platform) ─────────────────────────────
# Ubuntu 24.04 ships with an 'ubuntu' user at UID 1000. Rename it to 'laborant'
# so the iximiuz platform finds the expected user in /etc/passwd.
RUN usermod -l laborant -d /home/laborant -m ubuntu \
    && groupmod -n laborant ubuntu \
    && echo 'laborant ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && usermod -aG docker laborant

# ── enable Docker and SSH at boot ─────────────────────────────────────────────
RUN systemctl enable docker \
    && systemctl enable ssh

# ── sanitize filesystem for iximiuz ext4 bake ────────────────────────────────
# Ubuntu-specific rules (different from Rocky):
# 1. Delete sockets/pipes from apt %post scriptlets
# 2. Break hardlinks under /usr (Ubuntu has ~8, mostly Python pyc)
# 3. Delete /usr/share/doc entirely — all 74 dangling symlinks live here
#    (compressed changelog/NEWS files pointing to absent gz targets).
#    Safe to remove: doc files are never needed at runtime.
# NOTE: do NOT run 'find / -xdev -xtype l -delete' on Ubuntu — it kills
#    /sbin/init -> ../lib/systemd/systemd and other valid runtime symlinks.
RUN find /run /tmp /var/run -maxdepth 5 \( -type s -o -type p \) -delete 2>/dev/null || true \
    && find /usr -xdev -type f -links +1 2>/dev/null | while IFS= read -r f; do \
        [ -n "$f" ] && [ -f "$f" ] || continue; \
        cp -a "$f" /tmp/_hl_break 2>/dev/null && mv -f /tmp/_hl_break "$f" 2>/dev/null || true; \
       done \
    && rm -rf /usr/share/doc /usr/share/locale \
    && rm -f /var/log/README /etc/modules-load.d/modules.conf /etc/vconsole.conf

# ── sshd setup (required by iximiuz platform — bake tool SSHes in to verify liveness) ──
RUN sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs /root/.kube
COPY --chown=1000:1000 rootfs/bootstrap/labs/ /home/laborant/labs/

WORKDIR /home/laborant

CMD ["/sbin/init"]
