---
kind: unit
title: "Inside the Stack: AHV, AOS, and the CVM"
name: lesson-nkp-architecture-unit-2
---

::remark-box
This unit zooms into the bottom three layers of the NKP stack — the ones you never touch directly but that determine everything about how NKP performs, scales, and fails. By the end you'll be able to answer the question every new Nutanix student asks: **"what OS is actually running on the cluster?"**
::

## The question nobody asks (but everyone should)

When a student sees the NKP stack diagram for the first time, they usually ask about Kommander, CAPI, or Flux. Almost nobody asks about the bottom. But the bottom is where the interesting engineering is.

Look at the bottom three layers of the stack again:

```
┌─────────────────────────────────────────────────────┐
│  Kommander          — fleet UI, workspaces, RBAC    │
├─────────────────────────────────────────────────────┤
│  Flux CD            — GitOps, add-on reconciliation │
├─────────────────────────────────────────────────────┤
│  CAPI / CAPX / CAREN — declarative cluster lifecycle│
├─────────────────────────────────────────────────────┤
│  RKE2               — Kubernetes distribution       │
├─────────────────────────────────────────────────────┤
│  Rocky Linux 9.7    — CIS-hardened node OS          │  ← where does THIS run?
├─────────────────────────────────────────────────────┤
│  AHV                — KVM hypervisor                │  ← what's underneath?
│  AOS / CVM          — storage OS                    │  ← and this?
└─────────────────────────────────────────────────────┘
```

The question is: **what OS is the cluster running on?**

The answer is: **two instances of Linux are coexisting on every physical node** — and neither one is "the cluster OS" in the traditional sense.

---

## Two Linux instances on every node

Each physical Nutanix node runs exactly two Linux systems simultaneously:

```
Physical Node (x86 server)
│
├─ AHV Host OS  ──  Linux EL8 minimal
│   ├── KVM / QEMU  (virtualisation engine)
│   ├── Open vSwitch (OVS)  (virtual networking)
│   └── PCI passthrough controller  (VT-d / IOMMU)
│
└─ CVM  (Controller VM)  ──  Linux EL8 (Rocky-based)
    └── AOS  (Acropolis Operating System)
         ├── Distributed Storage Fabric (DSF)
         ├── Stargate  (I/O path)
         ├── Curator   (MapReduce, cluster-wide tasks)
         ├── Cassandra (metadata ring)
         ├── Prism     (local management API)
         └── Zeus      (configuration store)
```

| Layer | OS | What it does |
|---|---|---|
| **AHV host** | Linux EL8 minimal (KVM/QEMU/OVS) | Virtualises VMs, manages networking (OVS), handles PCI passthrough |
| **CVM** | Linux EL8 (Rocky-based) | Runs AOS: storage, cluster management, data services |

These are **not** two separate physical servers. They run on the same hardware, side by side, every second the cluster is running.

---

## AHV — the hypervisor

**AHV (Acropolis Hypervisor)** is Nutanix's proprietary enterprise-grade **Type 1 bare-metal hypervisor** — it runs directly on the hardware, not inside another OS. It is built on **KVM (Kernel-based Virtual Machine)**, the same open-source virtualisation technology used by RHEV, OpenStack, and most cloud providers.

What Nutanix adds on top of stock KVM:
- **Open vSwitch (OVS)** for VM networking — per-VM port isolation, VLAN tagging, microsegmentation via Flow
- **PCI passthrough controller** using VT-d/IOMMU — direct device assignment to VMs with bare-metal performance
- **AHV management integration** — Prism Central API drives VM create/delete/resize via AHV

Every NKP node (control plane VM, worker VM) runs as an **AHV virtual machine**. CAPX provisions these VMs by calling the Prism Central API — the same API you use when you manually create a VM in the Prism UI, but driven declaratively by Kubernetes CRDs.

---

## AOS — the storage OS

**AOS (Acropolis Operating System)** is the core software foundation of the entire Nutanix platform. It is **not** a traditional OS you interact with directly — it runs inside the CVM as a set of distributed services that together form the **Distributed Storage Fabric (DSF)**.

AOS is responsible for:
- Serving all storage I/O for every VM on the node (and the cluster)
- Maintaining data redundancy (Replication Factor 2 or 3)
- Snapshots, clones, compression, deduplication, erasure coding
- Cross-node replication and disaster recovery
- Cluster health monitoring and self-healing

### Key AOS services (inside the CVM)

| Service | What it does |
|---|---|
| **Stargate** | The I/O path — all reads and writes pass through Stargate |
| **Curator** | MapReduce engine — runs background tasks (dedup, compression, rebalancing) |
| **Cassandra** | Distributed metadata ring — knows where every data block lives |
| **Prism** | Local management API — exposes the REST API for Prism Central |
| **Zeus** | Cluster configuration store (ZooKeeper-based) |

---

## The CVM — the most important VM you'll never touch

The **CVM (Controller VM)** is a privileged Linux VM that runs on every Nutanix node. It is the component that owns everything that isn't pure virtualisation:

> Without the CVM, there is no cluster. It is the "brain" of each node — and together, the CVMs of all nodes form the Distributed Storage Fabric (DSF).

### CVM key facts

- Runs on every node — always, 24/7
- **Never shut down** unless Nutanix Support instructs you to (shutting down the CVM on a node removes that node from the storage fabric)
- Completely transparent to NKP — RKE2, CAPI, and Kubernetes have no knowledge of it
- Consumes a fixed slice of the node's resources that is **not** available to NKP VMs

### CVM resource reservation (the "CVM tax")

This is critical for sizing. On every node, the CVM permanently consumes:

| Resource | Reserved for CVM | Not available to NKP |
|---|---|---|
| vCPU | 12 vCPU | These cores cannot be scheduled to NKP node VMs |
| RAM | 48 GB | This memory cannot be used by NKP pods |

When you size an NKP cluster, always subtract the CVM tax first. A node with 32 vCPU / 128 GB RAM effectively has **20 vCPU / 80 GB RAM** available for NKP workloads.

---

## Why the CVM is a VM, not an in-kernel module

This is the architectural decision that defines Nutanix — and it is not obvious why it's better.

Most hyperconverged storage systems embed the storage controller directly into the hypervisor kernel:

```
vSAN (VMware):
  [ESXi kernel] → [vSAN module in-kernel] → [disks]

Storage Spaces Direct (Microsoft):
  [Windows Server kernel] → [S2D in-kernel] → [disks]

Nutanix:
  [AHV kernel] → [CVM (a VM)] → [PCI passthrough] → [disks]
```

Nutanix chose to run the storage controller **as a VM**. Three reasons this matters:

**1. Hypervisor-agnostic**
The CVM runs the same AOS code whether the hypervisor is AHV, VMware ESXi, or Microsoft Hyper-V. vSAN only works on ESXi. Storage Spaces Direct only works on Windows Server. AOS works on all three — you can migrate from ESXi to AHV without changing your storage software.

**2. Independent upgrade lifecycle**
You can upgrade AOS (storage) without touching the hypervisor, and vice versa. In a vSAN environment, upgrading vSphere also upgrades your storage layer — they are coupled. Nutanix separates them: the CVM can be upgraded on a rolling basis, one node at a time, while the cluster stays online.

**3. Fault isolation**
A bug in the storage stack cannot crash the hypervisor. The CVM is just another VM — if it crashes, AHV keeps running and VMs on that node stay up. The cluster detects the CVM failure and routes I/O to other nodes while the CVM restarts.

::details-box
---
:summary: "Coming from VMware vSAN? Here's how the architectures compare"
---

If you've managed a vSAN cluster, the CVM model initially seems wasteful — why spend 12 vCPU / 48 GB on a VM that just does storage? Here's the full comparison:

| Aspect | Nutanix (CVM) | VMware vSAN | Microsoft S2D |
|---|---|---|---|
| Storage controller location | VM (CVM) | In-kernel (ESXi) | In-kernel (Windows Server) |
| Hypervisor dependency | ✅ None — runs on AHV, ESXi, Hyper-V | ❌ ESXi only | ❌ Windows Server only |
| Upgrade coupling | ✅ AOS and AHV upgrade independently | ❌ vSphere upgrade = vSAN upgrade | ❌ Windows update = S2D update |
| Storage bug impact | CVM crash → AHV stays up | Kernel panic → hosts PSOD | BSOD possible |
| I/O latency to disks | Bare-metal via PCI passthrough (~10–20 µs) | Near bare-metal (in-kernel) | Near bare-metal (in-kernel) |
| Data locality | Primary design — I/O served from local disks first | Object-based distribution (can generate east-west traffic) | Policy-based (can be local or distributed) |

The "CVM tax" (12 vCPU / 48 GB) is the price for hypervisor-agnosticism and independent upgrades. Most Nutanix customers consider it worth paying.
::

---

## PCI passthrough — how the CVM gets bare-metal disk performance

The CVM runs as a VM — but it doesn't access disks through the hypervisor's virtualised I/O stack. Instead, the physical disk controllers (NVMe, SSD, HDD) are **passed directly through to the CVM** using **VT-d / IOMMU** — a CPU feature that allows a VM to own a physical PCIe device with no hypervisor software in the I/O path.

```
Without passthrough (virtualised I/O):
  Disk → [AHV I/O emulation layer] → CVM
  (hypervisor translates every I/O request — adds latency)

With passthrough (VT-d / IOMMU):
  Disk → [directly assigned] → CVM
  (no translation — bare-metal latency ~10–20 µs)
```

This is what Josh Odgers (ex-CTO field at Nutanix) documented as **"DirectPath I/O"** — and it is what gives Nutanix storage its performance characteristics (~1M IOPS per node on all-flash configurations).

> 📖 See Josh Odgers' blog for deep technical detail: [joshodgers.com](https://joshodgers.com)

