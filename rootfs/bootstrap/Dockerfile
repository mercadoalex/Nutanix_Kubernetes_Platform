# rootfs/bootstrap/Dockerfile
# vm1 — NKP Bootstrap / operator workstation
#
# Base: Ubuntu 24.04 (matches iximious ubuntu-24-04 catalog image)
# Role: Runs the NKP Bootstrap Cluster (kind), hosts operator tooling
#       (nkp CLI, kubectl, helm, flux, k9s, ansible). Does NOT run RKE2.
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
COPY downloads/bootstrap/k9s_Linux_amd64.tar.gz            /k9s.tar.gz

# ── main image ────────────────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION}

# ── versions (pinned — must match fetch.sh) ───────────────────────────────────
ARG NKP_VERSION=2.17.1
ARG KUBECTL_VERSION=1.34.3
ARG HELM_VERSION=3.17.3
ARG FLUX_VERSION=2.5.1
ARG KIND_VERSION=0.27.0
ARG K9S_VERSION=0.32.5
# Docker CE installed from upstream apt repo — internet required for apt at build time
# (apt packages are not practical to pre-stage; Docker is the only online dependency)
ARG DOCKER_VERSION=5:29.0.3-1~ubuntu.24.04~noble

# ── base packages ─────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
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
        python3 \
        python3-pip \
        sshpass \
    && rm -rf /var/lib/apt/lists/*

# ── Ansible (pip — no practical binary alternative) ───────────────────────────
RUN pip3 install --no-cache-dir --break-system-packages ansible

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

# ── k9s (from downloads stage) ────────────────────────────────────────────────
COPY --from=downloads /k9s.tar.gz /tmp/k9s.tar.gz
RUN tar xz -C /usr/local/bin k9s < /tmp/k9s.tar.gz \
    && rm /tmp/k9s.tar.gz

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

# ── lab files ─────────────────────────────────────────────────────────────────
RUN mkdir -p /home/laborant/labs /root/.kube
COPY --chown=1000:1000 rootfs/bootstrap/labs/ /home/laborant/labs/

WORKDIR /home/laborant
