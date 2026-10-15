# Course Roadmap — Consulting Architect Cloud Native (NKP)

Gaps identified via QA session. Grouped by priority. Will be addressed in future lessons.

---

## P1 — Must-have (CA-CN cannot skip these)

### 1. Multi-cluster topology design
When to use 1 Management + N Workload vs. hub-spoke vs. regional. Kommander workspace hierarchy (global → workspace → project). Attached Clusters (NKP Ultimate). Control plane placement: on-prem AHV vs. NC2 vs. hybrid. Reference architectures: 3-node dev, 5-node HA prod, 20-node GPU cluster.

### 2. High Availability design
etcd quorum math (why 3, why 5, never 4). Split-brain scenarios. Control plane VIP (MetalLB / Nutanix CCM). CAPX machine health checks (automatic node replacement). etcd backup and restore. Velero + etcd snapshot schedules, RTO/RPO targets.

### 3. NKP vs. the competition
Positioning against OpenShift, Rancher RKE2, Tanzu, and EKS Anywhere. Technical comparison: CAPI vs. OCP Machine API, Flux vs. ArgoCD, Cilium vs. OVN-Kubernetes, hypervisor-agnosticism vs. vSphere lock-in. When NKP is *not* the right answer.

### 4. Disaster Recovery architecture
What Velero backs up and what it doesn't. Backup targets: Nutanix Objects (S3-compatible), MinIO, AWS S3. etcd snapshots vs. Velero. Cross-cluster restore. NDK ProtectionPolicy vs. Velero. RTO/RPO design with Longhorn snapshots.

### 5. Identity & Access Management (Enterprise IAM)
OIDC flow: Dex (bundled) → AD/LDAP/Okta → kubeconfig generation. Kommander Groups mapping AD groups to RBAC roles. Workspace-level RBAC. Service accounts for CI/CD. kubeconfig lifecycle (token expiry, refresh). Audit logging → SIEM.

---

## P2 — Important (senior vs. junior architect)

### 6. Storage architecture design
Decision tree: Longhorn (dev) vs. Nutanix CSI (production) vs. NDK (enterprise data services). StorageClass performance tiers. Stateful workload patterns (StatefulSet + PVC anti-affinity). Database operators (CloudNativePG, Redis Operator) vs. bare VM. Nutanix Objects for unstructured data. CSI snapshots + Velero.

### 7. Networking architecture design
MetalLB L2 (lab) vs. BGP (production). Nutanix CCM vs. MetalLB. Ingress strategy: Traefik vs. NGINX vs. Gateway API. TLS termination: cert-manager + Let's Encrypt vs. internal CA. Service mesh decision (Istio/Linkerd on top of Cilium). Cilium ClusterMesh for cross-cluster service discovery.

### 8. Upgrade lifecycle
NKP version support lifecycle. K8s minor version upgrade via CAPI `RKE2ControlPlane` rolling update. Pre-upgrade checklist (API deprecations, add-on compatibility). Flux HelmRelease upgrades decoupled from cluster version. `nkp upgrade management-cluster`. OS image upgrade via `MachineDeployment` rolling update. Rollback limitations.

### 9. Multi-cluster observability
Thanos / Cortex for federated Prometheus (Kommander ships Thanos). Log aggregation: Fluentbit → Loki / Elastic / Splunk. Distributed tracing: OpenTelemetry Collector, Jaeger / Tempo. Alertmanager at fleet scale. DCGM metrics for GPU nodes. SLO/SLI design.

### 10. Cost management and chargeback
ResourceQuota and LimitRange per namespace. Kommander workspaces as cost boundaries. OpenCost / Kubecost for showback. Cluster autoscaling with CAPI (`ClusterAutoscaler` + `MachineDeployment`). KEDA for event-driven pod scaling (AI inference queues, message brokers).

### 11. Supply chain security
Cosign + Sigstore (image signing and admission verification). Kyverno (alternative to Gatekeeper for image policy). Harbor vulnerability scanning (Trivy, block CRITICAL CVEs). SBOM with Syft + Grype. CIS Benchmark for NKP (RKE2 CIS Level 1 — customer responsibility boundary). Pod Security Standards (Restricted / Baseline / Privileged).

---

## P3 — Hero-level depth

### 12. NC2 — Nutanix Cloud Clusters (hybrid cloud)
AHV on bare metal inside AWS / Azure. Use case: burst AI/ML to cloud H100 instances while keeping Management Cluster on-prem. Hybrid topology: on-prem Management Cluster + NC2 Workload Cluster in one Kommander fleet. Network path: Direct Connect / ExpressRoute.

### 13. Platform engineering patterns
GitOps-driven cluster provisioning (Cluster CRD in Git → CAPI creates cluster). Cluster-as-a-Service: self-service cluster requests via automation. Backstage integration: NKP clusters as catalog entities. Crossplane: provision Nutanix Objects / databases as K8s resources.

### 14. Certification roadmap
- **NCP-MCI** (Nutanix Certified Professional — Multicloud Infrastructure): AHV, AOS, Prism foundation
- **NCP-CN** (Nutanix Certified Professional — Cloud Native): NKP-specific exam
- **CKA / CKAD / CKS**: upstream K8s certs that complement NCP-CN
- Course-to-exam objective mapping
- Nutanix .NEXT Learning portal: free lab access and practice exams
