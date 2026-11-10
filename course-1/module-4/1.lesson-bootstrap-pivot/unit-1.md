---
kind: unit
title: "Lesson 4.1 — Bootstrap & Pivot: Building the Management Cluster"
name: 1-lesson-bootstrap-pivot-unit-1
---

# Lesson 4.1 — Bootstrap & Pivot: Building the Management Cluster

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-lab`
> **VMs used:** all five — bootstrap (vm1), controlplane (vm2), worker-01–03 (vm3–5)
> **Duration:** ~30 minutes

---

## What you will do

In production, `nkp create cluster` calls Prism Central and provisions VMs for you. In this lab the VMs already exist — RKE2 is pre-installed and auto-started on vm2–vm5. Your job is to replay the same logical steps that NKP performs:

1. **Observe** — the Management Cluster is already running (RKE2 auto-started at playground boot)
2. **Run `nkp create bootstrap`** — start the kind Bootstrap Cluster on vm1 with all CAPI controllers
3. **Understand the pivot** — see how `nkp move` hands control from the Bootstrap Cluster to the Management Cluster
4. **Delete the Bootstrap Cluster** — it is no longer needed

By the end you understand exactly what happens inside NKP when a cluster is created and handed off.

---

## Lab topology

```
bootstrap     172.16.0.10   Bootstrap / operator workstation   (Ubuntu 24.04)
controlplane  172.16.0.11   Management Cluster — control plane  (Rocky 9.7 / RKE2 server)
worker-01     172.16.0.12   Management Cluster — worker         (Rocky 9.7 / RKE2 agent)
worker-02     172.16.0.13   Management Cluster — worker         (Rocky 9.7 / RKE2 agent)
worker-03     172.16.0.14   Management Cluster — worker         (Rocky 9.7 / RKE2 agent)
```

All five VMs share the `172.16.0.0/24` network. The RKE2 registration port is **9345**; the Kubernetes API listens on **6443**.

---

## Version reference

| Component | Version |
|---|---|
| NKP CLI (`nkp`) | 2.17.1 |
| RKE2 | v1.34.3+rke2r1 |
| Kubernetes | 1.34.3 |
| CNI | Cilium (RKE2 default) |

---

## Before you start — the cluster is already running

When this playground booted, three things happened automatically in the background:

1. **controlplane** — `rke2-server` started via systemd
2. **worker-01, worker-02, worker-03** — `rke2-agent` started and joined the control plane
3. **bootstrap** — `cluster-pivot.service` waited until all 4 nodes were Ready, then copied the kubeconfig

> 🖥️ **Run on bootstrap (vm1).** Confirm the cluster is Ready before starting:

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME           STATUS   ROLES                AGE   VERSION          INTERNAL-IP
controlplane   Ready    control-plane,etcd   2m    v1.34.3+rke2r1   172.16.0.11
worker-01      Ready    <none>               90s   v1.34.3+rke2r1   172.16.0.12
worker-02      Ready    <none>               90s   v1.34.3+rke2r1   172.16.0.13
worker-03      Ready    <none>               90s   v1.34.3+rke2r1   172.16.0.14
```

If the cluster is not yet Ready, wait 1–2 minutes and retry. You can watch the auto-pivot progress:

```bash
journalctl -u cluster-pivot.service --no-pager | tail -20
```

---

## Part 1 — Start the Bootstrap Cluster

::image-box
---
:src: __static__/nkp-create-bootstrap-v1.png
:alt: 'Terminal output of nkp create bootstrap completing successfully'
---
_⚠️ Placeholder — replace with real screenshot before course launch._
::

This is the only part of the lesson where you replicate what NKP does in production. In production, `nkp create bootstrap` runs on the jump host before `nkp create cluster`. Here you run it to see exactly what it does.

### 1.1 Verify tooling

> 🖥️ **Run on bootstrap (vm1).**

```bash
nkp version
kubectl version --client
kind version
```

You should see `v2.17.1`, `v1.34.3`, and `v0.27.0` respectively.

