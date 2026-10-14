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
| **Cluster API (CAPI)** | The foundation. Provider-agnostic framework for declarative cluster lifecycle (`Cluster`, `Machine`, `MachineDeployment`, `RKE2ControlPlane` CRDs). |
| **CAPX** | *Cluster API Provider for Nutanix* (`cluster-api-provider-nutanix`). AHV-specific CAPI infrastructure provider. Watches `NutanixCluster`/`NutanixMachine` CRDs → calls Prism Central API to provision AHV VMs. Namespace: `capx-system`. |
| **CAREN** | *Cluster API Runtime Extensions for Nutanix* (`cluster-api-runtime-extensions-nutanix`). Lifecycle hook server. Intercepts `BeforeClusterCreate`, `BeforeClusterUpgrade`, `BeforeClusterDelete` events to validate Nutanix resources and inject CNI/CCM. Namespace: `caren-system`. |
| **RKE2** | The hardened Kubernetes distribution embedded in every NKP node. Provides the actual `kube-apiserver`, `etcd`, `kubelet`, and containerd runtime. |
| **Flux CD** | GitOps engine embedded in NKP. Manages add-on lifecycle (Longhorn, Prometheus, Grafana, cert-manager, etc.) via `HelmRelease` and `Kustomization` resources. |
| **Kommander** | NKP's multi-cluster management layer. Federates policy, RBAC, add-ons, and access control across all Managed and Attached clusters from a single pane. |

### Nutanix infrastructure layer (NCI)

NKP runs on top of the Nutanix Cloud Infrastructure (NCI) stack. Use these exact terms:

| Term | Definition | NKP connection |
|---|---|---|
| **NCI** (Nutanix Cloud Infrastructure) | Nutanix's infrastructure product tier. Contains AOS Storage, AHV Virtualization, Disaster Recovery, Flow, and NC2. Does **not** include Prism Central (that's *Nutanix Central*) or NKP/NDK (separate products). | NKP node VMs run on AHV (NCI); storage from AOS (NCI); managed via Prism Central (Nutanix Central) |
| **AHV** | KVM-based hypervisor. Part of NCI. Hosts all NKP node VMs. | CAPX provisions VMs on AHV via Prism Central API |
| **AOS** | FreeBSD-based storage OS running inside the CVM (Controller VM) on every node. Part of NCI. Provides distributed filesystem, snapshots, replication, dedup, compression. | Nutanix CSI driver + NDK read/write to AOS |
| **CVM** (Controller VM) | The per-node Nutanix storage controller VM. Runs AOS. Never shut down unless Nutanix support instructs. | Transparent to NKP; CSI/NDK talk to AOS via CVM |
| **Prism Central (PC)** | Multi-cluster management UI and REST API. Part of **Nutanix Central** (not NCI). CAPX/CAREN call `https://<PC_IP>:9440`. | Required for `nkp create cluster --endpoint` |
| **NDK** (Nutanix Data Services for Kubernetes) | Extends AOS enterprise storage features (snapshots, replication, tiering, dedup) to K8s `PersistentVolume` objects via CRDs (`DataServicePolicy`, `ProtectionPolicy`). | Alternative/complement to the CSI driver for stateful workloads |
| **Nutanix CSI Driver** | Standard K8s CSI driver. Translates `PersistentVolumeClaim` → AOS volume/file share. | Installed as NKP add-on; replaced by Longhorn in lab |
| **NKP Metal** | Extends NKP to bare-metal nodes (dual-native: VMs + containers). Announced April 2026. | Same nkp CLI + Kommander; bare-metal CAPI provider replaces CAPX |

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
│   ├── 00b-community-edition/       # WALKTHROUGH: Install CE 2.1 on bare metal, LCM upgrade to AOS 7.3
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
│   ├── 12-node-failure/             # TIER 3: kill vm4, watch rescheduling
│   └── 13-gpu/                      # MIXED: AHV GPU passthrough (walkthrough) + GPU Operator + time-slicing + MIG + lab sim
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

## rootfs Build Rules — iximious ext4 Bake Compatibility

> ⚠️ **Status: check-bake.sh passes locally; live playground boot not yet confirmed.**
> All three images pass the preflight script (0 hardlinks, 0 dangling symlinks, sshd ✓).
> The RootfsBaked result on the actual iximious platform is still unverified — update this
> section once a playground boot confirms `RootfsBaked: True` on all 5 VMs.

