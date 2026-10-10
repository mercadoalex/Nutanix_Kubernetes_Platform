# NKP Demo — Course Project

## Purpose
Learn and teach **NKP (Nutanix Kubernetes Platform)**. This project is an iximious-based interactive course covering NKP deployment, configuration, and operations on AHV.

## NKP Core Architecture

These are the canonical concepts every lesson in this course is built around.
Use these exact terms and definitions consistently across all lesson content.

### Cluster roles

| Term | Spanish (course uses both) | Definition |
|---|---|---|
| **Management Cluster** | Clúster de gestión | The self-managed "brain" of NKP. Hosts all Cluster API controllers and application managers that orchestrate the rest of the fleet. Always exists first; created via `nkp create cluster` + `nkp move`. |
| **Managed / Workload Cluster** | Clúster gestionado / de trabajo | Kubernetes clusters created and fully lifecycle-managed by the Management Cluster. Students interact with these as end-user clusters. |
| **Attached Cluster** | Clúster adjunto | External clusters (EKS, AKS, GKE, on-prem) connected to NKP so the same policies, add-ons, and governance apply to them. **NKP Ultimate only.** |
| **Bootstrap Cluster** | Clúster de arranque | A temporary `kind` cluster that runs on the operator workstation (vm1). Used only during initial cluster creation to host CAPI controllers before the Management Cluster exists. Deleted after `nkp move`. |

### Underlying technology

| Component | Role in NKP |
|---|---|
| **Cluster API (CAPI)** | The foundation. Provides automated lifecycle management (create, scale, upgrade, delete) for all clusters via declarative Kubernetes CRDs (`Cluster`, `Machine`, `MachineDeployment`, etc.). |
| **CAPI Provider: Nutanix** | The AHV-specific CAPI infrastructure provider. Translates `NutanixCluster` / `NutanixMachine` specs into Prism Central API calls to provision real AHV VMs. |
| **RKE2** | The hardened Kubernetes distribution embedded in every NKP node. Provides the actual `kube-apiserver`, `etcd`, `kubelet`, and containerd runtime. |
| **Flux CD** | GitOps engine embedded in NKP. Manages add-on lifecycle (Longhorn, Prometheus, Grafana, cert-manager, etc.) via `HelmRelease` and `Kustomization` resources. |
| **Kommander** | NKP's multi-cluster management layer. Federates policy, RBAC, add-ons, and access control across all Managed and Attached clusters from a single pane. |

### Cluster lifecycle flow

```
Operator workstation (vm1)
│
├─ nkp create bootstrap
│    └─► kind cluster starts on vm1  (Bootstrap Cluster)
│         └─► CAPI + Nutanix provider installed
│
├─ nkp create cluster --provider=nutanix
│    └─► Bootstrap CAPI calls Prism Central API
│         └─► AHV VMs provisioned  [📺 demo only — requires real AHV]
│              └─► RKE2 installed on each VM
│                   └─► Management Cluster is ready
│
├─ nkp move
│    └─► CAPI controllers pivot from Bootstrap → Management Cluster
│         └─► Bootstrap kind cluster is deleted
│
└─ nkp create cluster (repeat for each Workload Cluster)
      └─► Management Cluster's CAPI provisions new AHV VMs
           └─► Workload Cluster joins the fleet
```

### Lab mapping (Flexbox simulation)

The Bootstrap Cluster and the pivot (`nkp move`) steps are fully interactive in the lab.
The AHV VM provisioning step is skipped — RKE2 is pre-installed on vm2–vm5.

```
vm1  →  Bootstrap Cluster (kind)  +  operator workstation
vm2  →  Management Cluster control plane (RKE2 server)
vm3–5 → Management/Workload Cluster workers (RKE2 agents)
```

### NKP editions

| Edition | Cluster types available |
|---|---|
| **NKP Pro** | Management Cluster + Managed Clusters (AHV, vSphere, bare-metal) |
| **NKP Ultimate** | Pro + **Attached Clusters** (EKS, AKS, GKE, any CNCF-conformant cluster) |

---

## Platform: iximious + Flexbox

Lessons run inside **iximious Labs** playgrounds powered by **Firecracker microVMs**.  
For multi-node labs we use **Flexbox** — up to **5 VMs** sharing a flat local network, each with its own kernel, IP address, 2–4 vCPU, and 4–8 GB RAM.

### Flexbox topology (5-VM reference layout)

