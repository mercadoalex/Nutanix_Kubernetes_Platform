---
kind: unit
title: "NKP Uses Kubernetes to Manage Kubernetes"
name: lesson-nkp-architecture-unit-1
---

## What is NKP and where does it come from?

**NKP (Nutanix Kubernetes Platform)** was born from Nutanix's acquisition of **D2iQ** (formerly Mesosphere) in 2023. D2iQ had built two battle-tested open-source projects that now form the core of NKP:

- **Konvoy** — the Kubernetes distribution layer: cluster lifecycle management built on Cluster API, with CIS-hardened node images and RKE2 as the embedded Kubernetes engine
- **Kommander** — the management layer: centralized UI, GitOps engine, multi-tenancy, observability, and an application catalog across all clusters

Nutanix wrapped these into **NKP**, announced at .NEXT in May 2024, adding tight integration with AHV, AOS storage, and Prism Central.

> NKP is the **de facto replacement for NKE (Nutanix Kubernetes Engine)**, which was deprecated in October 2025. If you are coming from NKE, NKP is its successor — same Nutanix infrastructure, completely new architecture.

### What's new — recent releases

::details-box
---
:summary: "NKP 2.17, 2.18, and NKP Metal — staying current"
---

| Release | Highlights |
|---|---|
| **NKP 2.17** *(this course)* | Ubuntu STIG-compliant node image out of the box; RKE2 1.34.x; MetalLB as the default on-prem load balancer |

<small>*STIG (Security Technical Implementation Guide) — hardening standards published by the US Defense Information Systems Agency (DISA). A STIG-compliant image has been pre-configured to meet those security benchmarks out of the box, without manual hardening.</small>
| **NKP 2.18** | Clusters fully **FIPS 140-3 compliant**; **AI Navigator MCP Server** for natural-language root cause analysis; `NKPCluster` as a single source of truth for GitOps; automatic preflight checks before cluster updates; **Istio ambient mode** support; **Grafana Loki 3** with native OpenTelemetry |

<small>*FIPS 140-3 (Federal Information Processing Standard) — US government cryptography standard that defines requirements for cryptographic modules. A FIPS 140-3 compliant cluster uses only approved algorithms and validated crypto libraries end-to-end, required for US federal and regulated-industry deployments.</small>
| **NKP Metal** *(announced .NEXT April 2026)* | Extends NKP to **bare-metal nodes** with a dual-native architecture where containers and VMs are equally first-class; storage via CSI or Cloud Native AOS; same `nkp` CLI and Kommander management plane |

<small>*Dual-native architecture — a design where both VMs and containers are first-class workload primitives on the same platform. Unlike traditional setups where VMs are the hypervisor layer and containers run inside them, dual-native treats both as equals: scheduled, managed, and observed through the same control plane without one being a wrapper for the other.</small>

This course focuses on **NKP 2.17 on AHV**. The concepts — CAPI, Flux CD, Kommander, RKE2 — are identical across versions; the differences are additive features layered on top.
::

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

::image-box
---
:src: __static__/K8sFleetManagers.png
:alt: 'Kubernetes fleet management ecosystem — NKP/Kommander, Rancher Fleet, Azure Kubernetes Fleet Manager, GKE Fleet, Karmada, SAP Gardener, k0rdent'
---
::

NKP uses **Kommander** as its fleet management layer — it federates policy, RBAC, add-ons, and access control across all Managed and Attached clusters from a single pane.

**What does "federates policy" actually mean?**
You define a policy once at the fleet level, and Kommander automatically propagates and enforces it across all member clusters — without applying it to each cluster individually.

```bash
# ❌ Without federation: repeat for every cluster
kubectl apply -f security-policy.yaml --context cluster-1
kubectl apply -f security-policy.yaml --context cluster-2
kubectl apply -f security-policy.yaml --context cluster-N

# ✅ With federation: define once, enforced everywhere
kubectl apply -f security-policy.yaml  # hub / Management Cluster
# → automatically synced to all N member clusters
```
::

::hint-box
---
:summary: "NKP's fleet management comes from D2iQ — here's why that matters"
---

NKP's fleet management layer didn't start at Nutanix. It comes from **D2iQ** — a Kubernetes company Nutanix acquired in 2023. D2iQ was the original developer of two open-source projects that now form the core of NKP:

- **Kommander** — the fleet management layer: centralized UI, GitOps, multi-tenancy, policy, observability across all clusters
- **Konvoy** — the cluster lifecycle manager built on Cluster API (CAPI)

Nutanix wrapped these into **NKP (Nutanix Kubernetes Platform)**, announced at .NEXT in May 2024. The fleet management features (Kommander multi-cluster, Attached Clusters) are available in the **NKP Ultimate** tier.