The iximious platform converts OCI images to raw ext4 rootfs images at playground start time (the `RootfsBaked` condition). This bake step is strict — certain filesystem constructs that are valid in a container image will cause `RootfsBaked: False` and abort the playground.

### What the bake tool cannot handle

| Filesystem construct | Cause in Rocky Linux images | Fix applied in Dockerfiles |
|---|---|---|
| **Dangling symlinks** | RPM `.build-id` symlinks point to absent cross-arch binaries (ppc64le, s390x, aarch64); orphaned `alternatives` entries (`nc-man`, `soelim`) | `find / -xdev -xtype l -delete` — runs **after** hardlink-breaking and **after** sshd setup |
| **Unix sockets / pipes** | `gpg-agent` sockets left by RPM `%post` scriptlets (`rke2-selinux`, `container-selinux`) in `/run` | `find /run /tmp /var/run -maxdepth 5 \( -type s -o -type p \) -delete` — runs first |
| **Hardlinks** | Rocky RPMs create hardlinks across terminfo (33), zoneinfo (1105), Python `__pycache__` (1226+), crypto-policies, gcc/gdb share dirs, perl, getconf — **1393+ total** | `find /usr -xdev -type f -links +1` loop with `cp -a + mv` — must scan all of `/usr`, not just known subdirs |
| **SELinux xattrs** | `selinux-policy-targeted` + `container-selinux` write xattrs during `%post` | `SELINUX=disabled` in `/etc/selinux/config` |

> ⚠️ Ubuntu-based images (vm1 bootstrap) do not have these issues — apt packages do not create hardlinks, sockets, or SELinux xattrs. The Rocky Linux images (vm2–vm5) require the full sanitization step.

### Rocky Linux 9.7 base image trap — `curl-minimal` conflict

`rockylinux:9.7` ships `curl-minimal` pre-installed. It **conflicts** with `curl`. Without `--allowerasing`, any `dnf install` that includes `curl` (directly or as a dep) will **abort the entire transaction silently** — every package in that RUN step, including `openssh-server`, ends up never installed. There is no error about `openssh-server`; the only error mentions `curl-minimal`.

**Fix:** always pass `--allowerasing` on the first `dnf install` in Rocky Dockerfiles:

```dockerfile
RUN dnf install -y --setopt=install_weak_deps=False --allowerasing \
        systemd openssh-server curl git tmux ...
```

This replaces `curl-minimal` with `curl` and allows the full transaction to succeed.

### Mandatory sanitization RUN step (Rocky images only)

Must run **after all package installs and after RKE2 install**, but **before** the sshd setup step. The hardlink-breaker writes to `/tmp/_hl_break` — the socket/pipe deletion runs first to avoid leaving stale socket files from that temp write.

```dockerfile
# ── sanitize filesystem for iximiuz ext4 bake ────────────────────────────────
# 1. Delete sockets/pipes left by RPM %post scriptlets.
# 2. Break ALL hardlinks under /usr — covers terminfo, zoneinfo, Python pyc,
#    crypto-policies, gcc/gdb share dirs, perl, getconf, and anything else
#    RPM packages create.  The cp-a+mv pattern is safe: executables in
#    /usr/bin and /usr/sbin have link-count 1 after RPM install.
# 3. Delete dangling symlinks — .build-id entries for absent cross-arch
#    binaries (ppc64le, s390x, aarch64), orphaned alternatives entries, etc.
RUN find /run /tmp /var/run -maxdepth 5 \( -type s -o -type p \) -delete 2>/dev/null || true \
    && find /usr -xdev -type f -links +1 2>/dev/null | while IFS= read -r f; do \
        [ -n "$f" ] && [ -f "$f" ] || continue; \
        cp -a "$f" /tmp/_hl_break 2>/dev/null && mv -f /tmp/_hl_break "$f" 2>/dev/null || true; \
       done \
    && find / -xdev -xtype l -delete 2>/dev/null || true

# ── sshd setup — MUST come AFTER sanitization ────────────────────────────────
# The bake tool SSHes into the VM after boot to verify liveness.
# Rocky Linux does not ship sshd by default — openssh-server must be installed
# (it will be, if --allowerasing is used above) and host keys generated here.
RUN ssh-keygen -A \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && ln -sf /usr/lib/systemd/system/sshd.service \
        /etc/systemd/system/multi-user.target.wants/sshd.service
```