| VM | Role | IP | rootfs image | RAM |
|----|------|----|-------------|-----|
| `vm1` | Bootstrap / operator workstation | 192.168.0.10 | `nkp-bootstrap.ext4` | 4 GB |
| `vm2` | Management control plane | 192.168.0.11 | `nkp-controlplane.ext4` | 8 GB |
| `vm3` | Worker node 1 | 192.168.0.12 | `nkp-worker.ext4` | 8 GB |
| `vm4` | Worker node 2 | 192.168.0.13 | `nkp-worker.ext4` | 8 GB |
| `vm5` | Worker node 3 | 192.168.0.14 | `nkp-worker.ext4` | 8 GB |

### What the Flexbox topology enables

- Real multi-node RKE2 cluster (1 control plane + 3 workers)
- Real `nkp` bootstrap-and-pivot flow: kind cluster on vm1 → pivot to vm2 management cluster
- Node drain / cordon / eviction across actual separate machines
- Pod scheduling constraints (affinity, taints, tolerations) with observable placement
- Node failure simulation (kill vm4, watch rescheduling)
- MetalLB L2 load balancer on the shared subnet
- CNI real cross-node networking (Cilium / Calico)
- Distributed storage (Longhorn across worker drives)

### Hard blockers — what still requires real AHV

These operations cannot be performed inside the playground and are taught as guided walkthroughs:

| Blocked operation | Reason |
|---|---|
| `nkp create cluster --provider=nutanix` | Requires Prism Central API + AHV hypervisor |
| `.qcow2` image upload to Prism Central | Requires Prism Central image service |
| Nutanix CSI driver (block/file PVCs) | Calls Nutanix DSF storage APIs |
| Nutanix CCM (cloud load balancer VIPs) | Replaced by MetalLB in labs |

---

## Directory Structure

```
nkp_demo/
├── AGENTS.md                        # This file — Bob project context
├── lessons/
│   ├── 00-concepts/                 # READING: NKP architecture, cluster roles, CAPI, editions
│   ├── 01-os-image/                 # TIER 1: Download & upload Rocky image
│   ├── 02-prism-bootstrap/          # TIER 1: nkp bootstrap walkthrough
│   ├── 03-cluster-create/           # TIER 1: nkp create cluster (AHV demo)
│   ├── 04-nkp-cli/                  # TIER 2: nkp CLI, kubeconfig, contexts (1 VM)
│   ├── 05-kubectl-basics/           # TIER 2: Day-2 kubectl operations (1 VM)
│   ├── 06-bootstrap-pivot/          # TIER 3: kind → RKE2 pivot (5 VMs)
│   ├── 07-node-operations/          # TIER 3: drain, cordon, taints (5 VMs)
│   ├── 08-addons-catalog/           # TIER 3: NKP add-ons via Flux HelmReleases
│   ├── 09-gitops-flux/              # TIER 3: full GitOps loop
│   ├── 10-rbac-policy/              # TIER 3: ClusterRoles, OPA/Gatekeeper
│   ├── 11-monitoring/               # TIER 3: Prometheus + Grafana across nodes
│   └── 12-node-failure/             # TIER 3: kill vm4, watch rescheduling
├── rootfs/                          # rootfs image build tooling
│   ├── bootstrap/                   # nkp-bootstrap.ext4 build (vm1)
│   ├── controlplane/                # nkp-controlplane.ext4 build (vm2)
│   └── worker/                      # nkp-worker.ext4 build (vm3–5)
├── playground/                      # iximious Flexbox playground definitions (.yaml)
├── assets/                          # Screenshots, diagrams
└── scripts/                         # Helper shell scripts used in lessons
```

## Lesson Tiers

| Tier | VMs | Description |
|------|-----|-------------|
| **TIER 1** — Walkthrough | 0 | Guided steps with screenshots; no live infra required |
| **TIER 2** — Single-VM interactive | 1 (vm1) | `nkp` CLI + `kubectl` operations against a pre-loaded cluster |
| **TIER 3** — Full Flexbox | 5 | Real distributed K8s topology; students run actual join and operation commands |

## rootfs Images

Each VM boots its own purpose-built rootfs. The cluster is **not** pre-started — binaries and container images are pre-installed so nothing requires internet access at runtime. Students run the actual commands during the lab.

| Image | VM | Pre-installed contents |
|---|---|---|
| `nkp-bootstrap.ext4` | vm1 | `nkp`, `kubectl`, `helm`, `flux`, Docker (for kind), kubeconfig skeleton, lab YAML files |
| `nkp-controlplane.ext4` | vm2 | RKE2 server binary + images, Rocky 9.7 userland, NKP node artifacts |
| `nkp-worker.ext4` | vm3–5 | RKE2 agent binary + images, Rocky 9.7 userland |

## Conventions

