---
kind: unit
title: "NKP Uses Kubernetes to Manage Kubernetes"
name: lesson-nkp-architecture-unit-1
---

::remark-box
**NKP — Nutanix Kubernetes Platform** is Nutanix's enterprise Kubernetes fleet management system. Nutanix makes the hyperconverged infrastructure (compute + storage + networking in one box) that many enterprises run their data centres on. NKP is the layer on top that lets you deploy, operate, and govern fleets of Kubernetes clusters on that infrastructure — without writing your own automation.

If you've used EKS, GKE, or AKS, think of NKP as the equivalent for on-premises Nutanix AHV — with the added ability to manage clusters across multiple sites and cloud providers from one control plane.
::

::details-box
---
:summary: What is Kubernetes fleet management?
---

**Kubernetes fleet management** is the centralized administration of multiple clusters as a single, unified logical entity — rather than managing each cluster individually with its own access credentials, add-on lifecycle, and policy configuration.

Instead of SSHing into 10 different clusters to apply the same RBAC policy, a fleet manager lets you define it once and propagate it everywhere.

Common implementations in the ecosystem:

| Product | By |
|---|---|
| **NKP / Kommander** | Nutanix |
| **Rancher Fleet** | SUSE / Rancher |
| **Azure Kubernetes Fleet Manager** | Microsoft |
| **GKE Fleet** | Google |
| **Karmada** | CNCF (community) |
| **SAP Gardener** | SAP |
| **k0rdent** | Mirantis |

NKP uses **Kommander** as its fleet management layer — it federates policy, RBAC, add-ons, and access control across all Managed and Attached clusters from a single pane.
::

::hint-box
---
:summary: Hint 1
---

NKP's fleet management layer didn't start at Nutanix. It comes from **D2iQ** — a Kubernetes company Nutanix acquired in 2023. D2iQ was the original developer of two open-source projects that now form the core of NKP:

- **Kommander** — the fleet management layer: centralized UI, GitOps, multi-tenancy, policy, observability across all clusters
- **Konvoy** — the cluster lifecycle manager built on Cluster API (CAPI)

Nutanix wrapped these into **NKP (Nutanix Kubernetes Platform)**, announced at .NEXT in May 2024. The fleet management features (Kommander multi-cluster, Attached Clusters) are available in the **NKP Ultimate** tier.
::

## You're about to create a Kubernetes cluster. Where does that request go?

When you run `nkp create cluster`, you're not running a script that SSHes into
nodes and runs `kubeadm init`. You're creating a **Kubernetes object** — a YAML
resource — in another Kubernetes cluster. That cluster reads the object and
provisions the infrastructure.

> NKP uses Kubernetes to manage Kubernetes.

This is the core insight. Once it clicks, everything else in NKP makes sense.

---

## The four cluster roles

NKP defines four distinct roles for clusters. Each has a single job.

::image-box
---
:src: __static__/placeholder-four-cluster-roles-overview.png
:alt: 'NKP four cluster roles diagram showing Bootstrap, Management, Workload, and Attached clusters with directional arrows between them'
---
_TODO: Replace with actual screenshot — diagram showing Bootstrap→Management→Workload→Attached with labeled arrows indicating the lifecycle relationships (Bootstrap creates Management, Management creates Workload, Management federates Attached)_
::

### 1. Bootstrap Cluster — *Clúster de arranque*

A **temporary** cluster that exists only during initial installation.

- Created by `nkp create bootstrap` on your workstation
- Runs as a `kind` (Kubernetes-in-Docker) cluster — no VMs, no cloud
- Its sole job: host Cluster API controllers long enough to provision the Management Cluster
- **Deleted** after `nkp move` completes — it never runs in production

```
nkp create bootstrap
# → kind cluster appears on vm1
# → CAPI + Nutanix provider start inside it
# → Management Cluster gets created
# → nkp move  (CAPI moves to Management Cluster)
# → Bootstrap cluster deleted
```

Think of it as scaffolding: you need it to build the building, but once the building
stands on its own, the scaffolding comes down.

### 2. Management Cluster — *Clúster de gestión*

The **permanent brain** of your NKP environment.

