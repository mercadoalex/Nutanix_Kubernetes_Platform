---
kind: unit
title: "PCI Passthrough Deep Dive: Giving NKP Bare-Metal GPU Access"
name: lesson-passthrough-deep-unit-1
---

> 📖 **Prerequisites:** Read [Lesson 1b — What is PCI Passthrough?](../../module-1/1b.lesson-pci-passthrough/unit-1.md) for the conceptual foundation. This lesson assumes you understand what passthrough is — it goes deeper into the hardware mechanism and the Prism Central configuration.

> 📺 **Demo only** — GPU passthrough configuration requires physical Nutanix hardware with NVIDIA GPUs installed. The Prism Central steps in this lesson cannot be performed in the Flexbox playground. The GPU Operator setup that follows passthrough is interactive — see [GPU Support Part 2](../1.lesson-gpu/unit-2.md).

---

## The two uses of passthrough in Nutanix — a quick recap

| Use case | What's passed through | To what | Always on? |
|---|---|---|---|
| **Disk → CVM** | NVMe/SSD/HDD controllers via VT-d | CVM (Controller VM) | ✅ Yes — always, on every node, configured at factory |
| **GPU → NKP worker VM** | NVIDIA PCIe GPU via VT-d | NKP worker VM | ❌ No — operator configures per VM in Prism Central |

This lesson focuses on **GPU passthrough to NKP worker VMs** — the part you configure.

---

## VT-d and IOMMU — the hardware mechanism in depth

### The memory isolation problem

When a physical device (a GPU) issues a DMA (Direct Memory Access) request, it can write to any physical memory address on the system. Without isolation, a VM that owns a physical GPU could — in theory — use it to overwrite memory belonging to other VMs or the hypervisor.

**IOMMU** (Input-Output Memory Management Unit) solves this by acting as a translation layer between the PCIe bus and physical memory:

```
Without IOMMU:
  GPU DMA request → physical memory address (any address)
  (dangerous — GPU can access anything)

With IOMMU:
  GPU DMA request → IOMMU translates → VM's physical memory (isolated region only)
  (safe — GPU can only access memory belonging to its assigned VM)
```

The IOMMU maintains per-device address translation tables, similar to how the CPU's MMU manages virtual-to-physical memory translations for processes.

### VT-d (Intel) / AMD-Vi (AMD)

**VT-d (Virtualization Technology for Directed I/O)** is Intel's implementation of hardware-assisted I/O virtualisation. AMD's equivalent is **AMD-Vi** (also called IOMMU on AMD platforms). They serve the same function: expose the IOMMU capability to the hypervisor software.

When AHV (or any KVM hypervisor) wants to pass a PCIe device through to a VM:

1. AHV asks the kernel to create an **IOMMU domain** for the device
2. The IOMMU maps the device's DMA range to the VM's physical memory pages
3. The PCIe device is **detached from the host kernel** (VFIO driver takes over)
4. The VM gets direct PCIe access — the device sees the VM as if it were a physical machine

```
Physical H100 GPU
  │
  └── PCIe bus
       │
       └── IOMMU domain (VT-d)
            │    maps: GPU DMA addresses → VM #3 physical memory pages
            │    blocks: GPU DMA to any other VM or hypervisor memory
            │
            └── NKP Worker VM #3
                 └── NVIDIA kernel driver runs inside Rocky Linux 9.7
                      └── Full bare-metal GPU performance
```

### Why this achieves bare-metal performance

With passthrough, the GPU talks **directly to the VM's memory** through the IOMMU. The hypervisor (AHV) is not in the data path at all:

```
Standard virtualised GPU (emulation):
  VM issues GPU command
    → hypervisor intercepts
    → translates to real GPU command
    → result passed back through hypervisor
    → VM receives result
  (adds 100–500 µs of software overhead per operation)

GPU passthrough (VT-d):
  VM issues GPU command
    → GPU executes directly
    → result written to VM memory via IOMMU
  (bare-metal latency — same as a physical machine)
```

This is why NVIDIA quotes training benchmarks from DGX systems: those numbers are from physical machines with no hypervisor overhead. With passthrough to AHV VMs, NKP achieves the same performance — or within 1–3% (IOMMU translation overhead is negligible on modern CPUs).

### Josh Odgers — DirectPath I/O

Josh Odgers documented the same mechanism for **disk passthrough to the CVM** as "DirectPath I/O" — the same VT-d/IOMMU path that gives the CVM bare-metal storage performance is also what gives NKP worker VMs bare-metal GPU performance.

