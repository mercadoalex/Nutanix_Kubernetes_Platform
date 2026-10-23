---
kind: unit
title: "Design Review 2: Live Troubleshooting — Clusters Stuck in Provisioning"
name: lesson-design-review-2-unit-1
---

::remark-box
This is a **live troubleshooting scenario** — the kind of call you get at 2pm on a Tuesday when a customer's deployment has been sitting in `Provisioning` for two hours. The goal is not just to find the answer, but to show your **framework**: how you think, where you look first, and why.
::

## The call

> *"We ran `nkp create cluster` three hours ago. The cluster is still in `Provisioning`. Nothing in the UI tells us what's wrong."*

Your first response is not a command — it is a question:

> *"Before I start, let me understand your environment: Are the NKP controller pods running? Can you reach Prism Central from the management cluster nodes? And what version of AOS and PC are you on?"*

These three questions tell you whether you are dealing with a connectivity problem, a version mismatch, or a deeper infrastructure issue. Then you start the framework.

---

## The debugging framework

> *"I use a layered failure approach. NKP has three critical integration layers with Nutanix — each has its own logs and failure signals. I go from the outermost layer inward, stopping as soon as I find the broken layer."*

```
Layer 1  →  Prism Central connectivity (port 9440)
Layer 2  →  OS image availability in Prism Central
Layer 3  →  Subnet IPAM / IP allocation
Layer 4  →  CSI storage container
Layer 5  →  CAPI cluster object conditions
```

You do not jump to layer 5 before ruling out layers 1–4. Most production incidents live in layers 1–3.

---

## Step 1 — Prism Central connectivity on port 9440

> *"First I verify that the management cluster nodes can reach PC on port 9440. If there's no connectivity, nothing works — CAPX, CSI, and CCM all call that endpoint."*

```bash
# From a node in the management cluster (or the operator workstation):
curl -k https://<PC_IP>:9440/api/nutanix/v3/clusters

# Check the CAPX controller logs directly:
kubectl logs -n capx-system \
  $(kubectl get pod -n capx-system -l control-plane=controller-manager -o name) \
  | grep -i error
```

| Signal | Meaning | Action |
|---|---|---|
| HTTP 200 + JSON cluster list | Connectivity OK — move to Step 2 | — |
| `Connection refused` | Port 9440 blocked or PC not listening | Check firewall rules between cluster nodes and PC |
| `Connection timed out` | Network path issue or PC overloaded | Check routing, NSG rules, PC health |
| `SSL handshake failed` | TLS certificate mismatch or expired cert | Verify PC certificate, check `--insecure` flag usage |

::details-box
---
:summary: "Why port 9440 is always Step 1"
---
Port 9440 is the single endpoint that CAPX, the CSI driver, and the CCM all depend on. A firewall rule change, an expired certificate, or a PC restart can block all three simultaneously. The symptom — cluster stuck in `Provisioning` — is identical for all three root causes. Ruling out 9440 first eliminates the most common cause in one check.
::

---

## Step 2 — OS image availability in Prism Central

> *"If connectivity is fine, the next failure point is the node OS image. CAPI does not install the OS from scratch — it references a pre-built image in Prism Central. If that image is missing or has the wrong name, CAREN's `BeforeClusterCreate` hook blocks VM creation immediately."*

```bash
# List available images in Prism Central via the API:
curl -k -u <pc-user>:<pc-password> \
  https://<PC_IP>:9440/api/nutanix/v3/images \
  | jq '.entities[].spec.name'

# Check CAPX logs for image resolution errors:
kubectl logs -n capx-system \
  $(kubectl get pod -n capx-system -l control-plane=controller-manager -o name) \
  | grep -i "image"

# Check CAREN logs for BeforeClusterCreate hook failures:
kubectl logs -n caren-system \
  $(kubectl get pod -n caren-system -l app=caren -o name) \
  | grep -i "image\|before"
```