- Self-hosted: after `nkp move`, it manages itself
- Runs Kommander — the NKP control plane UI and API
- Runs Flux CD — GitOps engine that reconciles all add-ons
- Creates and manages all other clusters via Cluster API
- One Management Cluster per NKP environment

### 3. Managed / Workload Cluster — *Clúster de trabajo*

Where your applications run.

- Created and lifecycle-managed by the Management Cluster
- Has its own RKE2 control plane and worker nodes
- Add-ons deployed via Flux CD from the Management Cluster
- Can be upgraded, scaled, or deleted without touching the Management Cluster

### 4. Attached Cluster — *Clúster adjunto* (Ultimate only)

An **existing** cluster (EKS, GKE, on-prem RKE2) brought under NKP management.

- Not created by NKP — just registered with Kommander
- Gains centralized add-on management, RBAC, and observability
- Requires NKP Ultimate license

---

## The technology stack

Each layer has a specific job:

::image-box
---
:src: __static__/placeholder-nkp-full-stack-diagram.png
:alt: 'NKP full technology stack diagram with layers from Nutanix AHV at the bottom up through AOS, Prism Central, Rocky Linux, RKE2, CAPI/CAPX/CAREN, Flux CD, and Kommander at the top'
---
_TODO: Replace with actual screenshot — layered stack diagram with all components from AHV/AOS/Prism Central at the bottom up to Kommander at the top, with brief role labels for each layer_
::

```
┌─────────────────────────────────────────────────────┐
│  Kommander          — fleet UI, workspaces, RBAC    │
├─────────────────────────────────────────────────────┤
│  Flux CD            — GitOps, add-on reconciliation │
├─────────────────────────────────────────────────────┤
│  Cluster API (CAPI) — declarative cluster lifecycle │
│  CAPX               — CAPI provider for Nutanix AHV │
│  CAREN              — runtime extensions (policies) │
├─────────────────────────────────────────────────────┤
│  RKE2               — Kubernetes distribution       │
├─────────────────────────────────────────────────────┤
│  Rocky Linux 9.7    — CIS-hardened node OS          │
├─────────────────────────────────────────────────────┤
│  Nutanix NCI  ── AHV (hypervisor, hosts NKP VMs)   │
│               ── AOS (storage OS, CVM)              │
│  Nutanix Central ── Prism Central (CAPX/CAREN API)  │
└─────────────────────────────────────────────────────┘
```

| Component | What it does |
|---|---|
| **RKE2** | CNCF-conformant Kubernetes distribution from Rancher. Replaces kubeadm. CIS-hardened by default. |
| **Cluster API (CAPI)** | Kubernetes extension that models clusters as CRDs. Defines *what* a cluster should look like — number of control plane nodes, worker count, Kubernetes version. Provider-agnostic. |
| **CAPX** | *Cluster API Provider for Nutanix* (also `cluster-api-provider-nutanix`). The AHV-specific CAPI infrastructure provider. Watches `NutanixCluster` and `NutanixMachine` CRDs and translates them into Prism Central API calls that provision real AHV VMs. Ships inside the `nkp create bootstrap` cluster. |
| **CAREN** | *Cluster API Runtime Extensions for Nutanix*. A Nutanix-specific CAPI runtime extension server that intercepts cluster lifecycle hooks (BeforeClusterCreate, BeforeClusterUpgrade, etc.) to enforce Nutanix-specific policies — for example validating that the requested OS image exists in Prism Central before allowing cluster creation to proceed. |
| **Flux CD** | GitOps operator. Reads HelmRelease objects and ensures add-ons are installed and up to date. |
| **Kommander** | NKP's management UI. Workspaces, projects, centralized RBAC, add-on catalog. |

---

## CAPI, CAPX, and CAREN — how they divide the work

These three components are often confused because they all live inside the same cluster and cooperate tightly. Here is how to tell them apart:

::image-box
---
:src: __static__/placeholder-capi-capx-caren-relationship.png
:alt: 'Relationship diagram showing CAPI as the central framework with CAPX as the Nutanix infrastructure provider below it and CAREN as the lifecycle policy layer intercepting requests between the CLI and CAPX'
---
_TODO: Replace with actual screenshot — component relationship diagram: nkp CLI → CAREN (hooks) → CAPI (core controller) → CAPX (Nutanix provider) → Prism Central, with each component's role annotated_
::

