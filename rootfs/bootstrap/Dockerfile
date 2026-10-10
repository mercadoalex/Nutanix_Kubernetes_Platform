# rootfs/bootstrap/Dockerfile
# vm1 — NKP Bootstrap / operator workstation
#
# Base: Ubuntu 24.04 (matches iximious ubuntu-24-04 catalog image)
# Role: Runs the NKP Bootstrap Cluster (kind), hosts operator tooling
#       (nkp CLI, kubectl, helm, flux). Does NOT run RKE2.
#
# Build: see build.sh
# Target image: nkp-bootstrap.ext4

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# ── versions (all pinned) ─────────────────────────────────────────────────────
ARG NKP_VERSION=2.17.1
ARG KUBECTL_VERSION=1.34.3
ARG HELM_VERSION=3.17.3
ARG FLUX_VERSION=2.5.1
ARG KIND_VERSION=0.27.0
ARG K9S_VERSION=0.32.5
# Docker CE is installed from the upstream repo — version matches iximious catalog
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

# ── Ansible ───────────────────────────────────────────────────────────────────
RUN pip3 install --no-cache-dir --break-system-packages ansible

# ── Docker CE (needed to run kind bootstrap cluster) ─────────────────────────
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

# ── kubectl ───────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# ── helm ──────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm

# ── flux CLI ─────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C /usr/local/bin flux

# ── kind ──────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64" \
        -o /usr/local/bin/kind \
    && chmod +x /usr/local/bin/kind

# ── k9s (TUI cluster explorer) ────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
    | tar xz -C /usr/local/bin k9s

# ── nkp CLI ──────────────────────────────────────────────────────────────────
# The nkp v2.17.x standalone binary is publicly available from the D2iQ CDN.
# NKP is the renamed D2iQ DKP product; this URL requires no login or portal account.
#
# The binary is downloaded directly during the Docker build — no pre-placement needed.
# If you prefer to supply it manually (e.g. for a custom/patched build), place the
# binary at rootfs/bootstrap/nkp and comment out the RUN line below, uncommenting
# the COPY line instead.
RUN curl -fsSL \
        "https://downloads.d2iq.com/dkp/v${NKP_VERSION}/nkp_v${NKP_VERSION}_linux_amd64.tar.gz" \
        | tar xz -C /usr/local/bin/ nkp \
    && chmod +x /usr/local/bin/nkp
# COPY --chown=root:root nkp /usr/local/bin/nkp

# ── shell setup ───────────────────────────────────────────────────────────────
RUN echo 'source <(kubectl completion bash)' >> /etc/bash.bashrc \
    && echo 'source <(nkp completion bash)'  >> /etc/bash.bashrc \
    && echo 'source <(helm completion bash)' >> /etc/bash.bashrc \
    && echo 'alias k=kubectl'               >> /etc/bash.bashrc

# ── lab files (populated during image build) ──────────────────────────────────
RUN mkdir -p /home/laborant/labs /root/.kube
COPY --chown=1000:1000 labs/ /home/laborant/labs/

WORKDIR /home/laborant