### 1.2 Create the Bootstrap Cluster

> 🖥️ **Run on bootstrap (vm1).**

```bash
nkp create bootstrap
```

`nkp` uses `kind` under the hood to create a local Kubernetes cluster, then installs the **Cluster API controllers** and all infrastructure providers (CAPX, CAREN, CAPA, CAPZ, CAPG...) inside it.

> 📺 In production this cluster's CAPI controllers talk to Prism Central to provision real AHV VMs.
> In this lab we skip that — vm2–vm5 already exist.

Watch the output:

```
✓ Creating a bootstrap cluster
✓ Initializing new CAPI components
✓ Creating ClusterClass resources
```

**This completes in ~2 minutes** — the `konvoy-bootstrap` image was pre-pulled at playground start.

### 1.3 Inspect the Bootstrap Cluster

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl config current-context
kubectl get nodes
```

```
NAME                                   STATUS   ROLES           AGE
konvoy-capi-bootstrapper-control-plane Ready    control-plane   2m
```

This is the `kind` node — a single container running an entire Kubernetes control plane. It is scaffolding, not a real cluster.

Now look at what's running inside it:

```bash
kubectl get pods -A | grep -E "NAMESPACE|capi|capx|caren|cert"
```

```
NAMESPACE      NAME                                              READY   STATUS
capi-system    capi-controller-manager-...                       1/1     Running
capx-system    capx-controller-manager-...                       1/1     Running
caren-system   cluster-api-runtime-extensions-nutanix-...        1/1     Running
cert-manager   cert-manager-...                                  1/1     Running
```

These are the **CAPI controllers** — the brain of NKP cluster provisioning.

---

## Part 2 — Observe the Management Cluster

The Management Cluster was already built by the playground. This section explains what happened so you understand each component.

### 2.1 What ran on controlplane (vm2)

> 🖥️ **Switch to the controlplane terminal.**

```bash
sudo systemctl status rke2-server --no-pager | head -5
```

`rke2-server` is `active (running)` — it started automatically at boot. The config was baked into the image:

```bash
cat /etc/rancher/rke2/config.yaml
```

```yaml
token: "nkp-lab-token-2024"
tls-san:
  - "172.16.0.11"
  - "controlplane"
cni: cilium
disable:
  - rke2-ingress-nginx