### Cluster API (CAPI) — the framework

CAPI is a **generic Kubernetes extension** from the Kubernetes SIG-cluster-lifecycle project. It defines the *shape* of a cluster as CRDs:

- `Cluster` — the top-level cluster object
- `MachineDeployment` / `MachineSet` / `Machine` — declarative node pool management
- `KubeadmControlPlane` / `RKE2ControlPlane` — control plane bootstrap spec

CAPI itself is **infrastructure-agnostic** — it has no idea what AHV, AWS, or vSphere even is. It delegates actual VM creation to a *provider*.

### CAPX — the Nutanix provider

**CAPX** (*Cluster API Provider for Nutanix*, GitHub: `nutanix-cloud-native/cluster-api-provider-nutanix`) is the AHV-specific infrastructure provider. It adds two CRDs:

- `NutanixCluster` — describes AHV-specific cluster settings (Prism Central endpoint, subnet, storage container)
- `NutanixMachine` / `NutanixMachineTemplate` — describes each node VM (image, vCPU, RAM, category tags)

When CAPI creates a `Machine`, CAPX's controller takes over and:
1. Calls the Prism Central API to create a VM
2. Injects the RKE2 bootstrap script via cloud-init
3. Watches the VM until it joins the cluster
4. Updates the `Machine` object's status

CAPX is installed automatically by `nkp create bootstrap` and lives in the `capx-system` namespace.

### CAREN — the lifecycle guard

**CAREN** (*Cluster API Runtime Extensions for Nutanix*, GitHub: `nutanix-cloud-native/cluster-api-runtime-extensions-nutanix`) is a **CAPI Runtime Extension server** — a webhook-like component that intercepts cluster lifecycle events *before* CAPX acts on them.

CAREN handles:

| Hook | What CAREN does |
|---|---|
| `BeforeClusterCreate` | Validates OS image exists in Prism Central; validates storage container is accessible |
| `BeforeClusterUpgrade` | Verifies the target OS image for the new version is uploaded before allowing the upgrade to start |
| `BeforeClusterDelete` | Runs pre-delete cleanup (CSI volume detach, node drain ordering) |
| CNI / CCM injection | Installs Cilium and the Nutanix CCM into new clusters via `ClusterResourceSet` |

Think of CAREN as the **policy and pre-flight layer** that sits between your `nkp` command and CAPX actually calling Prism Central.

### How they fit together at cluster create time

```
nkp create cluster
      │
      ▼
 NutanixCluster + Cluster objects created in Bootstrap cluster
      │
      ▼
 CAREN BeforeClusterCreate hook fires
      │  ✓ OS image found in Prism Central
      │  ✓ Storage container reachable
      ▼
 CAPI core controller starts reconciling Machine objects
      │
      ▼
 CAPX NutanixMachine controller calls Prism Central API
      │  → AHV VM created
      │  → RKE2 bootstrap script injected via cloud-init
      ▼
 RKE2 starts on new VM → node joins cluster
```

---

## Tracing a cluster creation request

When you run:
```bash
nkp create cluster nutanix \
  --cluster-name my-cluster \
  --control-plane-replicas 3 \
  --worker-replicas 4
```

Here is what happens, step by step:

::image-box
---
:src: __static__/placeholder-cluster-creation-request-flow.png
:alt: 'End-to-end cluster creation request flow diagram from nkp CLI through CAREN, CAPI, CAPX, Prism Central, AHV VM boot, RKE2 startup, Flux CD add-on deployment, and Kommander registration'
---
_TODO: Replace with actual screenshot — sequential flow diagram numbered 1–8 matching the steps below, showing each component handoff from CLI command to fully registered cluster_
::

1. `nkp` CLI creates `NutanixCluster`, `NutanixMachineTemplate`, and `Cluster` objects in the Bootstrap (or Management) Cluster
2. CAPI controller sees the new `Cluster` object → starts reconciling
3. Nutanix provider calls Prism Central API → creates VMs on AHV
4. VMs boot from the Rocky Linux 9.7 CIS image (pre-loaded to Prism Central)
5. RKE2 starts on the control plane VM, bootstraps etcd + kube-apiserver
6. Worker VMs join the cluster via RKE2 agent
7. Flux CD starts deploying add-ons (Cilium, CoreDNS, metrics-server...)
8. Kommander registers the new cluster

