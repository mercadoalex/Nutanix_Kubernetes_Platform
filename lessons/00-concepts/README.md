# Lesson 00 — NKP Architecture: Core Concepts

> **Tier:** Reading / No playground required  
> **Purpose:** Establish the mental model before any hands-on work. Every other lesson assumes fluency with these terms.

---

## The big picture

NKP (Nutanix Kubernetes Platform) is not just one Kubernetes cluster — it is a **fleet management system** built on top of Kubernetes itself. The key insight is this:

> NKP uses Kubernetes to manage Kubernetes.

The control plane that creates, scales, upgrades, and deletes clusters is itself running inside a Kubernetes cluster. That cluster is called the **Management Cluster**.

---

## The four cluster roles

### 1. Bootstrap Cluster — *Clúster de arranque*

A **temporary** cluster that exists only during the initial installation.

- Created automatically by `nkp create bootstrap` on the operator workstation
- Runs as a `kind` (Kubernetes-in-Docker) cluster — no VMs required
- Its sole job: host the Cluster API controllers long enough to provision the Management Cluster
- **Deleted** once `nkp move` completes — it has no role in day-to-day operations

```
nkp create bootstrap
# → kind cluster appears on your laptop/workstation
# → CAPI controllers + Nutanix provider start inside it
```

Think of the Bootstrap Cluster as the scaffolding you erect to build a building — once the building stands on its own, the scaffolding comes down.

---

### 2. Management Cluster — *Clúster de gestión*

The **permanent brain** of the NKP fleet. Self-managed.

- Created on real infrastructure (AHV VMs) by the Bootstrap Cluster's CAPI controllers
- After `nkp move`, the CAPI controllers are now running *inside* this cluster — it manages itself
- Hosts **Kommander** — NKP's multi-cluster management UI and API
- Hosts all `HelmRelease` and `Kustomization` resources that push add-ons to the fleet
- Never runs application workloads — dedicated entirely to control-plane responsibilities

```
nkp create cluster --provider=nutanix --cluster-name=management ...
nkp move  # pivots CAPI from bootstrap → management cluster
```

**In the lab (Flexbox):**  
vm2 is the Management Cluster control plane. vm3–vm5 are its workers. These four VMs together *are* the Management Cluster in the lab topology.

---

### 3. Managed / Workload Cluster — *Clúster gestionado / de trabajo*

Kubernetes clusters that the Management Cluster **owns and operates**.

- Created by running `nkp create cluster` again, this time from the Management Cluster context
- The Management Cluster's CAPI provisions the AHV VMs, installs RKE2, joins the nodes
- Full lifecycle (scale, upgrade, delete, repair) is controlled declaratively via CRD objects in the Management Cluster
- Students and application teams get a `kubeconfig` for their Workload Cluster and interact with it directly — they never touch the Management Cluster

```bash
# Switch context to the management cluster
nkp get kubeconfig --cluster-name=management > mgmt.kubeconfig
export KUBECONFIG=mgmt.kubeconfig

# Create a workload cluster
nkp create cluster --provider=nutanix --cluster-name=workload-01 ...

# Get kubeconfig for the workload cluster
nkp get kubeconfig --cluster-name=workload-01 > workload.kubeconfig
```

You can have **many** Workload Clusters, all managed by a single Management Cluster.

---

### 4. Attached Cluster — *Clúster adjunto* ⭐ NKP Ultimate only

Kubernetes clusters that **already exist** and are brought under NKP governance — without NKP managing their lifecycle.

- Examples: Amazon EKS, Azure AKS, Google GKE, on-premises clusters, other RKE2 clusters
- Connected to NKP via the `nkp attach cluster` command, which installs a small agent
- Once attached, Kommander can push the same add-ons, RBAC policies, and monitoring to them just like Managed Clusters
- NKP does **not** create, scale, or delete Attached Clusters — that is still managed by the original provider (AWS, Azure, etc.)

```bash
nkp attach cluster --cluster-name=eks-prod --kubeconfig=./eks.kubeconfig
```

