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
│  + Nutanix provider — provisions VMs on AHV         │
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
| **Cluster API (CAPI)** | Kubernetes extension that models clusters as CRDs. `NutanixCluster`, `NutanixMachine` objects describe your infrastructure. |
| **Flux CD** | GitOps operator. Reads HelmRelease objects and ensures add-ons are installed and up to date. |
| **Kommander** | NKP's management UI. Workspaces, projects, centralized RBAC, add-on catalog. |

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