**Why sshd setup must run after sanitization:** the dangling-symlink deletion step
(`find / -xdev -xtype l -delete`) removes the sshd systemd symlink we just created if it runs
after sshd setup. The hardlink-breaker is safe before or after — executables are never hardlinked.

### Hardlink scope: must be all of `/usr`, not a list of known dirs

Early attempts scoped the hardlink-breaker to `/usr/share/terminfo /usr/share/zoneinfo /usr/lib/.build-id`. This missed ~1,231 hardlinks:

| Source | Count (approximate) |
|---|---|
| `/usr/lib64/python3.9/__pycache__` and subdirs | 1,020 |
| `/usr/lib/python3.9/` (dnf plugin pyc files) | 206 |
| `/usr/share/crypto-policies/back-ends/` | ~20 |
| `/usr/share/gcc-11/`, `/usr/share/gdb/` | ~10 |
| `/usr/libexec/getconf/`, `/usr/bin/perl` | 5 |

Use `find /usr -xdev -type f -links +1` — this catches everything without risking system directories outside `/usr`.

### Pre-flight check before every push

Run `bash rootfs/check-bake.sh all` before pushing any image. This script catches all four failure categories locally — **never push without running it first**. It is also wired into `make controlplane`, `make worker`, and `make bootstrap` and will block the push if any check fails.

```bash
cd rootfs && bash check-bake.sh all
# or via make (runs automatically before push):
cd rootfs && make controlplane worker
```

### Why the bake fails simultaneously on all Rocky VMs

All Rocky VMs fail `RootfsBaked` at the **exact same nanosecond** — this is a deterministic pre-scan rejection at the OCI layer level, not a per-file scan. The bake tool inspects the image before extracting it. Any of the four constructs above triggers immediate rejection of the entire image.

### Current image state (last updated: commit 3c4b89a)

| Image | Size | Hardlinks | Dangling symlinks | sshd | check-bake.sh | Live bake |
|---|---|---|---|---|---|---|
| `nkp-bootstrap:latest` | ~1.1 GB | ✓ 0 | ✓ 0 | ✓ | ✅ PASS | ❓ unverified |
| `nkp-controlplane:latest` | 859 MB | ✓ 0 | ✓ 0 | ✓ | ✅ PASS | ❓ unverified |
| `nkp-worker:latest` | 802 MB | ✓ 0 | ✓ 0 | ✓ | ✅ PASS | ❓ unverified |

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
- **Local container registry (lab):** Harbor (avoids Docker Hub rate limits — 100 pulls/6h anon, 200 pulls/6h free account)
- **Operator tooling:** `k9s` (TUI cluster explorer), `kubectl`, `nkp`, `helm`, `flux`
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

## Nutanix Community Edition (CE) — Home Lab Platform

CE is the free Nutanix stack used in home labs. Key facts for this course:

| Item | Detail |
|---|---|
| CE version | **2.1** (released 2024-08-19) |
| Bundled AOS | 6.8.1 |
| Installer | ISO → USB via **Rufus v3.21 exactly** (other versions fail) |
| ISO URL | `https://download.nutanix.com/ce/2024.08.19/phoenix.x86_64-fnd_5.6.1_patch-aos_6.8.1_ga.iso` |
| Upgrade path from old CE | ❌ None — fresh install only |
| LCM upgrades | ✅ Works directly (same build as commercial AOS) |
| Prism Central | ✅ Compatible with commercial PC build |
| NKP 2.17 readiness | ❌ Out of box — AOS 6.8.1 is below the 7.3 minimum. **Must LCM-upgrade to AOS 7.3 before installing NKP.** |

**Post-install upgrade sequence required for NKP 2.17:**
```
CE 2.1 (AOS 6.8.1)  →  LCM: AHV upgrade  →  LCM: AOS 7.3  →  Deploy PC pc.7.3  →  NKP ready
```

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

## Docker Hub Rate Limits — Why Harbor Matters