> 🔒 **This feature requires NKP Ultimate.** It is not available in NKP Pro.  
> Attached Clusters are not covered in the hands-on labs of this course (no EKS/AKS available in the playground), but the concept appears in the architecture diagrams.

---

## The technology underneath

NKP is not built from scratch — it assembles best-of-breed open source components into a coherent platform.

```
┌─────────────────────────────────────────────────────────────┐
│                         NKP                                 │
│                                                             │
│  Kommander  ────────────────────────────────────────────    │
│  (multi-cluster UI, policy federation, RBAC, Workspaces)    │
│                                                             │
│  Flux CD  ──────────────────────────────────────────────    │
│  (GitOps engine: HelmRelease, Kustomization)                │
│  add-ons: Longhorn, Prometheus+Thanos, Grafana, Velero, …   │
│                                                             │
│  Cluster API (CAPI)  ───────────────────────────────────    │
│  (declarative cluster lifecycle: create/scale/upgrade)      │
│  provider: NutanixCluster → Prism Central API → AHV VMs     │
│                                                             │
│  RKE2  ─────────────────────────────────────────────────    │
│  (hardened K8s on every node: apiserver, etcd, kubelet)     │
│  runtime: containerd  │  CNI: Cilium (default) / Calico     │
│  ingress: Traefik     │  LB on-prem: MetalLB                │
└─────────────────────────────────────────────────────────────┘
```

| Component | Origin | What it does in NKP |
|---|---|---|
| **Cluster API (CAPI)** | CNCF / sig-cluster-lifecycle | Declarative lifecycle for every cluster in the fleet |
| **CAPI Nutanix Provider** | Nutanix | Translates `NutanixCluster`/`NutanixMachine` CRDs → Prism Central API calls |
| **RKE2** | Rancher / SUSE | The hardened K8s distribution running on every node (CIS-hardened, FIPS-capable) |
| **Flux CD** | CNCF | GitOps engine; manages all add-ons as `HelmRelease` + `Kustomization` objects |
| **Kommander** | Nutanix | Multi-cluster dashboard; federates policy, RBAC, and add-ons across the fleet |
| **Cilium** | CNCF | Default CNI — eBPF-based networking, network policy, load balancing |
| **Calico** | Tigera | Alternative CNI — mature, widely deployed, BGP peering support |
| **Traefik** | Traefik Labs | Default Layer 7 ingress controller — routes HTTP/S traffic by path or header |
| **MetalLB** | CNCF sandbox | On-premises load balancer — assigns VIPs on bare-metal/AHV; used in labs |
| **Longhorn** | Rancher / SUSE | Distributed block storage add-on; ships in NKP catalog; used in lab Tier 3 |
| **Prometheus + Thanos** | CNCF | Metrics collection (Prometheus) + long-term storage & HA aggregation (Thanos) |
| **Grafana** | Grafana Labs | Metrics and log visualization; pre-built NKP dashboards included |
| **Velero** | VMware / CNCF | Backup, disaster recovery, and workload migration for stateful apps |
| **NDK** | Nutanix | Nutanix Data for Kubernetes — async replication and data protection for stateful apps on AHV |

---

## Full lifecycle in one diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  STEP 1 — Bootstrap                                              │
│  vm1 (operator workstation)                                      │
│  nkp create bootstrap  →  kind cluster (temporary)              │
│                              └─ CAPI + Nutanix provider          │
└───────────────────────┬──────────────────────────────────────────┘
                        │
                        ▼  [📺 demo only — requires real AHV]
┌──────────────────────────────────────────────────────────────────┐
│  STEP 2 — Management Cluster provisioning                        │
│  CAPI calls Prism Central → AHV VMs created → RKE2 installed    │
│  Result: Management Cluster is running on real hardware          │
└───────────────────────┬──────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 3 — Pivot                                                  │
│  nkp move  →  CAPI controllers move from kind → Management       │
│  Bootstrap kind cluster is deleted                               │
│  Management Cluster is now self-hosted                           │
└───────────────────────┬──────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│  STEP 4 — Workload Clusters (repeat as needed)                   │
│  nkp create cluster → Management CAPI → AHV VMs → RKE2          │
│  Each Workload Cluster gets its own kubeconfig                   │
└───────────────────────┬──────────────────────────────────────────┘
                        │
                        ▼  (NKP Ultimate only)
