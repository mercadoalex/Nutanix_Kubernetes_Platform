# Lesson 03 — Creating the Management Cluster on AHV

> **Tier:** 1 — Walkthrough (no playground required)  
> **Purpose:** Run `nkp create cluster` to provision a self-managed Management Cluster on AHV, then perform the CAPI pivot with `nkp move`.

> 📺 **This lesson requires real AHV infrastructure** (Prism Central + AHV cluster + Bootstrap Cluster from Lesson 02).  
> Commands and expected output are shown in full so you can follow along.

---

## What you will do

1. Run `nkp create cluster` — provision control plane and worker VMs on AHV via Prism Central
2. Watch `k9s` as CAPI provisions the VMs and RKE2 bootstraps them
3. Run `nkp move` — pivot the CAPI controllers from the Bootstrap Cluster into the new Management Cluster
4. Retrieve the Management Cluster kubeconfig
5. Verify the cluster is fully operational

---

## Prerequisites

- Bootstrap Cluster is running (Lesson 02 complete)
- `source ~/nkp-env` has been run in the current shell
- `nkp check environment --provider nutanix` passes all checks
- Prism Central shows the Rocky 9.7 image with status **Active**

---

## Version reference

| Component | Version |
|---|---|
| NKP CLI (`nkp`) | 2.17.1 |
| RKE2 / Kubernetes | 1.34.3+rke2r1 |
| Node OS | Rocky Linux 9.7 (CIS hardened) |
| Control plane replicas | 3 (HA) |
| Worker replicas | 4 |

---

## Part A — Run `nkp create cluster`

This single command drives the entire cluster provisioning flow through Prism Central.

```bash
source ~/nkp-env

nkp create cluster nutanix \
  --cluster-name "${CLUSTER_NAME}" \
  --endpoint "https://${NUTANIX_ENDPOINT}:${NUTANIX_PORT}" \
  --insecure \
  --control-plane-endpoint-ip "${CONTROL_PLANE_ENDPOINT_IP}" \
  --kubernetes-service-load-balancer-ip-range "${LB_IP_RANGE}" \
  --control-plane-vm-image "${NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME}" \
  --control-plane-prism-element-cluster "${PE_CLUSTER_NAME}" \
  --control-plane-subnets "${SUBNET_NAME}" \
  --control-plane-replicas 3 \
  --worker-vm-image "${NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME}" \
  --worker-prism-element-cluster "${PE_CLUSTER_NAME}" \
  --worker-subnets "${SUBNET_NAME}" \
  --worker-replicas 4 \
  --csi-storage-container "${STORAGE_CONTAINER}" \
  --csi-hypervisor-attached-volumes=true \
  --registry-mirror-url "${REGISTRY_MIRROR_URL}" \
  --self-managed
```

> **`--self-managed`** is the critical flag. It tells NKP this cluster will become the Management Cluster — CAPI controllers will eventually live inside it, and it will manage its own lifecycle.

### What happens after you press Enter

`nkp create cluster` does not provision VMs itself — it **creates CAPI custom resources** in the Bootstrap Cluster. The CAPI controllers then reconcile those resources by calling the Prism Central API.

```
nkp create cluster
    └─► Creates in Bootstrap Cluster:
        ├─ Cluster (CAPI core)
        ├─ NutanixCluster (CAPC — Nutanix-specific)
        ├─ MachineDeployment (3 control plane + 4 workers)
        └─ NutanixMachineTemplate (VM spec: image, vCPUs, RAM, subnet)

CAPC controller watches these resources
    └─► Calls Prism Central REST API
        └─► AHV clones the Rocky 9.7 image → 7 VMs appear in Prism
            └─► cloud-init runs on each VM
                └─► RKE2 bootstraps each VM
                    └─► Nodes join the cluster
```

---

## Part B — Watch provisioning with k9s

In a second terminal on the jump host, open `k9s` pointed at the Bootstrap Cluster:

```bash
k9s
```

Press `:` and type `cluster` to watch CAPI `Cluster` objects. You will see the cluster move through phases:

```
Provisioning → Provisioned → Deleting (bootstrap) → Ready
```

Switch to `:machines` to watch individual VM provisioning. Each `Machine` object moves through:

```
Pending → Provisioning → Running
```

Switch to `:pods` and filter by namespace `capi-system` to watch the CAPI reconciliation loop in real time.

In **Prism Central** → **Compute & Storage** → **VMs**, you will see the VMs appear and boot:

```
nkp-management-cp-0    (control plane 1 of 3)
nkp-management-cp-1    (control plane 2 of 3)
nkp-management-cp-2    (control plane 3 of 3)
nkp-management-md-0-0  (worker 1 of 4)
nkp-management-md-0-1  (worker 2 of 4)
nkp-management-md-0-2  (worker 3 of 4)
nkp-management-md-0-3  (worker 4 of 4)
```

**Total provisioning time: 15–30 minutes** depending on image clone speed and network throughput.

---

## Part C — Wait for the cluster to be Ready

```bash
kubectl wait cluster/${CLUSTER_NAME} \
    --for=condition=Ready \
    --timeout=30m
```

When this returns without error, the Management Cluster's Kubernetes API is up and all nodes have joined.

Alternatively, watch with:

```bash
kubectl get cluster ${CLUSTER_NAME} -w
```

```
NAME              PHASE          AGE   VERSION
nkp-management   Provisioning   2m    v1.34.3
nkp-management   Provisioned    18m   v1.34.3
nkp-management   Ready          22m   v1.34.3
```

---

## Part D — Retrieve the Management Cluster kubeconfig

```bash
mkdir -p ~/clusters
nkp get kubeconfig --cluster-name ${CLUSTER_NAME} > ~/clusters/mgmt.kubeconfig
chmod 600 ~/clusters/mgmt.kubeconfig
```

