# Feasibility: NKP Course on iximious Flexbox

## Conclusion up front

**The course is fully feasible.** Flexbox's 5-VM topology removes the single biggest
limitation of a solo Firecracker VM. The only remaining hard blockers are operations that
call the Nutanix AHV/Prism Central API directly — those become guided walkthrough lessons.
Everything else is hands-on and interactive.

---

## Platform constraints

| Resource | Per VM | 5-VM Flexbox total |
|---|---|---|
| vCPU | 2–4 | 10–20 |
| RAM | 4–8 GB | 20–40 GB |
| Storage | 1 root drive | 5 root drives |
| Network | Local IP per VM | Flat L2 subnet (shared) |
| Internet access | None at runtime | None at runtime |
| Nested virtualization | ❌ Not available | ❌ Not available |

### iximious catalog rootfs images (full list observed)

| rootfs name | OS / Tool | Notes |
|---|---|---|
| `rockylinux` | Rocky Linux 9 (floating `:9` tag) | RHEL-compatible; matches NKP node OS family |
| `almalinux` | AlmaLinux 9 | RHEL-compatible alternative to Rocky |
| `ubuntu-22-04` | Ubuntu 22.04 LTS | Older LTS |
| `ubuntu-24-04` | Ubuntu 24.04 LTS | Current LTS — best Docker 29 support |
| `ubuntu-26-04` | Ubuntu 26.04 (preview/nightly) | Next LTS; likely unstable for course use |
| `debian-stable` | Debian Stable (Bookworm) | |
| `debian-testing` | Debian Testing (Trixie) | Rolling; avoid for pinned course builds |
| `fedora` | Fedora (latest) | Rolling; avoid for pinned course builds |
| `alpine` | Alpine Linux | Musl libc — incompatible with RKE2 glibc binaries |
| `kali-linux` | Kali Linux | Security tooling distro; not relevant |
| `nixos` | NixOS | Declarative; interesting but complex for students |
| `opensuse-tumbleweed` | openSUSE Tumbleweed | Rolling SUSE; not relevant |
| `archlinux` | Arch Linux | Rolling; not relevant |
| `incus` | Incus (LXD fork) | Container/VM manager — see note below |

**Runtimes bundled in the catalog (available across images):**

| Runtime | Version |
|---|---|
| Docker | 29 |
| containerd | 2.2 |
| Kubernetes (catalog default cluster) | 1.35 |

> **`incus` rootfs — worth noting:** Incus is a system container and VM manager (a community
> fork of LXD by Canonical). On iximious, a Flexbox VM booted with the `incus` rootfs can
> launch **nested system containers or VMs** using Linux namespaces and optional KVM. This is
> not useful for NKP node VMs (we need real separate VMs, which Flexbox already provides), but
> it could be useful for a future lesson that demonstrates how NKP concepts relate to
> container-vs-VM isolation. Not used in this course.

**Rocky Linux alignment:** The catalog image is Rocky 9, which matches the NKP 2.17 node OS
family. However the tag is **floating** (`rockylinux:9`) — it will track the latest 9.x patch.
The rootfs build must pin `rockylinux:9.7` explicitly for reproducibility.

**K8s mismatch:** The catalog's default Kubernetes cluster is 1.35; NKP 2.17 requires 1.34.x.
This course never uses the catalog's pre-provisioned cluster — RKE2 v1.34.x is installed
explicitly in every node VM rootfs.

**Alpine incompatibility:** Alpine uses musl libc. RKE2, the `nkp` CLI, and most NKP tooling
are compiled against glibc. Alpine cannot be used for any VM in this course.

---

## Topology map

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flexbox Playground (5 VMs)                   │
│                                                                 │
│  vm1 — bootstrap/workstation     vm2 — management control plane │
│  192.168.0.10 / 4 GB RAM         192.168.0.11 / 8 GB RAM        │
│  nkp CLI, kubectl, helm, flux    RKE2 server, etcd, apiserver   │
│  kind (bootstrap cluster)                                       │
│                                                                 │
│  vm3 — worker-1   vm4 — worker-2   vm5 — worker-3               │
│  192.168.0.12     192.168.0.13     192.168.0.14                  │
│  8 GB RAM         8 GB RAM         8 GB RAM                     │
│  RKE2 agent       RKE2 agent       RKE2 agent                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## What Flexbox makes possible vs. single-VM

