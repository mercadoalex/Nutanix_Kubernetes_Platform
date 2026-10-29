---
kind: unit
title: "Lesson 06 — Bootstrap & Pivot: Building the Management Cluster"
name: 1-lesson-bootstrap-pivot-unit-1
---

# Lesson 06 — Bootstrap & Pivot: Building the Management Cluster

> **Tier:** 3 — Full Flexbox (5 VMs)  
> **Playground:** `nkp-flexbox.yaml`  
> **VMs used:** all five — vm1 (bootstrap), vm2 (controlplane), vm3–vm5 (workers)  
> **Duration:** ~45 minutes

---

## What you will do

In production, `nkp create cluster` calls Prism Central and provisions VMs for you. In this lab the VMs already exist — RKE2 is pre-installed on vm2–vm5. Your job is to replay the same logical steps:

1. Start the **Bootstrap Cluster** (a `kind` cluster) on vm1
2. Start the **RKE2 server** on vm2 — this becomes the Management Cluster control plane
3. Join **vm3, vm4, vm5** as worker nodes
4. **Pivot** — point your kubeconfig at the Management Cluster and verify it is fully operational
5. Delete the Bootstrap Cluster — it is no longer needed

By the end, you have a live 4-node Kubernetes cluster running RKE2, and you understand exactly what `nkp move` does under the hood.

---

## Lab topology

```
vm1  172.16.0.10   Bootstrap / operator workstation   (Ubuntu 24.04)
vm2  172.16.0.11   Management Cluster — control plane  (Rocky 9.7 / RKE2 server)
vm3  172.16.0.12   Management Cluster — worker-01      (Rocky 9.7 / RKE2 agent)
vm4  172.16.0.13   Management Cluster — worker-02      (Rocky 9.7 / RKE2 agent)
vm5  172.16.0.14   Management Cluster — worker-03      (Rocky 9.7 / RKE2 agent)
```

All five VMs share the `172.16.0.0/24` network. The RKE2 registration port is **9345**; the Kubernetes API listens on **6443**.

---

## Version reference

| Component | Version |
|---|---|
| NKP CLI (`nkp`) | 2.17.1 |
| RKE2 | v1.34.3+rke2r1 |
| Kubernetes | 1.34.3 |
| CNI | Cilium (RKE2 default, built into the airgap bundle) |

---

## Part 1 — Start the Bootstrap Cluster (vm1)

::image-box
---
:src: __static__/nkp-create-bootstrap-v1.png
:alt: 'docker ps output on vm1 showing the kind bootstrap cluster container running'
---
::

Open a terminal on **vm1**.

### 1.1 Verify tooling

```bash
nkp version
kubectl version --client
kind version
```

Expected output includes `v2.17.1`, `v1.34.3`, and `v0.27.0` respectively. If any command is missing, the rootfs image was not loaded correctly — re-launch the playground.

::image-box
---
:src: __static__/nkp-version-v1.png
:alt: 'Terminal output showing nkp version v2.17.1, kubectl version v1.34.3, and kind version v0.27.0'
---
::

### 1.2 Create the Bootstrap Cluster

```bash
nkp create bootstrap
```

`nkp` uses `kind` under the hood to create a local Kubernetes cluster, then installs the **Cluster API controllers** and the **Nutanix infrastructure provider** inside it.

> 📺 In production this cluster talks to Prism Central to provision real AHV VMs.  
> In this lab we skip that step — vm2–vm5 already exist with RKE2 pre-installed.

::image-box
---
:src: __static__/pulling-bootstrap-image-v1.png
:alt: 'Terminal output showing nkp create bootstrap pulling the kind bootstrap cluster image'
---
::

Watch the output. You will see:

```
✓ Bootstrap cluster created
✓ CAPI controllers installed
✓ Nutanix provider installed
```

### 1.3 Inspect the Bootstrap Cluster

```bash
kubectl get nodes
```

```
NAME                         STATUS   ROLES           AGE   VERSION
nkp-bootstrap-control-plane  Ready    control-plane   30s   v1.34.x
```

A single `kind` node. This is not a real cluster — it is scaffolding.

```bash
kubectl get pods -n capi-system
kubectl get pods -n capx-system    # Nutanix provider (CAPX)
kubectl get pods -n caren-system   # Runtime extensions (CAREN)
```

You should see the CAPI core controllers, CAPX (Cluster API Provider for Nutanix), and CAREN (Cluster API Runtime Extensions for Nutanix) running.

---

## Part 2 — Start the RKE2 server on vm2

::image-box
---
:src: __static__/kubectl-get-pods-v1.png
:alt: 'kubectl get pods -n capi-system showing CAPI core controllers and Nutanix provider pods all Running'
---
::


Switch to the **vm2** terminal.

### 2.1 Set the cluster token

The token is a shared secret all nodes use to authenticate to each other. Pick any string — it just needs to be consistent across all VMs.