NKP cluster creation pulls a large number of container images. Docker Hub enforces:

| Account type | Pull limit |
|---|---|
| Anonymous | 100 pulls / 6 hours |
| Free (authenticated) | 200 pulls / 6 hours |
| Pro / Team | Unlimited |

During iterative lab deployments (repeated `nkp create cluster` / destroy cycles), anonymous pulls are exhausted within one deployment. The reference solution from Jonas Högman's series is a **local Harbor registry** that proxies Docker Hub, caching images locally. The `REGISTRY_MIRROR_URL` env var in `nkp-env` points `nkp create cluster` at this local mirror.

In the Flexbox lab, Harbor is pre-loaded into the `nkp-bootstrap.ext4` rootfs or run as a separate service VM. All container images used in lessons must be pre-pulled into Harbor at rootfs build time.

## NKP POC / Trial License

NKP Pro/Ultimate features (Kommander multi-cluster, Attached Clusters, etc.) require a license. For lab use:

1. Log in to [portal.nutanix.com](https://portal.nutanix.com)
2. Hamburger menu → **Licenses**
3. → **Non-Production Licenses** → **Request POC License**
4. Select **NKP Ultimate** → follow on-screen steps
5. Apply in Kommander: **Licensing** → remove existing → **+ Activate License** → enter your key
6. Add your cluster name (must match `CLUSTER_NAME` exactly — used for license key binding)

A **30-day POC license** from the support portal is sufficient to explore the full NKP Ultimate feature set.

Jeroen Tielen also notes: *"Enable the 90 day ultimate trial and you can play with all the cool features. That would be enough to learn the whole stack and get certified."*

## k9s — Cluster Explorer

`k9s` is a terminal UI for Kubernetes. It is a critical lab tool — used to watch pods being created during `nkp create cluster` in real time.

```bash
# Install on vm1 (Ubuntu)
curl -fsSL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz \
  | tar xz -C /usr/local/bin k9s

# Use during cluster deployment to watch what's happening
k9s --kubeconfig="/home/laborant/labs/mgmt.kubeconfig"
```

Add `k9s` to the bootstrap rootfs (add to [`rootfs/bootstrap/Dockerfile`](rootfs/bootstrap/Dockerfile) ARG list and install step).

## Workload Cluster — UI Path (Kommander)

Jonas Högman's series documents creating Workload Clusters via the Kommander dashboard (alternative to the `nkp` CLI):

1. Kommander Dashboard → **Clusters** → **+ Add Cluster** → **Create New Cluster**
2. Set workspace, cluster name, SSH public key
3. **Control Plane pool:** Prism Central project, AOS cluster, OS image, VIP, replica count (≥3 for production)
4. **Worker pool:** same options + enable **worker node autoscaling**
5. **Storage:** select Prism storage container
6. **Networking:** pod CIDR, service CIDR, load balancer IP range
7. **Image Registry:** Harbor endpoint + CA cert (if local mirror used)
8. Click **Create** → watch VMs appear in Prism Central → wait for cluster Active state
9. Actions → **Download kubeconfig** → transfer to bastion

## Community Resources & Reference Series

| Resource | URL | What it covers |
|---|---|---|
| Nutanix Cloud Bible — NKP | [link](https://www.nutanixbible.com/18a-book-of-cloud-native-services-nutanix-kubernetes-platform.html) | Architecture overview (NKP 2.12) |
| nkp-quickstart | [github.com/nutanixdev/nkp-quickstart](https://github.com/nutanixdev/nkp-quickstart) | Automated deploy script, env vars, compatibility JSON |
| Jonas Högman — NKP series (5 posts) | [jonashogman.com](https://jonashogman.com/nkp-post-1-preparing-the-setup-environment/) | Full real-world deployment: Harbor, bootstrap, Kommander, IdP, Workload Cluster |
| Jeroen Tielen — NX-3060-G4 lab | [jeroentielen.nl](https://www.jeroentielen.nl/trying-to-get-my-oldest-to-the-latest-and-running-the-latest-%F0%9F%AB%A3/) | CE on legacy hardware, full stack upgrade walkthrough |
| Nutanix Support Portal | [portal.nutanix.com](https://portal.nutanix.com) | NKP downloads, compatibility matrix, POC licenses |