Verify you can reach the Management Cluster API directly:

```bash
kubectl --kubeconfig ~/clusters/mgmt.kubeconfig get nodes
```

```
NAME                    STATUS   ROLES                       AGE   VERSION
nkp-management-cp-0     Ready    control-plane,etcd,master   20m   v1.34.3+rke2r1
nkp-management-cp-1     Ready    control-plane,etcd,master   18m   v1.34.3+rke2r1
nkp-management-cp-2     Ready    control-plane,etcd,master   17m   v1.34.3+rke2r1
nkp-management-md-0-0   Ready    <none>                      15m   v1.34.3+rke2r1
nkp-management-md-0-1   Ready    <none>                      15m   v1.34.3+rke2r1
nkp-management-md-0-2   Ready    <none>                      14m   v1.34.3+rke2r1
nkp-management-md-0-3   Ready    <none>                      14m   v1.34.3+rke2r1
```

All 7 nodes `Ready`. 3 control plane + 4 workers = HA cluster.

---

## Part E — Pivot: `nkp move`

**This is the most important step.** The CAPI controllers are currently running in the Bootstrap Cluster (the `kind` cluster on your jump host). `nkp move` migrates them — and all the CAPI objects that describe the Management Cluster — **into the Management Cluster itself**.

After the pivot, the Management Cluster manages its own lifecycle. It no longer depends on anything running on the jump host.

```bash
nkp move \
    --to-kubeconfig ~/clusters/mgmt.kubeconfig
```

Expected output:

```
INFO[...] Pivoting cluster-api objects from bootstrap cluster to target cluster
INFO[...] Moving Cluster nkp-management
INFO[...] Moving NutanixCluster nkp-management
INFO[...] Moving MachineDeployments
INFO[...] Moving Machines
INFO[...] Pivot complete
✓ Cluster API objects moved to management cluster
```

### What `nkp move` does internally

1. **Pauses** reconciliation on all CAPI objects in the Bootstrap Cluster (so nothing changes during the move)
2. **Copies** all CAPI CRD objects (`Cluster`, `NutanixCluster`, `Machine`, `MachineDeployment`, etc.) to the Management Cluster
3. **Installs** the CAPI controllers and Nutanix provider into the Management Cluster
4. **Resumes** reconciliation — now the Management Cluster's own CAPI controllers own the objects
5. **Deletes** the CAPI objects from the Bootstrap Cluster

The Management Cluster is now fully self-hosted.

---

## Part F — Delete the Bootstrap Cluster

```bash
nkp delete bootstrap
```

```
✓ Bootstrap cluster deleted
```

Confirm the `kind` cluster is gone:

```bash
kind get clusters
# No kind clusters found.
```

The jump host is now just an operator workstation. Nothing critical is running on it.

---

## Part G — Verify the Management Cluster is self-managed

Switch your kubeconfig to the Management Cluster:

```bash
export KUBECONFIG=~/clusters/mgmt.kubeconfig
```

Verify CAPI is now running inside the Management Cluster:

```bash
kubectl get pods -n capi-system
kubectl get pods -n capc-system
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
capi-controller-manager-xxxx               1/1     Running   0          5m
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
capc-controller-manager-xxxx               1/1     Running   0          5m
```

Verify the cluster object is present and owned by itself:

```bash
kubectl get cluster ${CLUSTER_NAME} -n default
```

```
NAME              PHASE   AGE   VERSION
nkp-management   Ready   45m   v1.34.3
```

The Management Cluster sees and manages itself. This is the **self-managed** state.

---

## Part H — Access Kommander

Kommander (the NKP multi-cluster management UI) is deployed as part of the Management Cluster.

```bash
# Get the Kommander dashboard URL
nkp get dashboard --kubeconfig ~/clusters/mgmt.kubeconfig
```

```
https://10.0.2.50/dkp/kommander/dashboard
Username: admin
Password: <generated — shown in output>
```

Open the URL in your browser. This is the central control plane for your entire NKP fleet.

---

## Troubleshooting

### Machines stuck in `Provisioning`

```bash
kubectl get machines -A
kubectl describe machine <name>
```

Check the events section. Common causes:
- **Image not found in Prism Central** — verify `NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME` matches exactly
- **Subnet name mismatch** — check `SUBNET_NAME` matches the Prism Central network name exactly
- **Insufficient Prism Element capacity** — check CVM resources in Prism Element

### `nkp move` fails mid-way

The pivot is designed to be re-runnable. If it fails, run the same `nkp move` command again — CAPI objects that were already moved are skipped.

### Control plane VIP unreachable after pivot

Verify `CONTROL_PLANE_ENDPOINT_IP` is not in the DHCP scope and is not assigned to another device. Check it is routable from the jump host:

```bash
curl -k https://${CONTROL_PLANE_ENDPOINT_IP}:6443/healthz
# Should return: ok
```

---

## Summary

| Step | Command | Time |
|---|---|---|
| Create cluster | `nkp create cluster nutanix ...` | 15–30 min |
| Wait for Ready | `kubectl wait cluster/... --for=condition=Ready` | — |
| Get kubeconfig | `nkp get kubeconfig --cluster-name ...` | < 1 min |
| Pivot CAPI | `nkp move --to-kubeconfig ...` | 2–5 min |
| Delete bootstrap | `nkp delete bootstrap` | < 1 min |
| Verify self-managed | `kubectl get pods -n capi-system` | — |
| Access Kommander | `nkp get dashboard` | — |

---

## Next steps

➡️ [Lesson 04 — The NKP CLI: kubeconfig, Contexts, and Cluster Access](../04-nkp-cli/README.md)
