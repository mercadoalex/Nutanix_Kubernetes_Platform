---
kind: unit
title: "Lesson 00b — Nutanix Community Edition 2.1"
name: 2-lesson-community-edition-unit-1
---

# Lesson 00b — Nutanix Community Edition 2.1

> **Tier:** Walkthrough — requires physical x86 hardware (no playground needed)  
> **Purpose:** Install a real Nutanix AHV cluster at home so you have genuine infrastructure to run NKP against. CE is free, no license required.

---

## What is Community Edition?

Nutanix Community Edition (CE) is a free, fully functional version of the Nutanix stack — the same AOS and AHV binaries that ship in commercial products — packaged for installation on commodity x86 hardware. It is the standard way to run a Nutanix home lab.

**CE 2.1 key facts:**

| Item | Detail |
|---|---|
| Bundled AOS | 6.8.1 |
| AHV build | Identical to commercial AOS — LCM upgrades work directly |
| Prism Central | Compatible with the commercial PC build (deploy separately) |
| License | Free, no registration wall for the base install |
| Upgrade path from older CE | ❌ None — fresh install only |

> ⚠️ **Critical for NKP 2.17:** CE 2.1 ships AOS 6.8.1. NKP 2.17 requires **AOS 7.3 minimum**. You must upgrade via LCM after installation. See [Part C — LCM Upgrade](#part-c--lcm-upgrade-to-aos-73) below.

> ⚠️ **Do not register a CE cluster with a Prism Central that is already managing commercial licensed clusters.** Keep CE and production PC separate.

---

## Part A — Hardware requirements

CE runs on standard x86_64 servers or repurposed workstations. Jeroen Tielen's blog post proves even an **NX-3060-G4 (Ivy Bridge, ~2013)** handles the full NKP stack.

| Component | Minimum | Recommended for NKP |
|---|---|---|
| CPU | Intel Nehalem+ or AMD Bulldozer+ (x86_64, VT-x/AMD-V) | 8+ cores per node |
| RAM | 32 GB per node | 64 GB per node |
| Boot drive | 1× SSD ≥ 32 GB (for AHV hypervisor) | 1× SSD ≥ 64 GB |
| Data drives | 1× HDD/SSD ≥ 200 GB (for CVM + storage) | 2–4 drives per node |
| Network | 1 GbE | 10 GbE (1 GbE works for lab) |
| Nodes | 1 (single-node cluster) | 3 (for HA and realistic NKP topology) |

> **Single-node CE** works for basic NKP experiments but has no HA. A 3-node cluster is the minimum for meaningful NKP workload cluster topology.

---

## Part B — Create the bootable USB and install

### Downloads

| File | URL | MD5 |
|---|---|---|
| **CE 2.1 Installer ISO** | `https://download.nutanix.com/ce/2024.08.19/phoenix.x86_64-fnd_5.6.1_patch-aos_6.8.1_ga.iso` | `0e7c800b46986c84d4fcdae92e73dc53` |
| VirtIO drivers (Windows x64) | `https://download.nutanix.com/virtIO/1.2.5/Nutanix-VirtIO-1.2.5-x64.msi` | `ab722a4c1542054bc346fd7598eed732` |
| VirtIO drivers (ISO) | `https://download.nutanix.com/virtIO/1.2.5/Nutanix-VirtIO-1.2.5.iso` | `be064da69ee73f14e368c7ca879f5fa1` |

> The **OSS disclosure `.tar`** at `https://download.nutanix.com/ce/2024.08.19/oss_disclosures_ce-2.1.tar` is the open-source code disclosure archive, **not** the installer. You do not need to download it.

### Create the USB stick (Windows)

> ⚠️ **You MUST use Rufus v3.21 exactly.** Other versions (including newer ones) produce a USB that fails to boot or fails during installation. Download Rufus 3.21 from [github.com/pbatard/rufus/releases/tag/v3.21](https://github.com/pbatard/rufus/releases/tag/v3.21).

1. Insert a USB drive ≥ 8 GB (all data will be erased)
2. Open **Rufus v3.21**
3. **Device:** select your USB drive
4. **Boot selection:** click **SELECT** → choose the CE 2.1 `.iso`
5. **Partition scheme:** MBR
6. **Target system:** BIOS or UEFI
7. Click **START** → accept the ISO mode prompt → wait for completion

### Create the USB stick (Linux/macOS)

```bash
# Identify your USB device (e.g. /dev/sdb or /dev/disk2)
lsblk          # Linux
diskutil list  # macOS

# Write the ISO directly (replace /dev/sdX with your device — NOT a partition)
sudo dd if=phoenix.x86_64-fnd_5.6.1_patch-aos_6.8.1_ga.iso \
        of=/dev/sdX \
        bs=4M \
        status=progress \
        conv=fsync
```

### BIOS configuration

Before booting from USB, configure each node's BIOS:
- Enable **Intel VT-x** (or AMD-V) and **VT-d** (IOMMU)
- Set boot order: USB first
- Disable **Secure Boot**
- Set **SATA mode** to AHCI (not RAID)

### Installation steps

1. Boot the node from the USB — the Nutanix CE installer (Phoenix) starts automatically
2. Select the target disk for AHV (the hypervisor install drive — smallest SSD recommended)
3. Assign IP addresses when prompted:
   - **IPMI IP** — out-of-band management
   - **AHV host IP** — the hypervisor
   - **CVM IP** — the Controller VM (runs AOS)
4. Complete the installation — the node reboots into AHV
5. Repeat for each node

### Network layout reference (from Jeroen Tielen's home lab)

```
Node 1:  IPMI 10.0.2.1   AHV 10.0.2.11   CVM 10.0.2.21
Node 2:  IPMI 10.0.2.2   AHV 10.0.2.12   CVM 10.0.2.22
Node 3:  IPMI 10.0.2.3   AHV 10.0.2.13   CVM 10.0.2.23

Cluster Virtual IP:        10.0.2.30
Cluster Data Services IP:  10.0.2.31
Prism Central IP:          10.0.2.32
```

Use a `/24` subnet with a DHCP server that has a reserved range for NKP VIPs (outside DHCP scope):
- **Control Plane VIP** (NKP API server) — e.g. `10.0.2.50`
- **MetalLB / LB pool** — e.g. `10.0.2.51–10.0.2.60`

---

## Part B2 — Create the cluster in Prism Element

After all nodes are installed and CVMs are up:

1. Open a browser to any **CVM IP** on port 9440: `https://10.0.2.21:9440`
2. Log in with `admin` / `nutanix/4u` (default — change immediately)
3. Follow the **cluster creation wizard**:
   - Enter all CVM IPs
   - Set the **Cluster Virtual IP** and **Data Services IP**
   - Name your cluster
4. Accept defaults for storage pool and container

After cluster creation, apply your default configurations (NTP, DNS, SMTP if desired).

---

## Part C — LCM Upgrade to AOS 7.3

CE 2.1 ships AOS **6.8.1**. NKP 2.17 requires AOS **7.3** minimum. You must upgrade via **Life Cycle Manager (LCM)** — the same tool used in commercial clusters.

> ✅ CE 2.1's major improvement is that AOS and AHV are now on the **same build track as commercial versions**, so LCM upgrades work directly without waiting for CE-specific releases.

### Upload upgrade bundles via Prism Element

1. Go to [portal.nutanix.com](https://portal.nutanix.com) → **Downloads** → **AOS** → download AOS 7.3 (`.tar.gz`)
2. Also download the matching AHV upgrade bundle
3. In Prism Element: **LCM** (Life Cycle Manager) → **Settings** → **Dark Site** (if no internet) OR let LCM pull directly if internet-connected
4. **Prism Element** → top menu → **Upgrade Software** → upload the AOS bundle
5. Run the upgrade — CVMs rolling-restart, AHV upgrades node by node

### LCM upgrade order (always follow this sequence)

```
1. AHV upgrade       (hypervisor — nodes reboot one at a time)
2. AOS upgrade       (CVM software — rolling restart)
3. Prism Central     (deploy or upgrade separately)
```

> Never upgrade AOS before AHV if they need to match.

### Verify versions after upgrade

```bash
# SSH into any CVM
ssh nutanix@10.0.2.21

# Check AOS version
ncli cluster version

# Check AHV version on each host
hostssh "uname -r && cat /etc/nutanix/ahv-version"
```

Target state before proceeding to NKP:
- AOS: **7.3.x**
- AHV: **matching 7.3.x build**
- Prism Central: **pc.7.3.x**

---

## Part D — Deploy Prism Central

NKP requires Prism Central (PC). CE is **compatible with the commercial PC build** — download and deploy it the same way as in a production environment.

1. Go to [portal.nutanix.com](https://portal.nutanix.com) → **Downloads** → **Prism Central** → download PC 7.3 (`.tar`)
2. In Prism Element: **Prism Central** → **Deploy Prism Central**
3. Select the downloaded bundle
4. Assign the PC IP (`10.0.2.32` in the example above), vCPUs (4 min), RAM (16 GB min)
5. Wait for deployment — PC boots as a VM on AHV
6. Open `https://10.0.2.32:9440` → complete the PC setup wizard
7. Register the CE cluster with PC: in Prism Element → **Prism Central** → **Register**

> Jeroen Tielen used **PC 2024.2** on his G4 lab. For NKP 2.17 you need **pc.7.3** minimum.

---

## Part E — Install VirtIO drivers (for Windows VMs)

If you plan to run Windows VMs alongside NKP on the same cluster, attach the VirtIO ISO when creating Windows VMs — AHV uses paravirtualised disk and network devices that require the VirtIO driver.

```
VirtIO x64 installer: https://download.nutanix.com/virtIO/1.2.5/Nutanix-VirtIO-1.2.5-x64.msi
VirtIO ISO (for install media): https://download.nutanix.com/virtIO/1.2.5/Nutanix-VirtIO-1.2.5.iso
```

Upload the ISO to Prism Central → **Images** → Add Image → type **ISO**.  
Detailed steps: [Slipstream VirtIO into a Windows ISO](https://www.jeroentielen.nl/slipstream-virtio-drivers-into-windows-iso-to-use-on-nutanix-ahv/)

---

## Summary checklist

Before proceeding to [Lesson 01 — Getting the NKP OS Image](../3.lesson-os-image/unit-1.md), confirm:

- [ ] CE 2.1 installed on all nodes
- [ ] Cluster created in Prism Element with Virtual IP and Data Services IP assigned
- [ ] AOS upgraded to **7.3.x** via LCM
- [ ] AHV upgraded to matching **7.3.x** build via LCM
- [ ] Prism Central **pc.7.3.x** deployed and cluster registered
- [ ] Network has reserved IPs outside DHCP scope for NKP VIPs

---

## Next steps

➡️ [Lesson 01 — Getting the NKP OS Image](../3.lesson-os-image/unit-1.md)
