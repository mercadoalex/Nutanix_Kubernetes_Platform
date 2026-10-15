---
kind: unit
title: "GPU Support on NKP — Part 1: AHV GPU Hardware"
name: 1-lesson-gpu-unit-1
---

# GPU Support on NKP — Part 1: AHV GPU Hardware

> **Tier:** Mixed
> **This unit — AHV GPU assignment:** 📺 Walkthrough (requires real Nutanix hardware)
> **Next unit — GPU Operator + lab simulation:** 💻 Interactive (Flexbox 5-VM playground)
> **Playground:** `nkp-flexbox` (vm1 = bootstrap, vm2–vm5 = cluster)

---

## What you will learn

- Which NKP edition supports GPU workloads (and which doesn't)
- Which GPU vendors AHV supports — and which it doesn't
- How to assign a physical NVIDIA GPU to a VM on Nutanix AHV (passthrough and vGPU)
- How to build a heterogeneous AHV cluster with mixed CPU-only and GPU nodes
- AOS and Prism Central version requirements for GPU support

---

::remark-box
**NKP Pro or higher required.** GPU support is not available in NKP Starter. You must have an NKP Pro or NKP Ultimate license to use GPU-enabled node pools and the NVIDIA GPU Operator catalog add-on.
::

::remark-box
**NVIDIA GPUs only on AHV.** Nutanix AHV supports GPU passthrough and vGPU exclusively for **NVIDIA** hardware. AMD GPUs (Radeon Pro, Instinct MI series) are not supported for GPU passthrough or vGPU on AHV. GPU-enabled in the Nutanix vocabulary means NVIDIA.

Compatibility is verified in the [Nutanix NVIDIA Compatibility Matrix](https://portal.nutanix.com/page/documents/compatibility-details/list) — cross-references AOS version × AHV version × GPU card × NVIDIA driver version.
::

> 📖 **New to PCI passthrough?** Before reading this unit, see [Lesson 1b — What is PCI Passthrough?](../../module-1/1b.lesson-pci-passthrough/unit-1.md) for a ground-up explanation of the concept. This unit assumes you understand what passthrough means.

---

## Version reference

| Component | Version used |
|---|---|
| NKP | 2.17 |
| NVIDIA GPU Operator | v24.9.1 |
| CUDA base image | 12.4.0-base-ubuntu22.04 |
| RKE2 (cluster runtime) | v1.34.3+rke2r1 |

---

## Heterogeneous AHV cluster topology

A production AHV cluster does not need every node to have a GPU. You mix CPU-only nodes and GPU nodes in the same cluster — NKP schedules GPU workloads to nodes that have GPUs, and everything else to CPU-only nodes.

```
Nutanix AHV Cluster (example: 8 nodes)
│
├── Nodes 1–4:  CPU-only          (NX-8155)
│    └── NKP control plane + general workloads
│
├── Nodes 5–6:  NVIDIA H100 80GB  (NX-9151-G9, 4× H100 per node)
│    └── AI/ML training jobs
│
└── Nodes 7–8:  NVIDIA L40S 48GB  (NX-9151-G9 variant, 4× L40S per node)
     └── Inference / vGPU workloads
```

In NKP, you create separate **node pools** for GPU and CPU nodes. The GPU Operator only runs on nodes that have GPUs (via node selectors/tolerations). The `nvidia.com/gpu` resource is only registered on GPU nodes.

> **AHV ceiling:** The maximum GPU count per AHV node is **4 GPUs** (NX-9151-G9 or equivalent). For training jobs requiring more than 4 GPUs, you need either multi-node training (2+ GPU nodes connected via 200 Gbps fabric) or NKP Metal (bare-metal nodes that support 8 GPUs via NVLink/NVSwitch, e.g. DGX H100). This is covered in detail in [Lesson 7-3 — Sizing NKP for AI/ML](../3.lesson-ai-sizing/unit-1.md).

---

## Part A — Adding a GPU to a Nutanix AHV VM

> 📺 **Demo only** — requires Prism Central with physical GPU hardware installed in the AHV host.

NKP worker VMs are standard AHV VMs. Before the GPU Operator can see a GPU, the physical device must be assigned to the VM at the hypervisor level. AHV supports two modes:

### PCIe Passthrough (dedicated GPU per VM)

The entire physical GPU is reserved for one VM. No NVIDIA licensing required.

1. **Power off** the target VM in Prism Central (passthrough requires cold assignment — hot-plug is not supported)
2. Prism Central → **Virtual Infrastructure** → **VMs** → select the VM → **Update**
3. Scroll to the **GPU** section → **+ Add GPU**
4. Set type to **Passthrough**
5. Select the GPU device (e.g. `NVIDIA A100 80GB PCIe`)
6. **Save** → **Power On**

> ⚠️ Enable **CPU Pinning** and **NUMA alignment** on the VM to avoid cross-NUMA GPU-to-CPU memory latency: VM → Update → **CPU Pinning** → Enable.

### NVIDIA vGPU (shared GPU across multiple VMs)

One physical GPU is time-sliced at the hypervisor level into multiple vGPU instances, each VM gets a slice with dedicated framebuffer. Requires an **NVIDIA vGPU software license**.

1. Same path: VM → Update → GPU → **+ Add GPU** → type = **Virtual GPU (vGPU)**
2. Select a **compute profile** — for Kubernetes/AI workloads use `C` suffix profiles:
   - `A100-40C` — 40 GB framebuffer, full compute
   - `A10-4C` — 4 GB, suits smaller inference workloads
   - `A16-4C` — cost-effective, 4× A16 cards per GPU board

**AHV vGPU profile suffix guide:**

| Suffix | Type | Use case |
|---|---|---|
| `-xC` | Compute (vCS) | ML training, inference — **use this for NKP** |
| `-xQ` | Quadro Virtual Workstation | Pro graphics + compute |
| `-xA` | Virtual Application | Lightweight VDI |
| `-xB` | Virtual PC | Standard VDI desktops |

### AOS / Prism Central version requirements

| Feature | AOS min | PC min |
|---|---|---|
| PCIe passthrough | 5.15 | pc.2022.1 |
| NVIDIA vGPU | 6.5 | pc.2022.6 |
| vGPU live migration | 6.7 | pc.2023.3 |
| NKP 2.17 full support | **7.3** | **pc.7.3** |

---

> ➡️ **Continue to [GPU Support — Part 2: GPU Operator, Time-Slicing, MIG, and Lab](unit-2.md)** for the hands-on GPU Operator installation, time-slicing, MIG configuration, and the no-hardware lab simulation.

