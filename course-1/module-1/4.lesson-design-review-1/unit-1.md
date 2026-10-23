---
kind: unit
title: "Design Review 1: Financial Enterprise Multi-Site Deployment"
name: lesson-design-review-1-unit-1
---

::remark-box
This is a **design review exercise** — the kind of conversation that happens in a real consulting engagement before a single command is run. Read it as if you are in the room. Every decision here maps directly to concepts from the previous lesson.
::

## Customer context

A global financial services firm wants to adopt NKP across three datacenters:

| Site | Location | Role |
|---|---|---|
| NYC | New York | Primary — HQ, trading systems |
| LHR | London | Regional — EMEA workloads |
| FRA | Frankfurt | Regional — EU data residency |

**Current state:**
- Nutanix AOS **6.5**, Prism Central **6.10** across all three sites
- 200+ existing VMs running traditional workloads
- Target: **50 workload clusters** for application teams

**Requirements:**
- FIPS 140-3 compliance — non-negotiable (regulated financial sector)
- Air-gapped deployment — no direct internet access from production DCs
- Self-service model — 5 DevOps engineers need to enable ~40 developer teams
- Unified governance and audit trail across all sites

---

## Risk 1 — Version gap (the first thing you raise)

Before any design discussion, you stop the room:

> *"Your AOS 6.5 and PC 6.10 are not compatible with NKP. The minimum requirement is AOS 7.3 and PC 7.3. This is not a minor patch — it is a jump of two to three major generations. Everything else we design today depends on resolving this first."*

**Why this matters:** CAPX, the CSI driver, and the Cloud Controller Manager all call the Prism Central API. They depend on API capabilities that were introduced in PC/AOS 7.3. On 6.x, those controllers fail silently — VMs are never created, volumes never mounted, nodes never registered. The cluster gets stuck in `Provisioning` with no useful error.

**Proposed roadmap:**

```
Sprint 0  →  Upgrade AOS + PC on NYC pilot cluster only
Sprint 1  →  Validate PC 7.3+ API connectivity, run NKP preflight checks
Sprint 2  →  Install NKP management cluster on NYC
Sprint 3  →  Replicate validated config to LHR and FRA
```

> If you skip Sprint 0 and 1, everything downstream fails. Version compatibility is dependency #1.

::details-box
---
:summary: "Interview answer: why version PC and AOS before anything else?"
---
*"Because NKP is an integrated stack, not a standalone application. Its controllers — CAPX, CSI, CCM — depend on specific Prism Central API endpoints introduced in 7.3. A version mismatch is an API incompatibility, not just a feature gap. The symptom is a cluster stuck in Provisioning with no actionable error. You catch this in pre-engagement discovery, not during install."*
::

---

## Risk 2 — Multi-site topology (the design question with no single right answer)

With three datacenters, there are two architecturally valid options:

### Option A — One Management Cluster per region

```
NYC  →  Management Cluster A  →  manages NYC workload clusters
LHR  →  Management Cluster B  →  manages LHR workload clusters
FRA  →  Management Cluster C  →  manages FRA workload clusters
```

| | Detail |
|---|---|
| ✅ **Fault isolation** | A failure in NYC does not affect the ability to manage LHR or FRA |
| ✅ **Latency** | CAPI controllers run close to the infrastructure they manage |
| ✅ **Data residency** | FRA Management Cluster never sends EU workload metadata outside the EU |
| ❌ **Operational overhead** | Three management clusters to upgrade, monitor, and license |
| ❌ **No global single pane** | You need Kommander federation or an external aggregation layer for a unified view |

### Option B — Single global Management Cluster (NYC) + Managed Clusters everywhere

```
NYC  →  Management Cluster (global)
         ├─ NYC workload clusters  (managed)
         ├─ LHR workload clusters  (managed)
         └─ FRA workload clusters  (managed)
```

| | Detail |
|---|---|
| ✅ **Single pane of glass** | One Kommander dashboard for all 50 clusters |
| ✅ **Lower operational overhead** | One management cluster to maintain |
| ❌ **Single point of failure** | If NYC is unavailable, you cannot create, upgrade, or delete clusters in LHR or FRA (existing workloads keep running, but lifecycle operations are blocked) |
| ❌ **Data residency risk** | Cluster metadata for FRA EU workloads transits to NYC — may conflict with GDPR Article 44 |