::image-box
---
:src: __static__/d21q.png
:alt: 'D2iQ — the Kubernetes company Nutanix acquired in 2023, creators of Kommander and Konvoy'
:centered: true
---
::
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

NKP defines four distinct roles for clusters. Each has a single job — and understanding which ones are permanent versus temporary, and which are optional versus required, is the fastest way to make sense of any NKP deployment diagram.

The short version:

- **Bootstrap** is ephemeral — it exists only during initial installation and is deleted once the Management Cluster is up. You will never see it again after day one.
- **Management** is the permanent control plane. Every NKP environment has exactly one. It is the prerequisite for everything else.
- **Managed / Workload** clusters are where your applications run. Most installations have one or more of these — this is the typical Management + Workload setup you will see in production.
- **Attached** clusters are fully optional. They are for organizations that already run clusters on other platforms (EKS, GKE, AKS, on-prem) and want to bring them under the same NKP governance umbrella without rebuilding them. This requires NKP Ultimate.

So in practice: if you are deploying NKP on Nutanix AHV for the first time, you will end up with **one Management Cluster and one or more Workload Clusters**. Bootstrap appears briefly during setup and disappears. Attached clusters come into the picture only if your organization has a multi-cloud or hybrid strategy.

::details-box
---
:summary: "Are these roles mandatory? Can I combine them?"
---

The four roles are **relationship labels**, not a rigid topology you must follow. NKP's tooling and documentation is built around them, but the underlying technology doesn't prevent other arrangements:

| Role | Mandatory? | Reality |
|---|---|---|
| **Bootstrap** | Only during initial install — deleted right after `nkp move` | You could use any existing K8s cluster as a temporary CAPI host; `nkp create bootstrap` just automates this |
| **Management** | Yes, if you want NKP fleet management | Without it you have no Kommander, no centralized add-on lifecycle, no fleet RBAC — you'd just be running standalone RKE2 |
| **Managed / Workload** | No — the Management Cluster *can* host workloads | Nutanix strongly discourages it in production; it blurs the control plane / data plane boundary |
| **Attached** | No — NKP Ultimate only, fully optional | You can manage external clusters independently and never attach them |

**How the topology scales in practice:**
- A home lab might run Management + Workload on the same cluster
- A large enterprise might have one Management Cluster per region with dozens of Managed Clusters under each
- A hybrid org might attach EKS/GKE clusters alongside AHV-native Managed Clusters

The "four roles" model is the **canonical NKP path** — not a technical wall.
::

::image-box
---
:src: __static__/four-cluster-roles-overview.png
:alt: 'NKP four cluster roles — Bootstrap, Management, Workload, and Attached clusters'
---
::

### 1. Bootstrap Cluster 

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

### 2. Management Cluster 

The **permanent brain** of your NKP environment.

- Self-hosted: after `nkp move`, it manages itself
- Runs Kommander — the NKP control plane UI and API
- Runs Flux CD — GitOps engine that reconciles all add-ons
- Creates and manages all other clusters via Cluster API
- One Management Cluster per NKP environment