**Passthrough in NKP context:** The same VT-d/IOMMU mechanism is also used to pass **GPU cards** directly to NKP worker VMs — giving pods bare-metal GPU access with no hypervisor overhead. This is covered in detail in [Module 7 — GPU Support on NKP](../../module-7/1.lesson-gpu/unit-1.md).

---

## Data locality — why I/O doesn't travel the network

In a Nutanix cluster, each CVM **primarily serves the disks attached to its own node**. When a VM writes data, Stargate writes it to the local disks first, then replicates to another node for redundancy. When that same VM reads that data later, it reads from the local node — no network hop.

This is **data locality** as a first-class design principle:

```
VM on Node 1 reads data:
  ✅ Data is local → CVM on Node 1 serves it from local NVMe (~10–20 µs)

VM on Node 1 reads data that only exists on Node 2:
  ⚠️  CVM on Node 1 fetches it from CVM on Node 2 over the east-west network
  (this is a cache miss — Nutanix optimises to minimise these)
```

For NKP workloads this means: **stateful pods (databases, Longhorn volumes) perform best when their data is on the same node the pod runs on**. Kubernetes pod scheduling + Nutanix data locality work together — persistent volumes created on a node will be served locally as long as the pod stays on that node.

---

## Guest OS matrix — what can run on AHV

Rocky Linux is the NKP default node OS — but AHV supports a wide range of guest operating systems. The full list is maintained on the Nutanix support portal:

> 📋 **[portal.nutanix.com → Compatibility Matrix → Guest OS](https://portal.nutanix.com/page/documents/compatibility-details/list?type=guestos)**

A sample of supported guest OSes on AHV:

| Category | Examples |
|---|---|
| **RHEL family** | Rocky Linux 8/9, AlmaLinux 8/9, CentOS 7/8, RHEL 7/8/9 |
| **Debian family** | Ubuntu 20.04/22.04/24.04, Debian 10/11/12 |
| **Other Linux** | Fedora, SUSE Linux Enterprise 15, Amazon Linux 2, Flatcar Container Linux |
| **Windows** | Windows Server 2019/2022, Windows 10/11 (requires VirtIO drivers) |
| **Other** | Solaris x86 11 |

For NKP specifically: Rocky Linux 9.7 is the supported node OS for NKP 2.17. This is the OS that runs **inside the NKP node VMs** on AHV — not the OS of AHV itself.

---

## Container runtime inside the NKP node VM

Each NKP node VM runs Rocky Linux 9.7. Inside that VM, RKE2 installs and manages the container runtime. The **default and supported runtime is containerd** — RKE2 ships with containerd 2.x bundled.

Other runtimes are supported but not the default:

| Runtime | Support in NKP | Notes |
|---|---|---|
| **containerd** | ✅ Default | Bundled with RKE2, no separate install |
| **Docker** | ✅ Supported | Requires Docker Engine install; containerd is preferred |
| **CRI-O** | ✅ Supported | Alternative OCI runtime; common in OpenShift environments |
| **Podman** | ✅ Supported | Daemonless; used in some security-hardened environments |

In this course we use **containerd** (the RKE2 default). You will interact with it via `crictl` on the node and via standard `kubectl` commands — you never call containerd directly.

---

## Putting it all together — what runs where

Let's map the full stack to physical reality for one NKP worker node:

```
Physical server (e.g. Nutanix NX-8155)
│
├── AHV host OS  (Linux EL8 minimal — never touched by operators)
│    ├── KVM/QEMU: manages all VMs on this node
│    └── OVS: virtual network switch for VM traffic
│
├── CVM  (always running, reserved 12 vCPU / 48 GB)
│    └── AOS services: Stargate, Curator, Cassandra, Prism, Zeus
│         └── Owns all NVMe/SSD/HDD via PCI passthrough (VT-d)
│
└── NKP Worker VM  (Rocky Linux 9.7, gets remaining vCPU/RAM)
     └── RKE2 agent
          └── containerd
               └── Pods (your workloads)
```

The "cluster OS" question has a precise answer now:

- **The hypervisor layer** runs AHV (Linux EL8 minimal) — operators never log in here
- **The storage layer** runs AOS inside the CVM (Linux EL8 Rocky-based) — `ssh nutanix@<CVM_IP>` during maintenance only
- **The Kubernetes layer** runs Rocky Linux 9.7 inside each NKP node VM — this is where `kubectl`, `crictl`, and `journalctl` live
- **Your workloads** run as containers inside those VMs — they see Rocky Linux 9.7 as their host

---

## Check your understanding

Before moving on:

1. Why does Nutanix run the storage controller as a VM instead of in the hypervisor kernel?
2. What is the CVM tax and why does it matter for NKP sizing?
3. What CPU feature makes PCI passthrough possible?
4. What is data locality and why does it benefit stateful NKP workloads?
5. A physical node has 40 vCPU and 256 GB RAM. How much is available to NKP node VMs?
6. What container runtime does RKE2 use by default?
7. Can you run Ubuntu VMs on AHV? What about Windows?

Answers are in the lesson above.
