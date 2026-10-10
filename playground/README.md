# playground — iximious Flexbox Playground Definition

This directory contains the iximious playground YAML for the NKP course labs.

## Files

| File | Purpose |
|---|---|
| [`nkp-flexbox.yaml`](nkp-flexbox.yaml) | 5-VM Flexbox playground — full NKP cluster topology |

---

## Playground topology

```
172.16.0.0/24  (iximious local network)

bootstrap    172.16.0.10   4 vCPU / 4 GB   Ubuntu 24.04
               └─ nkp CLI, kubectl, helm, flux, kind (bootstrap cluster)

controlplane 172.16.0.11   4 vCPU / 8 GB   Rocky Linux 9.7
               └─ RKE2 server (kube-apiserver, etcd, controller-manager)

worker-01    172.16.0.12   4 vCPU / 8 GB   Rocky Linux 9.7
worker-02    172.16.0.13   4 vCPU / 8 GB   Rocky Linux 9.7
worker-03    172.16.0.14   4 vCPU / 8 GB   Rocky Linux 9.7
               └─ RKE2 agent (kubelet, kube-proxy)

MetalLB pool: 172.16.0.100 – 172.16.0.120
```

---

## Prerequisites before launching

1. **Build all three rootfs images** (see [`../rootfs/README.md`](../rootfs/README.md)):
   ```bash
   cd rootfs && make all
   ```

2. **Register the custom rootfs images** with your iximious account.  
   Upload `dist/nkp-bootstrap.ext4`, `dist/nkp-controlplane.ext4`, and `dist/nkp-worker.ext4`  
   via the iximious Labs dashboard → Custom Images.  
   The `source` names in `nkp-flexbox.yaml` must match the names you register:
   - `nkp-bootstrap`
   - `nkp-controlplane`
   - `nkp-worker`

3. **Register the playground** with your iximious account:
   ```bash
   iximiuz-labs playground publish --file playground/nkp-flexbox.yaml
   ```
   *(exact CLI command may differ — check iximious Labs documentation)*

---

## IP address reference

| Machine | IP | Role |
|---|---|---|
| `bootstrap` | `172.16.0.10` | Operator workstation, kind bootstrap cluster |
| `controlplane` | `172.16.0.11` | RKE2 API server (port 6443), CAPI pivot target |
| `worker-01` | `172.16.0.12` | RKE2 agent |
| `worker-02` | `172.16.0.13` | RKE2 agent |
| `worker-03` | `172.16.0.14` | RKE2 agent |
| MetalLB pool | `172.16.0.100–120` | LoadBalancer service VIPs |

---

## Lessons that use this playground

| Lesson | Machines used |
|---|---|
| 06 — Bootstrap & Pivot | all 5 |
| 07 — Node operations | all 5 |
| 08 — Add-ons catalog | all 5 |
| 09 — GitOps with Flux | all 5 |
| 10 — RBAC & Policy | all 5 |
| 11 — Monitoring | all 5 |
| 12 — Node failure | all 5 |

Tier 2 lessons (04, 05) use only the `bootstrap` machine — launch a single-VM playground
using the `nkp-bootstrap` source directly instead of this 5-VM definition.