### Recommendation for a regulated financial firm

**Option A — three independent Management Clusters.**

The failure isolation and data residency arguments outweigh the operational overhead in a financial context. Losing the ability to manage production clusters because a single DC is unreachable is not an acceptable risk for a firm running trading systems.

Operational overhead is addressed by standardizing the management cluster configuration as code (GitOps) and automating upgrades — you maintain one Flux configuration, applied to three identical clusters.

::details-box
---
:summary: "Interview answer: single vs. multi management cluster?"
---
*"For a financial firm with data residency requirements and high availability needs, I recommend one Management Cluster per region. The failure blast radius of a global management cluster is too high — if NYC goes down, you lose lifecycle control of all 50 clusters. Option A with GitOps-standardized configuration gives you resilience without compounding operational complexity."*
::

---

## Risk 3 — FIPS 140-3 compliance

NKP 2.18 supports fully FIPS 140-3 compliant clusters. What this means in practice:

- Node images use **Ubuntu Pro** with FIPS-validated cryptographic modules
- All intra-cluster communication uses only NIST SP 800-131A approved cipher suites
- The RKE2 binary is compiled against the FIPS-validated Go crypto library
- etcd, kube-apiserver, and containerd are all configured to use FIPS-approved TLS

**For the air-gapped case:** NKP 2.18 includes Nutanix Data Services for Kubernetes (NDK) in the air-gapped bundle by default. No additional licensing or separate download is required for storage services in this mode.

**What you verify in discovery:**
- Confirm the customer is targeting NKP 2.18+ (FIPS is not available in 2.17)
- Confirm FIPS-compliant Ubuntu Pro images are available in the air-gapped registry
- Confirm no non-FIPS components are added via the catalog (some community add-ons use non-validated crypto)

::details-box
---
:summary: "Interview answer: how do you deliver FIPS 140-3 on NKP?"
---
*"NKP 2.18 supports FIPS 140-3 end-to-end. You enable it at cluster creation time — the flag selects FIPS-validated node images and configures all components to use approved crypto modules only. The challenge in an air-gapped environment is ensuring your internal registry has the FIPS Ubuntu Pro images, not just the standard Rocky Linux ones. We include that as a preflight check before any cluster creation."*
::

---

## Risk 4 — Air-gapped deployment design

An air-gapped NKP deployment means no component can reach the internet at runtime. Everything must be pre-staged.

**What needs to be pre-staged:**

| Artifact | Where it lives | Used by |
|---|---|---|
| NKP container image bundle | Internal registry (Harbor) | `nkp create cluster` |
| CIS-hardened node OS images (`.qcow2`) | Prism Central image service | CAPX (VM provisioning) |
| Helm chart bundle | Internal chart repository | Flux CD (add-on lifecycle) |
| CNI images (Cilium) | Internal registry | CAREN (CNI injection) |
| CSI driver images | Internal registry | CAREN (CSI injection) |
| OS package mirror (yum/apt) | Internal mirror | Node bootstrap via cloud-init |

**Deployment flow:**

```bash
# 1. Generate manifests dry-run (on the operator workstation, before air-gap)
nkp create cluster nutanix \
  --cluster-name prod-nyc-01 \
  --registry-mirror https://harbor.internal \
  --dry-run -o yaml > prod-nyc-01.yaml

# 2. Version the manifest in Git
git add prod-nyc-01.yaml && git commit -m "add prod-nyc-01 cluster spec"

# 3. Flux applies it from the internal Git server — no internet required
```

The key insight: `--dry-run -o yaml` lets you inspect every object CAPI will create before committing. Combined with GitOps, every cluster becomes an auditable, reviewable artifact — which is exactly what a financial firm's change management process requires.

::details-box
---
:summary: "Interview answer: how do you handle air-gapped NKP?"
---
*"Air-gapped NKP requires pre-staging four categories of artifacts: container images, OS images in Prism Central, Helm charts, and package mirrors. We use Harbor as the internal registry and mirror. The workflow is: download once on a connected machine, transfer to the air-gapped environment via secure media, load into Harbor, then point all NKP components at the internal mirror. The `--registry-mirror` flag on `nkp create cluster` handles the runtime redirection."*
::

