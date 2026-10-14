---
kind: unit
title: "Lesson 02 — NKP Bootstrap: The Jump Host and Bootstrap Cluster"
name: 2-lesson-prism-bootstrap-unit-1
---

# Lesson 02 — NKP Bootstrap: The Jump Host and Bootstrap Cluster

> **Tier:** 1 — Walkthrough (no playground required)  
> **Purpose:** Prepare the operator workstation (jump host), configure credentials, and create the Bootstrap Cluster that will provision the Management Cluster.

> 📺 **This lesson requires real AHV infrastructure** (Prism Central + AHV cluster).  
> Steps are shown with full command output so you can follow along even without hardware.

---

## What you will do

1. Provision and configure the **jump host** VM on AHV
2. Install operator tooling: Docker, `nkp`, `kubectl`, `helm`, `git`, `k9s`
3. Set required environment variables
4. Run `nkp create bootstrap` — create the temporary kind Bootstrap Cluster
5. Verify CAPI controllers are running inside it

---

## Version reference

| Component | Version |
|---|---|
| NKP CLI (`nkp`) | 2.17.1 |
| Kubernetes (kind bootstrap) | 1.34.x |
| Docker CE | 29.x |
| AOS minimum | 7.3 |
| Prism Central minimum | pc.7.3 |

---

## Part A — Provision the jump host VM

The jump host is a dedicated VM on AHV from which you run all NKP CLI commands. It never becomes a cluster node — it is the operator's workstation.

### A.1 Clone the Rocky Linux image

The jump host uses the same Rocky Linux 9.7 NKP image you uploaded in Lesson 01. Clone it in Prism Central:

1. **Prism Central** → **Compute & Storage** → **VMs** → **Create VM**
2. **Name:** `nkp-jump`
3. **vCPUs:** 4 &nbsp;|&nbsp; **RAM:** 8 GB &nbsp;|&nbsp; **Disk:** clone from `nkp-rocky-9.7-release-cis-...qcow2`, resize to **128 GB**
4. **Network:** attach to your VM network (the same subnet NKP nodes will use)
5. **Guest Customization:** attach a cloud-init ISO (see A.2 below)
6. Power on the VM

### A.2 Cloud-init configuration