```bash
mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<'EOF'
token: "nkp-lab-token-2024"
tls-san:
  - "172.16.0.11"
  - "vm2"
cni: cilium
disable:
  - rke2-ingress-nginx
write-kubeconfig-mode: "0644"
EOF
```

> ℹ️ A `config.yaml` skeleton is already present from the rootfs build. The block above **replaces** it with the live token and IP values for this lab run.

### 2.2 Start RKE2 server

```bash
systemctl enable --now rke2-server
```

Follow the startup logs in a second pane:

```bash
journalctl -u rke2-server -f
```

RKE2 will:
1. Load the airgap image bundles from `/var/lib/rancher/rke2/agent/images/` into containerd
2. Start `etcd`
3. Start `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`
4. Start `kubelet` and register vm2 as a node
5. Deploy Cilium as the CNI

**This takes 3–5 minutes.** Wait for the line:

```
Node controller sync successful
```

### 2.3 Verify the control plane is up

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
```

```
NAME   STATUS   ROLES                       AGE   VERSION
vm2    Ready    control-plane,etcd,master   4m    v1.34.3+rke2r1
```

### 2.4 Retrieve the node join token

```bash
cat /var/lib/rancher/rke2/server/node-token
```

Copy this value — you will paste it on vm3, vm4, and vm5 in the next step.

```
K10abc123...::server:xyz789...
```

---

## Part 3 — Join worker nodes (vm3, vm4, vm5)

**Repeat these steps on vm3, vm4, and vm5.** Open three terminals (one per VM) and run them in parallel — the join steps are identical and independent.

### 3.1 Write the agent config

Replace `<TOKEN>` with the value from vm2:

```bash
mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<'EOF'
server: "https://172.16.0.11:9345"
token: "K10abc123...::server:xyz789..."
EOF
```

> ⚠️ Use the **full token string** from `cat /var/lib/rancher/rke2/server/node-token` on vm2, not the short `nkp-lab-token-2024` string. The node-token is derived from it and is what agents authenticate with.

### 3.2 Start RKE2 agent

```bash
systemctl enable --now rke2-agent
```

Watch logs:

```bash
journalctl -u rke2-agent -f
```

Wait for:
```
Successfully registered node
```

**Each worker takes 2–3 minutes to join.** Running them in parallel means all three are done in ~3 minutes total.

### 3.3 Confirm all workers joined (back on vm2)

```bash
kubectl get nodes -o wide
```

```
NAME   STATUS   ROLES                       AGE    VERSION           INTERNAL-IP
vm2    Ready    control-plane,etcd,master   10m    v1.34.3+rke2r1   172.16.0.11
vm3    Ready    <none>                      2m     v1.34.3+rke2r1   172.16.0.12
vm4    Ready    <none>                      2m     v1.34.3+rke2r1   172.16.0.13
vm5    Ready    <none>                      2m     v1.34.3+rke2r1   172.16.0.14
```

All four nodes `Ready`. The Management Cluster is operational.

---

## Part 4 — Pivot (vm1)

::image-box
---
:src: __static__/placeholder-kubectl-get-nodes-all-four-ready.png
:alt: 'kubectl get nodes showing all four cluster nodes (vm2 control-plane, vm3-vm5 workers) in Ready status after pivot'
---
_TODO: Replace with actual screenshot — After copying and fixing the kubeconfig, run `kubectl get nodes` from vm1 pointing at the Management Cluster and capture the output showing vm2 (control-plane,etcd,master) and vm3–vm5 (workers) all Ready_
::


Back on **vm1**. This is the logical equivalent of `nkp move` — you stop using the Bootstrap Cluster as your control point and switch to the Management Cluster directly.

### 4.1 Copy the kubeconfig from vm2

```bash
mkdir -p ~/.kube
scp root@172.16.0.11:/etc/rancher/rke2/rke2.yaml ~/.kube/mgmt.kubeconfig
```

The kubeconfig from vm2 will have `127.0.0.1` as the server address — fix it to the real IP:

```bash
sed -i 's/127.0.0.1/172.16.0.11/' ~/.kube/mgmt.kubeconfig
```

### 4.2 Switch context to the Management Cluster

```bash
export KUBECONFIG=~/.kube/mgmt.kubeconfig
kubectl get nodes
```

```
NAME   STATUS   ROLES                       AGE    VERSION
vm2    Ready    control-plane,etcd,master   12m    v1.34.3+rke2r1
vm3    Ready    <none>                      4m     v1.34.3+rke2r1
vm4    Ready    <none>                      4m     v1.34.3+rke2r1
vm5    Ready    <none>                      4m     v1.34.3+rke2r1
```

You are now operating against the real Management Cluster from vm1 — exactly as you would after `nkp move` in production.

### 4.3 Verify core system pods

```bash
kubectl get pods -A | grep -v Running
```

Only `Completed` pods (init/job pods) should appear — no `Pending` or `CrashLoopBackOff`. If any pod is stuck, check its logs before continuing.

```bash
kubectl get pods -n kube-system
```

Key pods to confirm running:

| Pod prefix | What it is |
|---|---|
| `cilium-` | CNI — one per node |
| `cilium-operator-` | CNI control plane |
| `rke2-coredns-` | Cluster DNS |
| `rke2-metrics-server-` | Metrics API |
| `etcd-vm2` | etcd for the control plane |
| `kube-apiserver-vm2` | Kubernetes API server |

### 4.4 Delete the Bootstrap Cluster

The Bootstrap Cluster's job is done. In production `nkp move` deletes it automatically. Here you do it manually:

```bash
nkp delete bootstrap
```

```
✓ Bootstrap cluster deleted
```

Verify it is gone:

```bash
kind get clusters
```

```
No kind clusters found.
```

The scaffolding is down. The Management Cluster stands on its own.

---

## Part 5 — Explore your cluster

### 5.1 Check cluster info

```bash
kubectl cluster-info
```

```
Kubernetes control plane is running at https://172.16.0.11:6443
CoreDNS is running at https://172.16.0.11:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### 5.2 Inspect the nodes with k9s (optional)