> 📖 Reference: [joshodgers.com — Nutanix CVM DirectPath I/O deep dive](https://joshodgers.com)

---

## IOMMU groups — the physical grouping constraint

PCIe devices are not individually isolated — they are grouped into **IOMMU groups** by the PCIe topology. All devices in the same IOMMU group must be passed through to the same VM together.

On Nutanix NX hardware, each GPU is typically in its own IOMMU group (because each GPU is on a dedicated PCIe slot with no peer devices sharing the bridge). This means you can assign individual GPUs to individual VMs.

If a GPU shares an IOMMU group with another device (e.g. its audio function on consumer GPUs), both must be passed through together. Enterprise GPU cards (H100, A100, L40S) do not have this issue.

```bash
# On an AHV host — list IOMMU groups (for reference only, don't run in lab)
find /sys/kernel/iommu_groups/ -type l | sort -V

# Each directory under /sys/kernel/iommu_groups/ is one group
# Each symlink inside is one PCIe device in that group
```

---

## Configuring GPU passthrough in Prism Central

> 📺 The following steps require a real AHV cluster with NVIDIA GPUs. They are shown as a walkthrough — observe the screenshots and steps; you cannot perform them in the Flexbox playground.

### Prerequisites

Before configuring passthrough on a VM:

1. **GPU must be physically installed** in the AHV host server
2. **NVIDIA driver must NOT be installed on the AHV host** — passthrough hands the device to the VM, not to the hypervisor. If an NVIDIA driver is running on the AHV host, the GPU cannot be passed through.
3. **VT-d / IOMMU must be enabled** in the server BIOS (Nutanix NX hardware has this enabled from factory)
4. **NKP Pro or higher** required — GPU node pools are not available in NKP Starter

### Step 1 — Verify GPU visibility in Prism Central

1. Prism Central → **Infrastructure** → **Hosts**
2. Click on the host that has the GPU installed
3. Scroll to **GPU** section — the GPU should appear in the list
4. Status should be **"Unused"** (not assigned to any VM)

If the GPU does not appear, it may be in use by the AHV host OS. Check `/proc/driver/nvidia/gpus/` on the AHV host — if that path exists, the host driver is loaded and passthrough is blocked.

### Step 2 — Power off the target NKP worker VM

Passthrough requires **cold assignment** — the VM must be powered off. Hot-plug is not supported for PCIe passthrough (it requires the OS to rebind the device, which AHV does not support mid-run).

1. In NKP, drain the worker node first to safely evict pods:
   ```bash
   kubectl drain worker-03 --ignore-daemonsets --delete-emptydir-data
   ```
2. In Prism Central → **Virtual Infrastructure** → **VMs** → select the worker VM
3. **Power Off** (not suspend)

### Step 3 — Assign the GPU in Prism Central

1. VM is powered off → click **Update**
2. Scroll to the **GPU** section → **+ Add GPU**
3. Set **Type** to **Passthrough** (not Virtual GPU)
4. Select the GPU device from the list (e.g. `NVIDIA H100 80GB PCIe`)
5. **Save**

> **CPU Pinning and NUMA alignment:** Enable these for GPU VMs to avoid cross-NUMA latency. VM → Update → **CPU Pinning** → Enable. This pins the VM's vCPUs to the NUMA node that the GPU is physically attached to, minimising PCIe bus latency between CPU and GPU memory.

### Step 4 — Power on and verify

1. Power on the VM in Prism Central
2. SSH into the worker node:
   ```bash
   ssh laborant@<worker-vm-ip>
   
   # Verify the GPU is visible inside the VM
   lspci | grep -i nvidia
   # Expected: 00:05.0 3D controller: NVIDIA Corporation H100 PCIe [10de:2331]
   
   # After GPU Operator installs the driver:
   nvidia-smi
   # Expected: GPU name, driver version, CUDA version, memory
   ```
3. Uncordon the node in Kubernetes:
   ```bash
   kubectl uncordon worker-03
   ```

### Step 5 — Remove the GPU assignment (when needed)

To move the GPU to a different VM or decommission a node:

1. Power off the worker VM (drain pods first)
2. VM → Update → GPU section → remove the GPU assignment
3. GPU status returns to "Unused"

---

## PCIe passthrough vs. NVIDIA vGPU — the decision

| | PCIe Passthrough | NVIDIA vGPU |
|---|---|---|
| **How it works** | Entire physical GPU → one VM | GPU partitioned via NVIDIA software into multiple vGPUs |
| **Performance** | Bare-metal (identical to physical) | 95–99% of bare-metal (small driver overhead) |
| **Memory isolation** | Full GPU VRAM exclusively to one VM | Framebuffer divided per vGPU profile |
| **NVIDIA license** | ❌ Not required | ✅ Required (vGPU software license per GPU) |
| **Live migration** | ❌ Not supported (PCIe devices can't be live-migrated) | ✅ Supported (AOS 6.7+, PC 2023.3+) |
| **VM count per GPU** | 1 VM per GPU | Multiple VMs per GPU (depends on profile) |
| **Best for** | Training jobs (all VRAM needed) | Inference, multi-tenant environments |
| **NKP workload** | Training pods (`nvidia.com/gpu: 1`) | Inference pods with MIG or vGPU profiles |

**Rule of thumb for NKP:**
- **Training jobs** (full fine-tuning, QLoRA) → PCIe passthrough (whole GPU, max VRAM)
- **Inference / shared access** → vGPU or MIG time-slicing (one GPU shared across pods)

---

## Full passthrough flow — from physical GPU to Kubernetes pod

```
Physical NVIDIA H100 (in AHV host server)
  │
  └── VT-d / IOMMU group
       │
       └── Prism Central assigns GPU to NKP Worker VM #3
            │
            └── AHV powers on Worker VM #3
                 │
                 └── Rocky Linux 9.7 boots
                      │
                      └── NVIDIA kernel module loads (GPU Operator Driver DaemonSet)
                           │
                           └── nvidia-container-runtime injected (Container Toolkit DS)
                                │
                                └── nvidia.com/gpu: 1 registered (Device Plugin DS)
                                     │
                                     └── Pod scheduled with nvidia.com/gpu: 1
                                          │
                                          └── Container gets /dev/nvidia0
                                               └── CUDA workload runs at bare-metal speed
```

Every step after "Prism Central assigns GPU" is handled automatically by the NVIDIA GPU Operator — you only configure the Prism Central step manually.

---

## Check your understanding

1. What does the IOMMU translate and why is that translation necessary for safe passthrough?
2. Why must a VM be powered off before you can assign a GPU via PCIe passthrough in AHV?
3. What is an IOMMU group and why does it constrain which devices can be passed through together?
4. What happens if the NVIDIA driver is already loaded on the AHV host OS when you try to configure passthrough?
5. In which scenario would you choose vGPU over passthrough for an NKP workload?
6. What is CPU pinning and why does it matter for GPU VMs?

Answers are in the lesson above.