Create `user-data.yaml` on your laptop. This cloud-init script matches the reference from [nkp-quickstart](https://github.com/nutanixdev/nkp-quickstart):

```yaml
#cloud-config
users:
  - name: nutanix
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [docker, wheel]
    shell: /bin/bash
    lock_passwd: false
    passwd: "$6$rounds=4096$saltsalt$hashedpassword"  # nutanix/4u — change in production

# Disable the Nutanix Rocky repo (points to Nutanix internal mirrors — not reachable outside)
write_files:
  - path: /etc/yum.repos.d/nutanix_rocky9.repo
    content: |
      [nutanix-rocky9]
      enabled=0

# Add Docker CE repo and install tooling
runcmd:
  - dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  - dnf install -y docker-ce docker-ce-cli containerd.io git tmux jq newt
  - systemctl enable --now docker
  - usermod -aG docker nutanix
  - curl -fsSL https://dl.k8s.io/release/v1.34.3/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
  - curl -fsSL https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm
  - curl -fsSL https://github.com/derailed/k9s/releases/download/v0.32.5/k9s_Linux_amd64.tar.gz | tar xz -C /usr/local/bin k9s
  - curl -fsSL https://downloads.d2iq.com/dkp/v2.17.1/nkp_v2.17.1_linux_amd64.tar.gz | tar xz -C /usr/local/bin/ nkp && chmod +x /usr/local/bin/nkp
```

Package this into a cloud-init ISO and upload it to Prism Central, then attach it to the jump host VM before first boot.

> ℹ️ The Nutanix Rocky image uses [cloud-init](https://cloud-init.io/) for first-boot configuration. Attaching the ISO triggers the script automatically on first power-on.

### A.3 Verify tooling

SSH into the jump host at its assigned IP (default user: `nutanix`, password: `nutanix/4u`):

```bash
ssh nutanix@<jump-host-ip>
```

```bash
nkp version       # v2.17.1
kubectl version --client    # v1.34.3
helm version      # v3.17.3
docker version    # 29.x
k9s version       # v0.32.5
```

---

## Part B — Set environment variables

NKP reads configuration from environment variables. The [nkp-quickstart `nkp-env`](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp-env) file is the canonical reference. Create it on the jump host:

```bash
cat > ~/nkp-env <<'EOF'
# ── Prism Central ─────────────────────────────────────────────────────────────
export NUTANIX_ENDPOINT="10.0.2.32"           # Prism Central IP — no https:// prefix
export NUTANIX_PORT="9440"
export NUTANIX_USER="admin"
export NUTANIX_PASSWORD="your-pc-password"
export NUTANIX_INSECURE=true                  # Set false if PC has a trusted cert

# ── Cluster identity ──────────────────────────────────────────────────────────
export CLUSTER_NAME="nkp-management"          # Used for license key binding

# ── NKP node image ────────────────────────────────────────────────────────────
# Exact filename from Prism Central Images — do NOT change
export NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME="nkp-rocky-9.7-release-cis-1.34.3-20260504011927.qcow2"

# ── Prism Element (AHV cluster) ───────────────────────────────────────────────
export PE_CLUSTER_NAME="your-ahv-cluster-name"    # As shown in Prism Element
export SUBNET_NAME="your-vm-network-name"          # VM network in Prism Central

# ── IP addressing (all must be OUTSIDE the DHCP scope) ───────────────────────
export CONTROL_PLANE_ENDPOINT_IP="10.0.2.50"      # K8s API VIP
export LB_IP_RANGE="10.0.2.51-10.0.2.60"          # MetalLB pool (min 2 IPs)

# ── Storage ───────────────────────────────────────────────────────────────────
export STORAGE_CONTAINER="SelfServiceContainer"    # Prism storage container name

# ── Registry mirror (avoids Docker Hub rate limits) ───────────────────────────
# Use local Harbor if deployed; otherwise omit or use Docker Hub directly
export REGISTRY_MIRROR_URL="registry-1.docker.io"
EOF

# Load the vars
source ~/nkp-env
```

> ⚠️ **IP addressing:** `CONTROL_PLANE_ENDPOINT_IP` and the `LB_IP_RANGE` IPs **must not be in your DHCP pool**. Reserve them as static IPs in your network. The K8s API VIP must be reachable from the jump host.

---

## Part C — Create the Bootstrap Cluster

With Docker running and the environment loaded, create the Bootstrap Cluster:

```bash
source ~/nkp-env
nkp create bootstrap
```

`nkp` uses `kind` to create a single-node Kubernetes cluster on the jump host, then deploys:
- **Cluster API (CAPI)** core controllers
- **CAPX** (Cluster API Provider for Nutanix) — translates `NutanixCluster` / `NutanixMachine` CRDs → Prism Central API calls
- **CAREN** (Cluster API Runtime Extensions for Nutanix) — pre-flight hooks that validate the OS image and storage container exist before provisioning begins

Expected output:

```
INFO[...] Creating bootstrap cluster
INFO[...] Initializing new bootstrap cluster
INFO[...] Installing CAPI components
INFO[...] Waiting for CAPI components to be ready
INFO[...] Bootstrap cluster created
✓ Bootstrap cluster created
```

This takes **2–4 minutes**.

### C.1 Inspect the Bootstrap Cluster

```bash
# kubectl now points at the kind cluster
kubectl get nodes
```

```
NAME                         STATUS   ROLES           AGE   VERSION
nkp-bootstrap-control-plane  Ready    control-plane   90s   v1.34.x
```

```bash
# CAPI core controllers
kubectl get pods -n capi-system
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
capi-controller-manager-xxxx               1/1     Running   0          80s
```

```bash
# Nutanix provider (CAPC)
kubectl get pods -n capc-system
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
capc-controller-manager-xxxx               1/1     Running   0          75s
```

### C.2 Verify Nutanix connectivity

`nkp` validates Prism Central connectivity before using it. You can trigger a manual check:

```bash
nkp check environment --provider nutanix
```

This verifies:
- Prism Central is reachable at `NUTANIX_ENDPOINT:9440`
- Credentials are valid
- The node image exists in the image service
- The subnet exists in Prism Central
- The Prism Element cluster name matches

Fix any errors reported here before proceeding to `nkp create cluster`.

---

## Part D — (Optional) Deploy a local Harbor registry

Docker Hub rate-limits anonymous pulls to **100 per 6 hours**. During repeated `nkp create cluster` cycles this is exhausted in one deployment. A local Harbor instance caches images and eliminates the limit.

```bash
# Deploy Harbor using Docker Compose on the jump host
curl -fsSL https://github.com/goharbor/harbor/releases/download/v2.11.0/harbor-online-installer-v2.11.0.tgz \
    | tar xz
cd harbor
cp harbor.yml.tmpl harbor.yml
# Edit harbor.yml: set hostname to jump host IP, disable HTTPS for lab, set admin password
./install.sh
```

Then update `nkp-env`:

```bash
export REGISTRY_MIRROR_URL="http://<jump-host-ip>:80"
```

> For this course, Harbor setup is optional in home labs — the iximious playground pre-loads all required images into the rootfs images at build time, bypassing Docker Hub entirely.

---

## Summary

| Step | Command | Result |
|---|---|---|
| Verify tooling | `nkp version` | `v2.17.1` |
| Load environment | `source ~/nkp-env` | Credentials and IPs exported |
| Create bootstrap | `nkp create bootstrap` | kind cluster + CAPI running |
| Verify CAPI | `kubectl get pods -n capi-system` | `Running` |
| Verify Nutanix provider | `kubectl get pods -n capc-system` | `Running` |
| Check environment | `nkp check environment --provider nutanix` | All checks pass |

---

## Next steps

➡️ [Lesson 03 — Creating the Management Cluster on AHV](../3.lesson-cluster-create/unit-1.md)