┌──────────────────────────────────────────────────────────────────┐
│  STEP 5 — Attached Clusters                                      │
│  nkp attach cluster (EKS / AKS / GKE / on-prem)                 │
│  Kommander pushes unified policy + add-ons                       │
└──────────────────────────────────────────────────────────────────┘
```

---

## Editions at a glance

| | NKP Pro | NKP Ultimate |
|---|---|---|
| Management Cluster | ✅ | ✅ |
| Managed Clusters (AHV, vSphere, bare-metal) | ✅ | ✅ |
| Kommander (multi-cluster management) | ✅ | ✅ |
| Flux-based add-on catalog | ✅ | ✅ |
| **Attached Clusters** (EKS, AKS, GKE, on-prem) | ❌ | ✅ |
| **Federated governance across hybrid/multi-cloud** | ❌ | ✅ |

---

## Key terminology quick-reference

| English | Español | One-liner |
|---|---|---|
| Management Cluster | Clúster de gestión | El cerebro auto-gestionado de NKP |
| Managed / Workload Cluster | Clúster gestionado / de trabajo | Clústeres de aplicaciones creados por el Management |
| Attached Cluster | Clúster adjunto | Clústeres externos incorporados a NKP (solo Ultimate) |
| Bootstrap Cluster | Clúster de arranque | Clúster kind temporal, solo durante la instalación |
| Cluster API (CAPI) | — | Base declarativa para el ciclo de vida de clústeres |
| Kommander | — | Panel multi-clúster de NKP |
| Pivot / `nkp move` | Pivote | Traslado de los controladores CAPI al Management Cluster |

---

## Supported node OS images

NKP supports multiple node OS images. The course uses Rocky Linux 9.7 to match the default NKP AHV image.

| OS | Notes |
|---|---|
| **Rocky Linux** | Default for AHV — used in this course |
| **Ubuntu** | Supported alternative |
| **Flatcar Container Linux** | Immutable, container-optimised OS |
| **BYOI** | Bring Your Own Image — custom OS images for specific compliance needs |

---

## NKP + AHV Compatibility Matrix

| NKP Version | K8s Versions | Rocky Image | AOS Min | Prism Central Min |
|---|---|---|---|---|
| **2.18** | 1.35.x, 1.34.x | Rocky 9.8 *(inferred)* | 7.5 | pc.7.5 |
| **2.17** ← *this course* | 1.34.x, 1.33.x | Rocky 9.7 | 7.3 | pc.7.3 |
| 2.16 | 1.33.x, 1.32.x | Rocky 9.6 | 6.10 | pc.2024.2 |
| 2.15 | 1.32.x, 1.31.x | Rocky 9.5 | 6.10 | pc.2024.2 |

> Source: [nkp-quickstart/nkp_compatibility.json](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp_compatibility.json)
> Each NKP release supports the current K8s minor **and one version back** — supports in-place cluster upgrades without an OS image change.

---

## References

> 📖 **Nutanix Cloud Bible — NKP chapter:**
> [https://www.nutanixbible.com/18a-book-of-cloud-native-services-nutanix-kubernetes-platform.html](https://www.nutanixbible.com/18a-book-of-cloud-native-services-nutanix-kubernetes-platform.html)
> *(Based on NKP 2.12 / PC 2024.1 — this course targets NKP 2.17; concepts are consistent, some UI details may differ)*

> 🔧 **NKP Quickstart (Nutanix Dev):**
> [https://github.com/nutanixdev/nkp-quickstart](https://github.com/nutanixdev/nkp-quickstart)
> Reference implementation with cloud-init, `nkp-env`, `nkp create cluster` flags, and automated `nkpDeploy.sh`. MIT License.

---

## Next steps

➡️ [Lesson 01 — Getting the NKP OS Image](../01-os-image/README.md)