| Capability | Single VM | Flexbox 5-VM |
|---|---|---|
| Real multi-node cluster | ❌ | ✅ |
| Node drain / cordon / eviction | ❌ simulated | ✅ real |
| Pod scheduling (affinity, taints) | ❌ workarounds | ✅ real |
| Node failure simulation | ❌ | ✅ kill vm4 |
| nkp bootstrap-and-pivot flow | ❌ | ✅ kind on vm1 → RKE2 on vm2 |
| CNI cross-node networking | ❌ | ✅ Calico/Cilium on shared L2 |
| MetalLB L2 load balancer | ❌ | ✅ |
| etcd member operations | ❌ | ✅ |
| Distributed storage (Longhorn) | ❌ | ✅ |

---

## Hard blockers (require real AHV — taught as walkthroughs)

| Operation | Why blocked | Lesson approach |
|---|---|---|
| `nkp create cluster --provider=nutanix` | Calls Prism Central API to provision AHV VMs | Annotated screenshot walkthrough |
| `.qcow2` upload to Prism Central | Requires Prism Central image service | Procedural walkthrough (Lesson 01) |
| Nutanix CSI block/file PVCs | Calls Nutanix DSF storage APIs | Replaced by **Longhorn** (RWO+RWX+snapshots, ships as an NKP add-on) |
| Nutanix CCM cloud load balancer VIPs | Drives AHV VIP allocation | Replaced by MetalLB L2 |

---

## The NKP bootstrap-and-pivot analogy

NKP's real flow:

```
nkp create bootstrap   →  kind cluster starts on bootstrap node
nkp create cluster     →  CAPI NutanixCluster provider calls Prism Central → VMs provisioned
nkp move               →  management cluster becomes self-hosted on new VMs
```

Flexbox faithful reproduction:

```
vm1: nkp create bootstrap  →  kind cluster on vm1         ✅ real command
     nkp create cluster       (skipped — no AHV)          📺 demo only
     [pre-installed RKE2]  →  RKE2 already on vm2–vm5
vm1: nkp move              →  pivot to vm2 cluster        ✅ real command
```

Students see and run the real `nkp bootstrap` and `nkp move` commands. Only the
"Nutanix provisions VMs" middle step is pre-done in the rootfs, which is an accurate
representation of what NKP actually abstracts away.

---

## rootfs build strategy

All binaries and container images must be baked in at build time. Nothing is downloaded
at runtime.

| Image | Base OS | Target VM | Key contents |
|---|---|---|---|
| `nkp-bootstrap.ext4` | Ubuntu 24.04 (catalog `ubuntu-24-04`) | vm1 | `nkp` v2.17, `kubectl` 1.34, `helm` v3, `flux`, Docker 29, kind, lab YAML manifests |
| `nkp-controlplane.ext4` | `rockylinux:9.7` (pinned) | vm2 | RKE2 v1.34.x server binary + all server-side container images |
| `nkp-worker.ext4` | `rockylinux:9.7` (pinned) | vm3–5 | RKE2 v1.34.x agent binary + all agent-side container images |

**Base OS selection rationale:**
- **vm1 uses Ubuntu 24.04** — Docker 29 (required for kind) installs cleanly from the iximious
  catalog image. The bootstrap node runs operator tooling only; OS flavour does not need to
  match the production node OS.
- **vm2–vm5 use Rocky Linux 9.7** — The iximious `rockylinux` catalog image is already Rocky 9,
  so this is not a build-from-scratch problem. The tag is pinned to `rockylinux:9.7` (not the
  floating `:9`) to guarantee the exact minor version matches the NKP 2.17 production node OS.
  This maximises fidelity for SELinux behaviour, systemd unit names, kernel parameters, and
  CIS hardening contexts students will encounter on real NKP clusters.