| Signal | Meaning | Action |
|---|---|---|
| Image name appears in API response | Image present — move to Step 3 | — |
| `image not found` in CAPX logs | Image missing from PC | Upload the correct `.qcow2` CIS-hardened image to PC |
| Image present but wrong version | Image name mismatch | Verify exact filename matches `--control-plane-vm-image` flag |

::details-box
---
:summary: "The image filename trap — why exact names matter"
---
The `--control-plane-vm-image` flag takes the **exact image name as it appears in Prism Central** — including the full version string. A common mistake is uploading `nkp-rocky-9.7-release-cis-1.34.3.qcow2` but passing `nkp-rocky-9.7-cis` as the flag value. CAREN's `BeforeClusterCreate` hook does an exact-string match and rejects it. Always copy the image name directly from the PC image list.
::

---

## Step 3 — Subnet IPAM and IP allocation

> *"If the image exists, the next layer is IP assignment. CAPI needs to assign IPs to control plane and worker nodes automatically via the subnet's IPAM pool in Prism Central. Without it, `MachineSet` controllers cannot provision nodes."*

```bash
# Check the status of MachineSet objects:
kubectl get machineset -A

# Describe a stuck MachineSet for detailed events:
kubectl describe machineset <machineset-name> -n <namespace>

# Cluster-wide events sorted by time — most useful for catching IP allocation failures:
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Check NutanixMachine objects for per-node errors:
kubectl get nutanixmachine -A
kubectl describe nutanixmachine <machine-name> -n <namespace>
```

| Signal | Meaning | Action |
|---|---|---|
| `Machines` show `Provisioning` → `Running` | IP allocation working — move to Step 4 | — |
| `No IP addresses available` | IPAM pool exhausted | Expand the IPAM range in PC subnet configuration |
| `Failed to allocate IP` | IPAM not configured on subnet | Add an IPAM pool to the Prism Central subnet |
| `NutanixMachine` stuck in `Pending` | VM never created in AHV | Check CAPX logs for the specific PC API call that failed |

::details-box
---
:summary: "IPAM vs DHCP — which one does CAPI expect?"
---
CAPI supports both IPAM pools (configured in Prism Central) and DHCP. However, IPAM pools are strongly preferred for NKP because they give Prism Central deterministic control over IP assignment and avoid race conditions with external DHCP servers. If the customer uses DHCP, verify the DHCP server has enough leases available for all planned nodes (control plane × replicas + workers × replicas + a buffer for rolling upgrades).
::

---

## Step 4 — CSI storage container

> *"If the nodes boot and join the cluster but pods with `PersistentVolumeClaim` stay in `Pending`, the problem has shifted from cluster provisioning to storage provisioning. The CSI driver cannot create volumes."*

```bash
# Check CSI controller pod health:
kubectl get pods -n ntnx-system
kubectl describe pod -n ntnx-system -l app=nutanix-csi-controller

# Check CSI driver logs:
kubectl logs -n ntnx-system \
  $(kubectl get pod -n ntnx-system -l app=nutanix-csi-controller -o name) \
  -c nutanix-csi-plugin

# Verify storage container exists in Prism Element (not PC):
curl -k -u <pe-user>:<pe-password> \
  https://<PE_IP>:9440/api/nutanix/v3/storage_containers \
  | jq '.entities[].spec.name'

# Check PVC events for the specific failure message:
kubectl describe pvc <pvc-name> -n <namespace>
```

| Signal | Meaning | Action |
|---|---|---|
| CSI pods `Running`, volumes mount | CSI OK — problem is elsewhere | — |
| `storage container not found` | Container name mismatch | Verify `--csi-storage-container` value matches exact name in PE |
| `Permission denied` on storage container | CSI service account lacks storage write access | Grant `Storage.Admin` role to the NKP PC user in Prism |
| PVC stays `Pending` with no CSI events | CSI driver not registered with kubelet | Check `kubelet` logs on the node for CSI registration errors |