- Each lesson folder contains a `README.md` with the lesson body.
- Lesson filenames are zero-padded and kebab-cased: `01-os-image`, `06-bootstrap-pivot`, etc.
- Every lesson header states its **Tier** and **VM count** so readers know what playground to launch.
- Code blocks use fenced triple-backtick with a language tag.
- Version-specific values (NKP version, K8s version, image name) are documented in a table at the top of the relevant lesson.
- Do not rename Nutanix-provided artifacts — NKP tooling depends on exact filenames.
- Blocked/walkthrough steps are clearly marked with a `> 📺 Demo only` blockquote.

## Tech Stack / Platform

- **Playground platform:** iximious Labs (Firecracker microVMs) + Flexbox (multi-VM)
- **Kubernetes engine in labs:** RKE2 v1.34.x (same engine NKP 2.17 embeds) — pinned, never inherited from iximious catalog
- **Kubernetes distribution taught:** NKP (Nutanix Kubernetes Platform)
- **Production node OS:** Rocky Linux 9.7 (CIS Level 1 hardened Nutanix image, `.qcow2`)
- **Lab node OS:** Rocky Linux 9.7 (custom-built rootfs — **not** the iximious catalog image)
- **NKP CLI:** `nkp` v2.17 binary
- **Container runtime:** containerd 2.x (via RKE2, on node VMs); Docker 29 (on vm1 bootstrap, for kind)
- **CNI:** Cilium (NKP default) or Calico
- **Ingress:** Traefik (NKP default Layer 7 ingress controller)
- **Load balancer (lab substitute):** MetalLB L2 (replaces Nutanix CCM; confirmed NKP default for on-prem)
- **Storage (lab substitute):** Longhorn or local-path provisioner (replaces Nutanix CSI)
- **Observability stack:** Prometheus + Thanos + Grafana + Alertmanager
- **Backup / DR:** Velero (bundled NKP add-on)
- **Supported node OS (production):** Rocky Linux, Ubuntu, Flatcar, BYOI

## iximious Catalog vs. Course Custom Images

iximious ships a wide selection of rootfs images for Flexbox VMs. This course uses two of
them as bases and ignores the rest.

> **Rocky Linux in the iximious catalog:** There is exactly **one** Rocky Linux image —
> `rockylinux` — built from the floating `rockylinux:9` Docker tag. This is **Rocky Linux 9**
> (currently tracking 9.x latest). There is no Rocky 8 and no Rocky 10 variant.

| iximious rootfs | OS | Used in this course? | Reason |
|---|---|---|---|
| `rockylinux` | Rocky Linux 9 (floating `:9`) | ✅ **vm2–5 base** | RHEL-compatible; matches NKP 2.17 node OS family — pin to `:9.7` |
| `ubuntu-24-04` | Ubuntu 24.04 LTS | ✅ **vm1 bootstrap** | Best Docker 29 + kind support; operator workstation only |
| `almalinux` | AlmaLinux 9 | ❌ | Alternative RHEL clone; Rocky preferred for NKP fidelity |
| `ubuntu-22-04` | Ubuntu 22.04 LTS | ❌ | Superseded by 24.04 |
| `ubuntu-26-04` | Ubuntu 26.04 (preview) | ❌ | Unstable/nightly; not suitable for pinned course builds |
| `debian-stable` | Debian Bookworm | ❌ | Not RHEL-compatible; no DNF/SELinux parity |
| `debian-testing` | Debian Trixie | ❌ | Rolling release; avoid |
| `fedora` | Fedora (latest) | ❌ | Rolling release; avoid |
| `alpine` | Alpine Linux | ❌ | musl libc — **incompatible** with RKE2 and `nkp` (glibc binaries) |
| `kali-linux` | Kali Linux | ❌ | Security distro; not relevant |
| `nixos` | NixOS | ❌ | Declarative model incompatible with standard systemd/RPM expectations |
| `opensuse-tumbleweed` | openSUSE Tumbleweed | ❌ | Rolling SUSE; not relevant |
| `archlinux` | Arch Linux | ❌ | Rolling; not relevant |
| `incus` | Incus (LXD fork) | ❌ | Nested container/VM manager; not needed — Flexbox already gives us separate VMs |

> ⚠️ The `rockylinux:9` tag is **floating** — it tracks the latest Rocky 9.x patch release.
> The rootfs build must pin the exact minor version using `rockylinux:9.7` to guarantee
> reproducibility across course rebuilds.

### rootfs build approach per VM role

| VM | Base OS for rootfs build | Source |
|---|---|---|
| vm1 (bootstrap) | Ubuntu 24.04 | iximious `ubuntu-24-04` catalog image |
| vm2 (control plane) | Rocky Linux **9.7** | `docker.io/rockylinux:9.7` (pinned tag, not floating `:9`) |
| vm3–5 (workers) | Rocky Linux **9.7** | `docker.io/rockylinux:9.7` (pinned tag, not floating `:9`) |

