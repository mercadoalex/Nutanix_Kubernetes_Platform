---
kind: unit
title: "Lesson 01 — Getting the NKP OS Image"
name: 3-lesson-os-image-unit-1
---

# Lesson 01 — Getting the NKP OS Image

> **Objective:** Download the correct NKP Rocky Linux node image from the Nutanix Support Portal and upload it to Prism Central so that NKP can use it when provisioning cluster nodes.

---

## Version Reference

| NKP Version | K8s Version | Rocky Image |
|-------------|-------------|-------------|
| 2.17        | 1.34.x      | Rocky 9.7   |
| 2.16        | 1.33.x      | Rocky 9.6   |
| 2.15        | 1.32.x      | Rocky 9.5   |

> ⚠️ **Always download the OS image that matches your NKP CLI version.** Mixing versions causes bootstrap failures.

---

## Why a custom image?

NKP does **not** use a stock Rocky Linux ISO. The image from the Nutanix Support Portal is a pre-built, **CIS Level 1 hardened** cloud image with everything a node needs already baked in:

- `kubeadm`, `kubelet`, `containerd`
- CNI/CSI prerequisites
- All NKP-specific kernel and OS configurations

This means zero post-boot provisioning of the OS layer — the image is ready to join a cluster as soon as it boots.

---

## Prerequisites

- A Nutanix account — free to create at [my.nutanix.com](https://my.nutanix.com)
- Access to Prism Central with the **Image Administrator** role (or higher)
- Enough storage in the image service for one `.qcow2` file (~3–5 GB)

---

## Step 1 — Download the image

1. Log in to **[my.nutanix.com](https://my.nutanix.com)**.
2. Navigate to **Downloads**.
3. In the product dropdown, select **"NKP Operating System Images"**.

   > 📌 This section was added in NKP 2.16+. If you only see older categories, make sure you are on a current portal version.

4. Locate the **Rocky Linux 9.7 – CIS Hardened for AHV** entry and download the `.qcow2` file.

The filename follows this pattern:

```
nkp-rocky-9.7-release-cis-1.34.3-20260504011927.qcow2
```

- `9.7` — Rocky Linux minor version
- `1.34.3` — Kubernetes version embedded in the image
- `20260504011927` — build timestamp (UTC)

> ⚠️ **Do not rename the file.** NKP auto-populates the image name from the filename. Renaming it will break the NKP image lookup during cluster creation.

---

## Step 2 — Upload to Prism Central

1. Log in to **Prism Central**.
2. Go to **Infrastructure → Compute & Storage → Images** (or search "Images" in the top bar).
3. Click **Add Image**.
4. Set **Image Type** to **Disk**.
5. Choose **Upload a file** and select the `.qcow2` you downloaded.
6. Leave the **Name** field exactly as auto-populated — do not edit it.
7. Click **Save** and wait for the upload to complete.

Once the image status shows **Active**, it is ready for use by the NKP bootstrap process.

---

## Quick Validation

After upload, confirm the image is visible and correctly typed:

```bash
# Using the Nutanix CLI (if configured)
nutanix@cvm$ acli image.list | grep nkp-rocky
```

Or via the Prism Central UI: the image should appear in the Images list with type **Disk** and state **Active**.

---

## Common Mistakes

| Mistake | Result | Fix |
|---|---|---|
| Downloading the wrong Rocky version | Bootstrap failure — K8s version mismatch | Re-download the image that matches your `nkp` CLI version |
| Renaming the `.qcow2` file | NKP cannot find the image by expected name | Delete and re-upload with the original filename |
| Uploading as type **ISO** instead of **Disk** | VMs boot incorrectly | Delete and re-upload, selecting **Disk** as image type |
| Using an image from a different NKP minor version | Subtle incompatibilities, potential node join failures | Always match NKP CLI version → OS image version |

---

## Next Steps

➡️ [Lesson 02 — NKP CLI Bootstrap](../../module-2/1.lesson-rke2-bootstrap/unit-1.md)