Total time: **45–60 minutes** on a real Nutanix AHV cluster.

---

## The Nutanix infrastructure layer

NKP doesn't run in a vacuum — it sits on top of the **Nutanix Cloud Infrastructure (NCI)** stack. Understanding this layer is essential because NKP connects to it at multiple points.

::image-box
---
:src: __static__/placeholder-nci-stack-diagram.png
:alt: 'NCI stack diagram showing AHV hypervisor, AOS storage OS with CVM, and Prism Central, with annotations indicating where NKP node VMs run, where the CSI driver connects, and where CAPX and CAREN API calls land'
---
_TODO: Replace with actual screenshot — three-column diagram for AHV, AOS/CVM, and Prism Central, each with an annotation showing which NKP component connects to it and how_
::

```
┌──────────────────────────────────────────────────────────────────┐
│                   Nutanix Cloud Infrastructure (NCI)             │
│                                                                  │
│  ┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
│  │     AHV     │   │      AOS         │   │  Prism Central   │  │
│  │  KVM-based  │   │  FreeBSD-based   │   │  Multi-cluster   │  │
│  │ hypervisor  │   │  storage OS CVM  │   │  control plane   │  │
│  └──────┬──────┘   └───────┬──────────┘   └────────┬─────────┘  │
│         │                  │                        │            │
│    NKP VMs run here    CSI driver            CAPX / CAREN API    │
│                        reads/writes           calls land here    │
└──────────────────────────────────────────────────────────────────┘
```

### NCI — Nutanix Cloud Infrastructure

**NCI** is Nutanix's infrastructure product tier. It includes **AOS Storage**, **AHV Virtualization**, Disaster Recovery, Flow (network security), and Cloud Clusters (NC2). It does **not** include Prism Central (that's part of *Nutanix Central*) or NKP/NDK (separate products).

When you see "NKP runs on NCI", it means: NKP node VMs run on **AHV**, their persistent storage comes from **AOS**, and the whole thing is managed through **Prism Central** (which sits in the Nutanix Central tier above NCI).

### AHV — the hypervisor

**AHV** is Nutanix's KVM-based hypervisor. Every NKP node (control plane VM, worker VM) runs as an AHV virtual machine. CAPX provisions these VMs by calling the Prism Central API — the same way you would manually create a VM in the Prism UI, but declaratively driven by Kubernetes CRDs.

NKP Metal (see below) extends this to bare-metal nodes alongside VMs.

### AOS — the storage OS

**AOS** runs inside the **Controller VM (CVM)** — a dedicated VM that runs on every Nutanix node alongside the workload VMs. The CVM is the storage brain: it provides the distributed filesystem (NDFS/DSF), replication, snapshots, compression, deduplication, and tiering for all VMs on that node.

NKP connects to AOS through two paths:

| Path | What it does |
|---|---|
| **Nutanix CSI Driver** | Kubernetes storage driver. Translates `PersistentVolumeClaim` objects into AOS volumes and file shares. Installed as an NKP add-on. |
| **NDK (Nutanix Data Services for Kubernetes)** | Extends AOS data services — snapshots, replication, compression, dedup, tiering — directly to Kubernetes `PersistentVolume` objects. Gives Kubernetes workloads access to enterprise storage features without leaving the Kubernetes API. |

> In the lab we use **Longhorn** as the storage add-on because it runs entirely inside Kubernetes without needing AOS. In a real Nutanix cluster you would use the Nutanix CSI driver + NDK instead.

### Prism Central — the control plane NKP talks to

**Prism Central (PC)** is Nutanix's multi-cluster management UI and API server. It federates multiple Nutanix clusters under one pane and exposes a REST API for automation.

CAPX and CAREN both call the Prism Central API:

- **CAPX** calls PC to create/delete/resize VMs when reconciling `NutanixMachine` objects
- **CAREN** calls PC to validate that OS images and storage containers exist before allowing cluster operations to proceed

