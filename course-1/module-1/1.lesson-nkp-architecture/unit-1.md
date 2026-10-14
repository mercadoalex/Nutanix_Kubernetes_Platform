---
kind: unit
title: "NKP Uses Kubernetes to Manage Kubernetes"
name: lesson-nkp-architecture-unit-1
---

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
│  Nutanix AHV        — hypervisor                    │
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

## In the lab

In this course's iximious Flexbox lab, we simulate steps 3–8 manually:

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

Answers are in the lesson above — re-read the relevant section before moving on.
