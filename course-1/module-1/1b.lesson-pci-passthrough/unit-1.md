---
kind: unit
title: "What is PCI Passthrough?"
name: lesson-pci-passthrough-unit-1
---

::remark-box
This is a **concept-only lesson** — no lab, no terminal. You can read it in under 5 minutes. It exists because "passthrough" appears in two critical places in NKP: inside the Nutanix CVM (storage performance) and inside NKP node VMs (GPU access). Once you understand the idea, both uses make immediate sense.
::

## The problem passthrough solves

When a virtual machine needs to use a hardware device — a disk, a GPU, a network card — the standard approach is **emulation**: the hypervisor intercepts the VM's hardware requests and translates them into real hardware operations.

```
Standard virtualised I/O:

VM requests disk write
  → hypervisor intercepts
  → translates to real disk operation
  → disk writes data
  → result passed back through hypervisor to VM
```

This works, but the hypervisor is in the middle of every single I/O operation. That translation adds latency and CPU overhead. For most workloads it's invisible. For storage-intensive databases or GPU-accelerated AI training, it matters enormously.

**PCI passthrough** eliminates the hypervisor from the I/O path entirely.

---

## The core idea — direct assignment

**PCI passthrough** (also called *PCIe passthrough* or *device passthrough*) is a technique where the hypervisor assigns a physical PCIe device **directly and exclusively** to one VM. The VM owns that device as if it were physically plugged into the VM's own motherboard.

```
Without passthrough (emulation):
  Physical GPU → [hypervisor translates] → VM sees a virtual GPU
  (like a translator between two people — functional but slower)

With passthrough:
  Physical GPU → [assigned directly] → VM sees the REAL GPU
  (like handing the card to the person directly — no translation)
```

Once assigned, the VM has **bare-metal access** to the device:
- No hypervisor software in the I/O path
- Native device drivers run inside the VM
- Full device performance — same as if the VM were a physical machine

---

## What makes passthrough possible — VT-d and IOMMU

PCI passthrough requires two hardware features working together:

| Feature | What it is | What it does |
|---|---|---|
| **VT-d** (Intel) / **AMD-Vi** (AMD) | CPU virtualisation extension | Allows the CPU to route DMA (Direct Memory Access) requests from a PCIe device directly to a VM's memory address space |
| **IOMMU** (Input-Output Memory Management Unit) | Chipset component | Acts as an MMU for PCIe devices — translates device memory addresses and enforces isolation so the passed-through device can only access its assigned VM's memory |

Together, VT-d + IOMMU create a **hardware-enforced isolation boundary**: the passed-through device can talk directly to its VM's memory, and nothing else. This is what makes it safe to give a VM exclusive ownership of a physical device.

To use passthrough on Nutanix AHV, VT-d must be enabled in the server BIOS (it usually is on Nutanix hardware from the factory).

---

## Two places passthrough appears in NKP

### 1. Disk passthrough to the CVM (always on, transparent)

Every Nutanix node uses passthrough to give the **CVM exclusive ownership of the physical disk controllers** (NVMe SSDs, HDDs). This is always enabled — you never configure it yourself.

```
NVMe SSD
  → [VT-d / IOMMU]
  → CVM owns the SSD directly
  → AOS (Stargate) reads/writes at bare-metal speed (~10–20 µs latency)
```

This is what Josh Odgers called **"DirectPath I/O"** — it's why Nutanix achieves bare-metal storage latency despite running storage inside a VM. Without passthrough, every disk I/O would pass through the AHV hypervisor, adding 50–200 µs of overhead per operation.

### 2. GPU passthrough to NKP worker VMs (configured per VM)

When you add a GPU node to an NKP cluster, you configure Prism Central to pass the **physical NVIDIA GPU directly to the NKP worker VM**. The worker VM then sees a real GPU, installs real NVIDIA drivers, and the NVIDIA GPU Operator manages it from Kubernetes.

```
NVIDIA H100 (physical card in the server)
  → [VT-d / IOMMU]
  → NKP worker VM owns the GPU directly
  → NVIDIA driver runs inside Rocky Linux 9.7
  → GPU Operator exposes it as nvidia.com/gpu resource
  → Pods schedule onto it
```

This is covered in full detail in [Module 7 — GPU Support on NKP](../../module-7/1.lesson-gpu/unit-1.md).

---

## Passthrough vs. vGPU — quick comparison

Passthrough gives one VM the entire physical GPU. That's great for performance — but wasteful if the workload doesn't use the whole card.

| Mode | What it does | Best for |
|---|---|---|
| **PCIe passthrough** | Entire physical GPU → one VM | Training jobs that need all VRAM (full fine-tuning) |
| **NVIDIA vGPU** | GPU partitioned into virtual GPUs via software | Multiple VMs sharing one card (inference, desktop AI) |
| **MIG** (Multi-Instance GPU) | GPU partitioned into isolated hardware slices | Hard isolation between tenants, mixed workload sizes |
| **Time-slicing** | GPU shared via time-multiplexing | Dev/test environments, many small jobs |

MIG and time-slicing are configured through the **NVIDIA GPU Operator** inside Kubernetes — not at the hypervisor level. They are explained in [Module 7 — GPU Operator, Time-Slicing, and MIG](../../module-7/1.lesson-gpu/unit-2.md).

---

## Summary

- **Passthrough** = hypervisor assigns a physical PCIe device directly to one VM, bypassing emulation
- **VT-d + IOMMU** = the CPU/chipset hardware that makes passthrough safe and fast
- **In Nutanix**: disk passthrough to CVM gives AOS bare-metal storage performance — always on, transparent
- **In NKP**: GPU passthrough to worker VMs gives pods bare-metal GPU access — configured in Prism Central

> Module 7 covers the full GPU passthrough configuration in Prism Central, vGPU vs. passthrough tradeoffs, and the NVIDIA GPU Operator setup inside NKP.