```bash
k9s --kubeconfig ~/.kube/mgmt.kubeconfig
```

Press `0` to see all namespaces. Press `:nodes` to jump to the node view. Use `d` to describe a node. Press `q` to quit.

### 5.3 Run a test workload

Confirm the cluster can schedule and run pods:

```bash
kubectl run nginx --image=nginx:alpine --restart=Never
kubectl get pod nginx -w
```

Wait for `Running`, then clean up:

```bash
kubectl delete pod nginx
```

---

## What just happened — the pivot explained

::image-box
---
:src: __static__/placeholder-nkp-delete-bootstrap-output.png
:alt: 'nkp delete bootstrap terminal output confirming the bootstrap cluster was deleted and kind get clusters shows none'
---
_TODO: Replace with actual screenshot — Run `nkp delete bootstrap` and then `kind get clusters` and capture both commands and their output confirming "✓ Bootstrap cluster deleted" and "No kind clusters found."_
::


```
BEFORE PIVOT                        AFTER PIVOT

vm1 (Bootstrap)                     vm1 (operator workstation only)
└─ kind cluster                     └─ kubeconfig → vm2:6443
   └─ CAPI controllers
   └─ Nutanix provider              vm2 (Management Cluster CP)
                                    └─ RKE2 server
vm2  RKE2 server  (standalone)      └─ Kubernetes API
vm3  RKE2 agent                     └─ etcd
vm4  RKE2 agent                     vm3  worker node
vm5  RKE2 agent                     vm4  worker node
                                    vm5  worker node
```

In production, `nkp move` also migrates the `Cluster`, `Machine`, and `NutanixCluster` CRD objects from the Bootstrap Cluster into the Management Cluster, so the Management Cluster can manage its own lifecycle. In the lab we skip this because there are no CAPI objects to migrate — the VMs were pre-provisioned.

---

## Troubleshooting

### RKE2 server stuck at startup

```bash
journalctl -u rke2-server --no-pager | tail -50
```

Common causes:
- **Port 6443 already in use** — check `ss -tlnp | grep 6443`
- **Airgap bundles not loaded** — check `ls /var/lib/rancher/rke2/agent/images/`; if empty the rootfs image was not built correctly

### Worker node stuck in `NotReady`

```bash
# On the worker VM
journalctl -u rke2-agent --no-pager | tail -30
```

Common causes:
- **Wrong token** — re-check `cat /var/lib/rancher/rke2/server/node-token` on vm2 and update the agent config
- **Wrong server IP** — confirm `server: "https://172.16.0.11:9345"` (port **9345**, not 6443)
- **Network issue** — `ping 172.16.0.11` from the worker; `curl -k https://172.16.0.11:9345/ping`

### `scp` from vm1 to vm2 fails

Ensure the SSH service is running on vm2:
```bash
# On vm2
systemctl status sshd
```

Alternatively, copy the kubeconfig content manually: `cat /etc/rancher/rke2/rke2.yaml` on vm2, paste into `~/.kube/mgmt.kubeconfig` on vm1, then run the `sed` fix.

---

## Summary

| Step | Command | Where |
|---|---|---|
| Create bootstrap | `nkp create bootstrap` | vm1 |
| Start control plane | `systemctl enable --now rke2-server` | vm2 |
| Get join token | `cat /var/lib/rancher/rke2/server/node-token` | vm2 |
| Join workers | `systemctl enable --now rke2-agent` | vm3–5 |
| Copy kubeconfig | `scp root@172.16.0.11:/etc/rancher/rke2/rke2.yaml ~/.kube/mgmt.kubeconfig` | vm1 |
| Fix server address | `sed -i 's/127.0.0.1/172.16.0.11/' ~/.kube/mgmt.kubeconfig` | vm1 |
| Delete bootstrap | `nkp delete bootstrap` | vm1 |

---

## Next steps

➡️ [Lesson 07 — Node Operations: drain, cordon, taints](../2.lesson-node-operations/unit-1.md)