> We will look at the internal layering of the Management Cluster in detail later — see [Management cluster architecture](#management-cluster-architecture).

### 3. Managed / Workload Cluster

Where your applications run.

- Created and lifecycle-managed by the Management Cluster
- Has its own RKE2 control plane and worker nodes
- Add-ons deployed via Flux CD from the Management Cluster
- Can be upgraded, scaled, or deleted without touching the Management Cluster

### 4. Attached Cluster (Ultimate only)

An **existing** cluster (EKS, GKE, on-prem RKE2) brought under NKP management.

- Not created by NKP — just registered with Kommander
- Gains centralized add-on management, RBAC, and observability
- Requires NKP Ultimate license

---

## The technology stack

Each layer has a specific job:

::image-box
---
:src: __static__/nkp-full-stack-diagram.png
:alt: 'NKP full technology stack diagram with layers from Nutanix AHV at the bottom up through AOS, Prism Central, Rocky Linux, RKE2, CAPI/CAPX/CAREN, Flux CD, and Kommander at the top'
---
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


## Management cluster architecture

The Management Cluster is not a single monolithic application — it is a layered platform where each layer has a clearly defined responsibility. Understanding these layers explains why Flux CD, Prometheus, and CAPI all coexist in the same cluster without stepping on each other.

```
┌─────────────────────────────────────────────────────────────────┐
│  Catalog / Apps   — partner apps, NKP Insights                  │
├─────────────────────────────────────────────────────────────────┤
│  Platform         — Prometheus, Loki, Grafana, Velero,          │
│                     Gatekeeper                                  │
├─────────────────────────────────────────────────────────────────┤
│  Managers         — Flux CD, Git Operator, DexAuth              │
├─────────────────────────────────────────────────────────────────┤
│  Cluster          — CAPI, cert-manager, CNI, CSI                │
└─────────────────────────────────────────────────────────────────┘
```

| Layer | Components | Responsibility |
|---|---|---|
| **Cluster** | CAPI, cert-manager, CNI, CSI | Infrastructure lifecycle — provisions, scales, and upgrades cluster nodes; manages TLS certificates and pod networking |
| **Managers** | Flux CD, Git Operator, DexAuth | Platform orchestration — reconciles add-ons from Git, manages authentication and SSO federation |
| **Platform** | Prometheus, Loki, Grafana, Velero, Gatekeeper | Operational services — observability, log aggregation, backup/DR, and policy enforcement across all managed clusters |
| **Catalog / Apps** | Partner and customer apps, NKP Insights | Marketplace and diagnostics — deploy curated applications from the NKP catalog; NKP Insights scans clusters for health and security findings |

The layers form a dependency chain: **Cluster** must be healthy before **Managers** can reconcile add-ons; **Managers** (Flux CD) deploy everything in **Platform**; **Platform** must be running before the NKP **Catalog** app ecosystem is useful.

::details-box
---
:summary: "Where does Kommander fit in this layering?"
---

Kommander spans the **Managers** and **Platform** layers. Its core API server and workspace controller run at the Managers layer (they need DexAuth for authentication and Flux CD to push configurations to member clusters). Its UI and the Kommander add-on catalog sit at the Platform / Catalog layer.

When you open the Kommander dashboard, you are talking to an API server that was itself deployed by Flux CD — the same GitOps loop that deploys everything else on the Management Cluster.
::

---

## CAPI, CAPX, and CAREN — how they divide the work

These three components are often confused because they all live inside the same cluster and cooperate tightly. Here is how to tell them apart:

::image-box
---
:src: __static__/capi-capx-caren-relationship.png
:alt: 'Relationship diagram showing CAPI as the central framework with CAPX as the Nutanix infrastructure provider below it and CAREN as the lifecycle policy layer intercepting requests between the CLI and CAPX'
---
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

::image-box
---
:src: __static__/fit-together-cluster-create-time -v1.png
:alt: 'Cluster create time flow: nkp create cluster → NutanixCluster + Cluster objects in Bootstrap cluster → CAREN BeforeClusterCreate hook validates OS image and storage container → CAPI reconciles Machine objects → CAPX calls Prism Central API creating AHV VM and injecting RKE2 bootstrap via cloud-init → RKE2 starts, node joins cluster'
---
::

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
:src: __static__/fit-together-cluster-create-time -v1.png
:alt: 'End-to-end cluster creation request flow diagram from nkp CLI through CAREN, CAPI, CAPX, Prism Central, AHV VM boot, RKE2 startup, Flux CD add-on deployment, and Kommander registration'
---
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
:src: __static__/Nutanix-cloud-infra-v1.png
:alt: 'NCI stack diagram showing AHV hypervisor, AOS storage OS with CVM, and Prism Central, with annotations indicating where NKP node VMs run, where the CSI driver connects, and where CAPX and CAREN API calls land'
---
_Nutanix Cloud Infrastructure (NCI) stack: AHV hosts NKP node VMs, AOS (via CVM) provides storage for the CSI driver and NDK, and Prism Central exposes the API that CAPX and CAREN call to provision and validate cluster resources._
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

## Infrastructure prerequisites — the architect's checklist

Before `nkp create cluster` can succeed on a real Nutanix AHV environment, six infrastructure conditions must be true. Each one has a specific component that depends on it — get any of them wrong and the cluster either fails to create or gets stuck silently in `Provisioning`.

This section explains **why** each prerequisite exists, not just what it is.

::details-box
---
:summary: "1. Prism Central 7.3 or 7.5 + AOS 7.3 or 7.5"
---

NKP is not a standalone application — it is a set of controllers that call the Prism Central API continuously. **CAPX** provisions VMs, **CSI** creates storage volumes, and **CCM** (Cloud Controller Manager) discovers node metadata. All three depend on specific API capabilities that were introduced in PC/AOS 7.3.

If PC or AOS is on an older version, those controllers fail silently: VMs are never created, volumes are never mounted, nodes are never registered. The cluster gets stuck in `Provisioning` with no obvious error message.

**Interview answer:** *"Why version PC and AOS?"* → *"Because it is an integrated stack, not a standalone app. NKP's controllers depend on specific PC API endpoints for infra provisioning, storage, and node metadata. Version mismatch means API incompatibility — cluster stuck in Provisioning."*
::

::details-box
---
:summary: "2. Prism Central API on port 9440"
---

Port 9440 is the Prism Central REST API endpoint. NKP connects to it with a least-privilege service account for three critical operations:

| Controller | What it calls PC:9440 for |
|---|---|
| **CAPX** | List subnets, create/delete VMs (control plane + workers) |
| **CSI driver** | Create and attach persistent volumes |
| **CCM** | Discover node metadata, assign load balancer VIPs |

If there are firewalls, proxies, or invalid TLS certificates blocking port 9440, the cluster creates but never becomes `Ready`. **This is the number one failure point in NKP deployments.**

**Interview answer:** *"How do you debug?"* → *"Check connectivity to PC:9440 from the nodes first. Then check the logs of `capx-controller-manager`, `csi-controller`, and `ccm` — they tell you exactly which API call is failing."*
::

::details-box
---
:summary: "3. Subnet with IPAM or DHCP configured in Prism Central"
---

CAPI assigns IPs to control plane and worker nodes automatically during provisioning. It does this by referencing a Prism Central subnet that has an **IPAM pool** (or DHCP) configured.

Without IPAM/DHCP on the subnet, CAPI's `MachineSet` controller cannot allocate IPs and the nodes never boot into the cluster. The `NutanixMachine` objects stay in a pending state with no useful error.

**Interview answer:** *"Why not static IPs?"* → *"You can, but CAPI expects a subnet with an IPAM pool configured in PC. Without it, MachineSets cannot provision nodes. It is a network design prerequisite, not just a configuration detail."*
::

::details-box
---
:summary: "4. Storage container configured for the CSI driver"
---

The Nutanix CSI driver (Nutanix Volumes / Files) creates persistent volumes by allocating space inside a **storage container** in Prism Element. This container name is passed to `nkp create cluster` via `--csi-storage-container`.

Without a valid storage container, the CSI driver starts but cannot fulfil any `PersistentVolumeClaim`. Any pod that requests storage stays in `Pending` indefinitely.

**Interview answer:** *"What happens if you don't configure the storage container?"* → *"The cluster comes up, but you have no persistence. StatefulSets, databases, anything with a PVC is blocked. It is the bridge between Kubernetes storage abstractions and the Nutanix storage layer."*
::

::details-box
---
:summary: "5. Pre-built OS image (Rocky Linux 9.7 CIS-hardened) uploaded to Prism Central"
---

CAPI does not install the OS from scratch. It references a **pre-built image** that already contains the kernel, `containerd`, `kubelet`, and all CIS hardening. CAPX calls Prism Central to clone that image when creating each node VM.

The exact image filename matters — `nkp create cluster` takes `--control-plane-vm-image` with the full image name as it appears in Prism Central. If the image is missing or the name is wrong, the cluster fails immediately with an image-not-found error from CAREN's `BeforeClusterCreate` hook.

**Interview answer:** *"Can you use your own image?"* → *"Yes, but it must follow NKP's CIS-hardened spec and include the exact packages. A wrong image creates VMs that either don't boot or don't join the control plane. That is why Nutanix validates and distributes official images — they are tested against the specific NKP version."*
::

::hint-box
---
:summary: "⚠️ Not supported: Prism Central in dual-stack (IPv4 + IPv6)"
---

NKP does **not** support Prism Central configured in dual-stack mode. This is a hard blocker — not a warning.

If a customer has PC running dual-stack, CAPX and CAREN cannot reliably resolve API endpoints and cluster creation fails. There is no workaround.

**Discovery checklist item:** Verify PC network mode during the pre-engagement discovery phase. If dual-stack is present, PC must be migrated to IPv4-only before NKP installation begins. This is a prerequisite that cannot be deferred.

**Interview answer:** *"How do you avoid this with a customer?"* → *"You catch it in discovery. If the customer has dual-stack, you scope a PC migration to IPv4-only as a prerequisite work item before any NKP engagement starts."*
::

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

---

## Lab Topology

::image-box
---
:src: __static__/Flexbox-lab-topology-v1.png
:alt: 'Flexbox lab topology showing vm1 as bootstrap/operator workstation and vm2–vm5 as the NKP cluster nodes'
---
_Flexbox 5-VM lab topology: vm1 runs the Bootstrap kind cluster and operator tooling; vm2 is the Management Cluster control plane; vm3–vm5 are worker nodes. All VMs share a flat 192.168.0.x network._
::