This is why `nkp create cluster` requires `--endpoint https://<PC_IP>:9440` — that address is the Prism Central API endpoint.

### NDK — Nutanix Data Services for Kubernetes

**NDK** is a more recent layer that sits between AOS and Kubernetes. Where the CSI driver gives you basic PV provisioning, NDK gives Kubernetes workloads access to the full AOS feature set:

- **Application-consistent snapshots** of PVs
- **Cross-cluster replication** of PVs (for DR)
- **Storage efficiency** — compression, dedup, tiering — applied per-PV
- **Volume groups** — attach a single AOS volume group to multiple pods

NDK is configured via its own CRDs (`DataServicePolicy`, `ProtectionPolicy`, etc.) and is particularly relevant for stateful workloads like databases running on NKP.

### NKP Metal — bare-metal Kubernetes (new, April 2026)

**NKP Metal** extends NKP beyond AHV VMs to **bare-metal nodes**. It introduces a dual-native architecture where VMs and containers are equally first-class:

- Bare-metal nodes join NKP clusters alongside AHV VM nodes
- Targets AI/ML workloads, edge deployments, and performance-sensitive applications where VM overhead matters
- Uses the same `nkp` CLI and Kommander management plane as the AHV-based deployment

> NKP Metal was announced in April 2026. This course covers the AHV VM path. The bare-metal path uses the same CAPI/Flux/Kommander concepts — the difference is in the infrastructure provider (a bare-metal CAPI provider replaces CAPX).

### How NKP connects to NCI — summary

| NKP component | Nutanix layer it talks to | What it does |
|---|---|---|
| CAPX | Prism Central API | Creates/deletes NKP node VMs |
| CAREN | Prism Central API | Validates OS images, storage containers |
| Nutanix CSI driver | AOS (via CVM) | Provisions PersistentVolumes |
| NDK | AOS (via CVM) | Snapshots, replication, storage policies on PVs |
| Nutanix CCM | Prism Central API | Provisions L4 load balancer VIPs (replaced by MetalLB in lab) |
| NKP node VMs | AHV | Run as AHV VMs on the hypervisor |

---

## In the lab

In this course's iximious Flexbox lab, we simulate steps 3–8 manually:

::image-box
---
:src: __static__/placeholder-flexbox-lab-topology.png
:alt: 'Flexbox lab topology diagram showing 5 VMs: vm1 as operator workstation with nkp CLI and kubectl, vm2 as RKE2 control plane, vm3 through vm5 as RKE2 worker nodes, each with their IP addresses and assigned roles labeled'
---
_TODO: Replace with actual screenshot — network topology diagram of the 5-VM Flexbox lab environment with IP addresses, hostnames, and role labels (operator workstation, control plane, worker ×3)_
::

- vm2 plays the role of the control plane VM (already has RKE2 server installed)
- vm3–vm5 play worker VMs (already have RKE2 agent installed)
- vm1 is your operator workstation (nkp CLI + kubectl + Ansible)

You won't create VMs via CAPI here — the VMs already exist. But you will:
- Bootstrap the RKE2 cluster manually (the way CAPI would do it)
- Install Cilium, MetalLB, Longhorn, Traefik
- Use `k9s` to watch everything come up
- Run the same `nkp` CLI commands you'd run on a real Nutanix cluster

Open a terminal on **vm1** and confirm the tools are ready:

```bash
nkp version
kubectl version --client
k9s version
ansible --version
```

All four should print version information. If any fail, the rootfs image may need rebuilding.

---

## Check your understanding

Before moving on, you should be able to answer:

1. Why does the Bootstrap cluster get deleted?
2. What does CAPI actually store — code or data?
3. Which component deploys Cilium — RKE2, CAPI, or Flux?
4. What is the difference between a Managed cluster and an Attached cluster?
5. What is the difference between CAPX and CAREN?
6. Which Nutanix component does CAPX call when it needs to create a VM?
7. What does NDK add on top of the basic Nutanix CSI driver?
8. Why does the lab use Longhorn instead of the Nutanix CSI driver?

Answers are in the lesson above — re-read the relevant section before moving on.