---

## Step 5 — CAPI cluster object conditions

> *"If all four layers above check out but the cluster is still not `Ready`, I go directly to the CAPI `Cluster` object. Its `status.conditions` field is the authoritative source of truth for what CAPI thinks is wrong."*

```bash
# Get the full cluster object — conditions are in status:
kubectl get cluster <cluster-name> -n <namespace> -o yaml | yq '.status.conditions'

# Human-readable describe output:
kubectl describe cluster <cluster-name> -n <namespace>

# Check the RKE2ControlPlane object — often has more specific errors:
kubectl get rke2controlplane -n <namespace>
kubectl describe rke2controlplane <cp-name> -n <namespace>

# Check individual Machine objects for node-level errors:
kubectl get machine -n <namespace>
kubectl describe machine <machine-name> -n <namespace>
```

**Common condition failures and their causes:**

| Condition | Failure message | Root cause |
|---|---|---|
| `ControlPlaneReady` | `KubeConfig generation failed` | cert-manager not running or TLS bootstrap error |
| `ControlPlaneReady` | `Control plane not ready after X minutes` | RKE2 server failed to start — check node journal |
| `InfrastructureReady` | `NutanixCluster reconciliation failed` | CAPX cannot reach PC — back to Step 1 |
| `MachinesReady` | `Machine X failed to join` | Network policy blocking node-to-node communication |

```bash
# If a node joined but RKE2 is not healthy — check the node directly:
ssh <node-ip> "journalctl -u rke2-server -n 100"   # control plane
ssh <node-ip> "journalctl -u rke2-agent -n 100"    # workers
```

::details-box
---
:summary: "Interview answer: how do you approach a cluster stuck in Provisioning?"
---
*"I use a layered approach — outermost to innermost. Layer 1 is always PC:9440 connectivity because every NKP controller depends on it. If that's fine I check image availability, then IPAM, then CSI, then finally the CAPI object conditions. Most production incidents resolve at layers 1–3. The CAPI conditions in layer 5 are the authoritative source of truth but they only tell you 'what' failed, not 'why' — you need the lower-layer signals to understand the root cause."*
::

---

## Debugging cheatsheet

```bash
# ── CAPX (VM provisioning) ─────────────────────────────────────────────────
kubectl logs -n capx-system -l control-plane=controller-manager --tail=100

# ── CAREN (lifecycle hooks) ───────────────────────────────────────────────
kubectl logs -n caren-system -l app=caren --tail=100

# ── CSI driver ────────────────────────────────────────────────────────────
kubectl logs -n ntnx-system -l app=nutanix-csi-controller -c nutanix-csi-plugin --tail=100

# ── CAPI core controllers ─────────────────────────────────────────────────
kubectl logs -n capi-system -l control-plane=controller-manager --tail=100

# ── All cluster events (most useful for a quick triage) ──────────────────
kubectl get events -A --sort-by='.lastTimestamp' | grep -i "fail\|error\|warn" | tail=50

# ── Cluster object conditions ─────────────────────────────────────────────
kubectl get cluster -A
kubectl describe cluster <name> -n <namespace>
```

---

## Framework summary

| Step | What you check | Tools |
|---|---|---|
| **1. PC connectivity** | Can nodes reach `PC:9440`? | `curl`, CAPX logs |
| **2. OS image** | Does the image exist in PC with the exact name? | PC API, CAPX logs, CAREN logs |
| **3. IPAM** | Does the subnet have an IP pool with free addresses? | `MachineSet` events, `NutanixMachine` describe |
| **4. CSI** | Does the storage container exist and is the CSI user authorized? | CSI logs, PE API, PVC events |
| **5. CAPI conditions** | What does the `Cluster` object's `status.conditions` say? | `kubectl describe cluster`, RKE2ControlPlane, node journald |

> Stop at the first broken layer. Fix it, re-run, then continue down the list only if the cluster is still stuck.