write-kubeconfig-mode: "0644"
```

In production you would write this config before running `systemctl enable --now rke2-server`.

### 2.2 What ran on the workers (vm3–5)

> 🖥️ **Switch to any worker terminal (worker-01, worker-02, or worker-03).**

```bash
sudo systemctl status rke2-agent --no-pager | head -5
cat /etc/rancher/rke2/config.yaml
```

```yaml
server: "https://172.16.0.11:9345"
token: "nkp-lab-token-2024"
```

The workers have the same token as the control plane and know where to register. In production you copy this token from `cat /var/lib/rancher/rke2/server/node-token` on the control plane.

### 2.3 What ran on bootstrap (vm1)

> 🖥️ **Back on bootstrap (vm1).**

The `cluster-pivot.service` ran automatically. It:
1. Waited for SSH to become available on `172.16.0.11`
2. Waited for `rke2.yaml` to be written by RKE2
3. Copied the kubeconfig and fixed the server address
4. Waited until all 4 nodes showed `Ready`

```bash
journalctl -u cluster-pivot.service --no-pager
```

```
[cluster-pivot] Waiting for controlplane SSH...
[cluster-pivot] controlplane SSH ready
[cluster-pivot] Waiting for RKE2 kubeconfig on controlplane...
[cluster-pivot] RKE2 kubeconfig ready
[cluster-pivot] kubeconfig copied to /home/laborant/.kube/mgmt.kubeconfig
[cluster-pivot] ...1/4 nodes Ready (30s)
[cluster-pivot] All 4 nodes Ready ✓
[cluster-pivot] Cluster pivot complete. Run: kubectl get nodes
```

This is exactly what `nkp move` does — it transfers control from the Bootstrap Cluster to the Management Cluster.

---

## Part 3 — Explore the Management Cluster

::image-box
---
:src: __static__/the-pivot-v1.png
:alt: 'kubectl get nodes showing all four cluster nodes in Ready status after pivot'
---
_⚠️ Placeholder — replace with real screenshot before course launch._
::

> 🖥️ **Run on bootstrap (vm1).**

### 3.1 Verify all nodes and their roles

```bash
kubectl get nodes -o wide
```

```
NAME           STATUS   ROLES                AGE   VERSION          INTERNAL-IP
controlplane   Ready    control-plane,etcd   5m    v1.34.3+rke2r1   172.16.0.11
worker-01      Ready    <none>               3m    v1.34.3+rke2r1   172.16.0.12
worker-02      Ready    <none>               3m    v1.34.3+rke2r1   172.16.0.13
worker-03      Ready    <none>               3m    v1.34.3+rke2r1   172.16.0.14
```

### 3.2 Verify core system pods

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
| `etcd-controlplane` | etcd |
| `kube-apiserver-controlplane` | Kubernetes API server |

### 3.3 Explore with k9s

> 🖥️ **Run on bootstrap (vm1).**

```bash
k9s
```

- Press `0` to see all namespaces
- Press `:nodes` to jump to the node view
- Use `d` to describe a node
- Press `q` to quit

### 3.4 Run a test workload

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

## Part 4 — Delete the Bootstrap Cluster

The Bootstrap Cluster's job is done. In production `nkp move` deletes it automatically. Here you do it manually:

> 🖥️ **Run on bootstrap (vm1).**

```bash
nkp delete bootstrap
kind get clusters
```

```
✓ Deleting bootstrap cluster
No kind clusters found.
```

The scaffolding is gone. The Management Cluster stands on its own — it is now **self-managed**.

---

## What just happened — the pivot explained

```
BEFORE PIVOT                         AFTER PIVOT

bootstrap (vm1)                      bootstrap (vm1)
└─ kind cluster                      └─ kubeconfig → controlplane:6443
   └─ CAPI controllers               └─ Bootstrap cluster deleted
   └─ Nutanix provider

controlplane  RKE2 server            controlplane  Management Cluster CP
worker-01     RKE2 agent             worker-01     worker node
worker-02     RKE2 agent             worker-02     worker node
worker-03     RKE2 agent             worker-03     worker node
```

In production, `nkp move` also migrates the `Cluster`, `Machine`, and `NutanixCluster` CRD objects from the Bootstrap Cluster into the Management Cluster — so the Management Cluster can manage its own lifecycle going forward. In the lab we skip this because there are no CAPI objects to migrate (the VMs were pre-provisioned).

---

## Troubleshooting

### Cluster not Ready after 5 minutes

```bash
journalctl -u cluster-pivot.service --no-pager | tail -20
sudo systemctl status rke2-server --no-pager   # on controlplane
sudo systemctl status rke2-agent --no-pager    # on any worker
```

### `nkp create bootstrap` fails with webhook errors

The CAPI webhooks are still initializing. Wait 60 seconds and run again — `nkp create bootstrap` detects the existing cluster and retries cleanly:

```bash
nkp create bootstrap
```

### Worker node stuck in `NotReady`

```bash
# On the worker VM
sudo journalctl -u rke2-agent --no-pager | tail -30
# Verify connectivity
curl -k https://172.16.0.11:9345/ping
```

---

## Summary

| Step | What happened | How |
|---|---|---|
| RKE2 server started | controlplane booted | `systemctl enable rke2-server` in rootfs |
| Workers joined | worker-01/02/03 booted | `systemctl enable rke2-agent` + baked config |
| Kubeconfig pivoted | `cluster-pivot.service` ran on bootstrap | Automatic — polls until 4 nodes Ready |
| Bootstrap Cluster | **You** created and deleted it | `nkp create bootstrap` / `nkp delete bootstrap` |

---

## Next steps

➡️ [Lesson 4.2 — Node Operations: drain, cordon, taints](../2.lesson-node-operations/unit-1.md)
