# playground — iximious Flexbox Playground Definition

This directory contains the iximious playground YAML for the NKP course labs.

## Files

| File | Purpose |
|---|---|
| [`playground.yaml`](playground.yaml) | 5-VM Flexbox playground — full NKP cluster topology |
| [`nkp-flexbox.yaml`](nkp-flexbox.yaml) | Identical copy (kept for reference) |

---

## Playground topology

```
172.16.0.0/24  (iximious local network)

bootstrap    172.16.0.10   2 vCPU / 2 Gi   Ubuntu 24.04   20 Gi disk
               └─ nkp CLI, kubectl, helm, flux, kind (bootstrap cluster)

controlplane 172.16.0.11   2 vCPU / 4 Gi   Rocky Linux 9.7   20 Gi disk
               └─ RKE2 server (kube-apiserver, etcd, controller-manager)

worker-01    172.16.0.12   2 vCPU / 2 Gi   Rocky Linux 9.7   20 Gi disk
worker-02    172.16.0.13   2 vCPU / 2 Gi   Rocky Linux 9.7   20 Gi disk
worker-03    172.16.0.14   2 vCPU / 2 Gi   Rocky Linux 9.7   20 Gi disk
               └─ RKE2 agent (kubelet, kube-proxy)

MetalLB pool: 172.16.0.100 – 172.16.0.120
```

### iximious platform limits (free tier)

| Resource | Limit | This playground |
|---|---|---|
| Total vCPU | 10 | 10 (2 × 5 VMs) |
| Total RAM | 16 GiB | 12 Gi |
| Total disk | 240 GiB | 100 Gi (20 Gi × 5 VMs) |

---

## Prerequisites before launching

1. **Build all three rootfs images** (see [`../rootfs/README.md`](../rootfs/README.md)):
   ```bash
   cd rootfs && make all
   ```

2. **Push the OCI rootfs images** to GHCR:
   ```bash
   cd rootfs && make push
   ```
   Images must be available at:
   - `ghcr.io/mercadoalex/nkp-bootstrap:latest`
   - `ghcr.io/mercadoalex/nkp-controlplane:latest`
   - `ghcr.io/mercadoalex/nkp-worker:latest`

3. **Create the playground** with `labctl`:
   ```bash
   cd ~/Desktop/nkp_demo
   labctl playground create -f playground/playground.yaml -b flexbox nkp-lab
   ```
   The `name:` field in the manifest (`nkp-lab`) must match the `<local-name>` argument exactly.

   **Published playground:** https://labs.iximiuz.com/playgrounds/nkp-lab-b2fa17d3

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