- **iximious catalog K8s 1.35 cluster is not used** — RKE2 v1.34.x is installed explicitly
  in the rootfs. The catalog's pre-provisioned cluster is a separate iximious feature that this
  course bypasses entirely.

**Storage in labs:**
- **Tier 2 (vm1 single-node):** `local-path-provisioner` (bundled with RKE2) — zero config,
  instant PVC binding, used for basic pod-volume lifecycle exercises.
- **Tier 3 (5-VM Flexbox):** **Longhorn** — distributed RWO+RWX block storage with
  `VolumeSnapshot` support, replicating across vm3/vm4/vm5. Longhorn is a first-class NKP
  add-on (ships in the NKP catalog as a HelmRelease), so students see the same Longhorn they
  would deploy in production via `nkp`. It also powers the Lesson 12 node-failure scenario:
  kill vm4, watch Longhorn re-replicate volumes to the surviving workers.

> **Why not AWS EBS CSI?** AWS EBS CSI requires real EC2 instances, an AWS account, and calls
> the EC2 metadata endpoint (`169.254.169.254`) at startup. It crash-loops immediately on
> non-EC2 nodes. LocalStack can mock it but adds ~1 GB of overhead per VM and has incomplete
> snapshot support. It is not viable for an airgapped Firecracker environment.
>
> **Why not Rook/Ceph?** Each Ceph OSD daemon needs ~1 GB RAM. Across three worker nodes
> already running RKE2 agents and NKP workloads, Ceph would exhaust the 8 GB budget.
> Longhorn uses far less memory (controller ~256 MB, instance manager ~100 MB per node).

The cluster is **not** pre-started. Students run `rke2 server` and `rke2 agent` join
commands during the lab to experience the actual initialization sequence.

---

## Lesson tier model

| Tier | VMs | Lessons |
|---|---|---|
| **TIER 1** Walkthrough | 0 | 01 OS image, 02 Prism bootstrap, 03 cluster create |
| **TIER 2** Single-VM | 1 | 04 nkp CLI, 05 kubectl basics |
| **TIER 3** Full Flexbox | 5 | 06 bootstrap-pivot, 07 node ops, 08 add-ons, 09 GitOps, 10 RBAC, 11 monitoring, 12 node failure |

---

## Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| iximious `rockylinux` tag is floating (`:9`, not `:9.7`) | **High** | Pin `rockylinux:9.7` explicitly in rootfs `Dockerfile FROM` line; document in rootfs README |
| iximious catalog defaults to K8s 1.35; NKP needs 1.34.x | **High** | Explicitly install RKE2 v1.34.x in rootfs build; never use the catalog's pre-provisioned cluster feature |
| 8 GB VMs may not be available in all iximious plans | Medium | k3s fallback works at 4 GB for single-control-plane; note requirement in lesson header |
| No internet — container images must all be pre-pulled | High | rootfs build pipeline must `ctr images import` every image; CI validates the image list |
| RKE2 version drift when NKP ships a new K8s patch | Low | Pin exact RKE2 release tag in rootfs `Makefile`; update when NKP version bumps |
| Firecracker boot time with large rootfs | Low | ext4 images with pre-pulled images can be 8–15 GB; iximious streams the rootfs, first boot ~20s |
| MetalLB L2 needs to announce on the VM's subnet | Low | Configure MetalLB IPAddressPool to 192.168.0.100–192.168.0.200 in the bootstrap lab setup script |
| Docker 29 on vm1 Ubuntu rootfs vs. containerd 2.2 on node VMs | Low | Different runtimes on different VMs is intentional and mirrors real NKP setup (operator laptop vs. nodes) |
| Longhorn requires open-iscsi on worker nodes | Low | Install `iscsi-initiator-utils` in the Rocky 9.7 worker rootfs build; add `iscsid` systemd unit enable |