---

## Risk 5 — Self-service model for 40 developer teams

The constraint: 5 DevOps engineers cannot manually provision clusters for 40 teams. The solution is a three-layer self-service model:

**Layer 1 — ClusterClass templates (what devs choose from)**

Pre-approved cluster sizes defined by the platform team. Developers pick a size; they do not design infrastructure:

| Template | Control Plane | Workers | Use case |
|---|---|---|---|
| `nkp-small` | 1 node | 2 nodes | Dev / staging |
| `nkp-medium` | 3 nodes | 4 nodes | Production apps |
| `nkp-large` | 3 nodes | 8 nodes | Data-intensive workloads |

**Layer 2 — GitOps workflow (how clusters get created)**

```
Dev team  →  PR in Git with cluster spec  →  Platform team reviews  →  Merge  →  Flux deploys
```

No direct `kubectl` or `nkp` access for developers. Every cluster creation goes through a code review. This gives the platform team control without being a manual bottleneck.

**Layer 3 — Policy enforcement with Gatekeeper/OPA**

Constraints enforced automatically — no human review needed for these:

- All clusters must use FIPS-compliant node images
- All clusters must have logging and monitoring enabled
- Storage class must be `retain` for namespaces tagged `data-critical`
- No cluster can be created outside an approved subnet range

::details-box
---
:summary: "Interview answer: how do 5 DevOps support 40 dev teams?"
---
*"You don't scale people — you scale automation. ClusterClass gives developers a menu of pre-approved configurations. GitOps gives the platform team an audit trail and a review gate without being a manual bottleneck. Gatekeeper enforces the compliance rules automatically so the DevOps team isn't manually checking every cluster. The platform team's job shifts from provisioning to maintaining the templates and policies."*
::

---

## Risk 6 — Storage design for regulated workloads

Financial workloads have specific storage requirements that default configurations do not address:

| Requirement | Implementation |
|---|---|
| **Dedicated storage per team** | CSI `StorageClass` per namespace, backed by dedicated Nutanix storage containers |
| **No accidental data deletion** | `reclaimPolicy: Retain` on all production `StorageClass` objects — volumes survive PVC deletion |
| **Backup and point-in-time recovery** | Velero (bundled NKP add-on) + Nutanix volume snapshots for application-consistent backups |
| **Storage quotas** | Kubernetes `ResourceQuota` per namespace to prevent one team consuming all storage capacity |
| **Cross-site replication** | NDK `ProtectionPolicy` CRDs for PV replication between NYC and LHR/FRA for DR |

**Critical detail on `reclaimPolicy: Retain`:** In a default Kubernetes setup, deleting a PVC deletes the underlying volume. For a trading system or database, this is catastrophic. `Retain` means the volume stays in Prism Central even after the PVC is gone — a human must explicitly release it. Always the default for financial workloads.

::details-box
---
:summary: "Interview answer: storage design for a financial firm?"
---
*"Three non-negotiables for financial storage on NKP: Retain reclaim policy so no volume is ever automatically deleted, Velero for application-consistent backups with NDK snapshots, and ResourceQuota per namespace for capacity governance. For DR, NDK ProtectionPolicy gives you cross-site PV replication without leaving the Kubernetes API — the DR runbook becomes a kubectl command, not a storage admin ticket."*
::

---

## Design summary

| Decision | Recommendation | Rationale |
|---|---|---|
| Version upgrade | AOS 7.3+ and PC 7.3+ before NKP install | Hard dependency — no workaround |
| Multi-site topology | One Management Cluster per region (Option A) | Fault isolation + EU data residency |
| FIPS compliance | NKP 2.18 with FIPS-validated Ubuntu Pro images | Only version with full FIPS 140-3 support |
| Air-gap | Harbor mirror + dry-run GitOps workflow | No internet dependency at runtime |
| Self-service | ClusterClass + GitOps PR workflow + Gatekeeper | Scale without scaling headcount |
| Storage | Retain policy + Velero + NDK ProtectionPolicy + quotas | Compliance, DR, and capacity governance |