## NKP Compatibility Matrix

Source: [`nkp_compatibility.json`](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp_compatibility.json) — authoritative version matrix from the nkp-quickstart repo.

| NKP Version | K8s Versions Supported | Rocky Image | AOS Min | Prism Central Min |
|-------------|----------------------|-------------|---------|-------------------|
| **2.18**    | 1.35.x, 1.34.x       | Rocky 9.8 *(inferred)* | 7.5 | pc.7.5 |
| **2.17** ← *this course* | 1.34.x, 1.33.x | Rocky 9.7 | 7.3 | pc.7.3 |
| 2.16        | 1.33.x, 1.32.x       | Rocky 9.6   | 6.10    | pc.2024.2         |
| 2.15        | 1.32.x, 1.31.x       | Rocky 9.5   | 6.10, 7.0, 7.3 | pc.2024.2, pc.2024.3, pc.7.3 |

> Each NKP release supports **two K8s minor versions** — current and one version back.
> Always match the NKP CLI version to the OS image. Mixing versions causes bootstrap failures.

## Jump Host Specification (from nkp-quickstart)

The nkp-quickstart reference architecture uses a dedicated **jump host** VM for running the NKP CLI. This maps directly to vm1 in the Flexbox lab topology.

| Parameter | Production (AHV VM) | Lab equivalent (Flexbox vm1) |
|---|---|---|
| vCPUs | 4 | 2–4 |
| Memory | 8 GB | 4 GB |
| Disk | 128 GB (cloned from Rocky image, resized) | rootfs ext4 image |
| OS | Rocky Linux (NKP image via cloud-init) | Ubuntu 24.04 (iximious catalog) |
| User | `nutanix` (sudo, docker group) | `root` / `laborant` |
| Tools installed | Docker, kubectl, helm, git, tmux, jq | Pre-baked in rootfs |

Key cloud-init details from the reference:
- Disables the Nutanix Rocky repo (`nutanix_rocky9.repo`) and replaces it with the Docker CE repo
- Installs: `docker-ce`, `kubectl`, `helm`, `git`, `tmux`, `jq`, `newt`
- Adds the `nutanix` user to the `docker` and `wheel` groups
- Default SSH password: `nutanix/4u`

## nkp create cluster — Key Flags Reference

From [`nkp-create-mgmt-cluster.sh`](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp-create-mgmt-cluster.sh):

```bash
nkp create cluster nutanix -c $CLUSTER_NAME \
  --endpoint https://$NUTANIX_ENDPOINT:9440 \
  --insecure \
  --control-plane-endpoint-ip $CONTROL_PLANE_ENDPOINT_IP \   # K8s API VIP — must be outside DHCP/IPAM scope
  --kubernetes-service-load-balancer-ip-range $LB_IP_RANGE \ # MetalLB pool — for Kommander dashboard + services
  --control-plane-vm-image $NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME \
  --control-plane-prism-element-cluster $PE_CLUSTER_NAME \
  --control-plane-subnets $SUBNET_NAME \
  --control-plane-replicas 3 \
  --worker-vm-image $NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME \
  --worker-prism-element-cluster $PE_CLUSTER_NAME \
  --worker-subnets $SUBNET_NAME \
  --worker-replicas 4 \
  --csi-storage-container $STORAGE_CONTAINER \
  --csi-hypervisor-attached-volumes=true \
  --self-managed                                              # Creates a self-managed Management Cluster
```

Critical env vars (from [`nkp-env`](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp-env)):

| Variable | Example | Notes |
|---|---|---|
| `CLUSTER_NAME` | `nkp-starter` | Used for license key generation in Pro/Ultimate |
| `NUTANIX_ENDPOINT` | `10.38.207.7` | Prism Central IP — no `https://` prefix |
| `CONTROL_PLANE_ENDPOINT_IP` | `10.38.207.50` | K8s API VIP — **must be outside DHCP scope** |
| `LB_IP_RANGE` | `10.38.141.51-10.38.141.52` | MetalLB pool — at minimum 2 IPs |
| `NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME` | `nkp-rocky-9.5-release-cis-1.32.3-...qcow2` | Exact image filename — do not rename |
| `NUTANIX_STORAGE_CONTAINER_NAME` | `SelfServiceContainer` | Prism storage container for CSI |
| `REGISTRY_MIRROR_URL` | `registry-1.docker.io` | Avoids Docker Hub rate limiting on HPOC |
| `NKP_BUNDLE` | `./container-images/kommander-image-bundle-v2.17.1.tar,...` | Air-gap bundle path |
