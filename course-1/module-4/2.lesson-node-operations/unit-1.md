---
kind: unit
title: "Lesson 4.2 — Node Operations: drain, cordon, taints, and tolerations"
name: 2-lesson-node-operations-unit-1
---

# Lesson 4.2 — Node Operations: drain, cordon, taints, and tolerations

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-lab`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running across worker-01–worker-03
> **Duration:** ~40 minutes

---

## What you will do

Safely take nodes in and out of service — the operations you perform during OS patching, hardware maintenance, and rolling cluster upgrades:

- **cordon** — mark a node unschedulable (no new pods land here)
- **drain** — evict all running pods from a node gracefully
- **uncordon** — return a node to service
- **taints & tolerations** — restrict which pods can run on which nodes

All commands run from **bootstrap (vm1)** against the live Management Cluster.

---

## Lab topology reminder

```
controlplane  172.16.0.11   control plane
worker-01     172.16.0.12   worker node 1
worker-02     172.16.0.13   worker node 2
worker-03     172.16.0.14   worker node 3
```

---

## Part 1 — cordon and drain

::image-box
---
:src: __static__/kubectl-drain-v1.png
:alt: 'kubectl drain worker-03 terminal output showing pods being evicted one by one with ignore-daemonsets flag'
---
_⚠️ Placeholder — replace with real playground screenshot before course launch._
::

### 1.1 Deploy a test workload spread across workers

> 🖥️ **Run on bootstrap (vm1).** Copy and run the following commands in your terminal.

```bash
kubectl create deployment drain-test --image=nginx:alpine --replicas=6
kubectl get pods -l app=drain-test -o wide
```

Confirm pods are spread across worker-01, worker-02, and worker-03. You should see 6 pods distributed across the three worker nodes.

### 1.2 Cordon worker-02

Cordoning marks a node **unschedulable** — the scheduler will not place new pods on it. Existing pods are **not** evicted.

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl cordon worker-02
kubectl get nodes
```

Expected output:

```
NAME           STATUS                     ROLES                AGE
controlplane   Ready                      control-plane,etcd   1h
worker-01      Ready                      <none>               1h
worker-02      Ready,SchedulingDisabled   <none>               1h
worker-03      Ready                      <none>               1h
```

`SchedulingDisabled` — worker-02 is cordoned. Now verify existing pods on worker-02 are still running:

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl get pods -l app=drain-test -o wide
```

Pods on worker-02 are untouched. Only **new** pods are blocked from landing there.

### 1.3 Drain worker-02

Drain evicts all non-daemonset pods from a node gracefully. Each pod is given time to terminate cleanly before the next one is evicted.

> 🖥️ **Open a second terminal on bootstrap (vm1) and run the watch command first, then run the drain in your first terminal.**

Second terminal — watch pods reschedule in real time:

```bash
kubectl get pods -l app=drain-test -o wide -w
```

First terminal — drain the node:

```bash
kubectl drain worker-02 \
    --ignore-daemonsets \
    --delete-emptydir-data
```

- `--ignore-daemonsets` — DaemonSet pods (like Cilium agents) cannot be evicted; this flag skips them
- `--delete-emptydir-data` — allows evicting pods that use `emptyDir` volumes (data is lost — expected for stateless pods)

Watch the second terminal: pods that were on worker-02 are terminated and rescheduled onto worker-01 and worker-03.

### 1.4 Verify

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl get pods -l app=drain-test -o wide
```

No pods should appear on worker-02. worker-01 and worker-03 now carry all 6 replicas.

### 1.5 Perform maintenance (simulated)

In a real scenario you would now SSH into worker-02 and perform your OS patch or hardware operation. Here we simulate it:

> 🖥️ **Run on bootstrap (vm1).**

```bash
echo "Simulating maintenance on worker-02..."
sleep 5
echo "Maintenance complete."
```

### 1.6 Uncordon worker-02

When maintenance is complete, return the node to service:

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl uncordon worker-02
kubectl get nodes
```

worker-02 returns to `Ready`. Now scale up to trigger rescheduling onto the returned node:

```bash
kubectl scale deployment drain-test --replicas=9
kubectl get pods -l app=drain-test -o wide
```

New pods land on worker-02 — it is back in rotation.

### 1.7 Clean up

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl delete deployment drain-test
```

---

## Part 2 — Taints and tolerations

::image-box
---
:src: __static__/kubectl-drain-v1.png
:alt: 'kubectl get nodes showing worker-02 in Ready,SchedulingDisabled state after cordon'
---
_⚠️ Placeholder — replace with real playground screenshot before course launch._
::

**Taints** prevent pods from being scheduled onto a node unless the pod explicitly **tolerates** the taint. Used to:
- Reserve nodes for specific workloads (GPU, high-memory)
- Mark nodes as degraded or under maintenance
- Enforce placement constraints without affinity rules

### 2.1 Taint a node

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl taint node worker-03 dedicated=gpu:NoSchedule
```

Format: `key=value:effect`

| Effect | Behavior |
|---|---|
| `NoSchedule` | New pods without the toleration are not scheduled here |
| `PreferNoSchedule` | Scheduler avoids this node but will use it if no other option exists |
| `NoExecute` | New pods blocked AND existing pods without toleration are evicted |

### 2.2 Verify the taint is applied

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl describe node worker-03 | grep -A5 Taints
```

Expected output:

```
Taints: dedicated=gpu:NoSchedule
```

### 2.3 Deploy without a toleration

> 🖥️ **Run on bootstrap (vm1).** Deploy and observe where pods land.

```bash
kubectl create deployment no-toleration --image=nginx:alpine --replicas=9
kubectl get pods -l app=no-toleration -o wide
```

No pods land on worker-03 — they all go to worker-01 and worker-02. worker-03 is reserved.

### 2.4 Deploy with a toleration

Create the manifest file, then apply it:

> 🖥️ **Run on bootstrap (vm1).**

```bash
cat > toleration-deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: with-toleration
spec:
  replicas: 3
  selector:
    matchLabels:
      app: with-toleration
  template:
    metadata:
      labels:
        app: with-toleration
    spec:
      tolerations:
        - key: dedicated
          operator: Equal
          value: gpu
          effect: NoSchedule
      containers:
        - name: nginx
          image: nginx:alpine
EOF
kubectl apply -f toleration-deploy.yaml
kubectl get pods -l app=with-toleration -o wide
```

These pods **can** land on worker-03. They may also land on worker-01/worker-02 — tolerations *allow* scheduling on a tainted node, they do not *force* it.

### 2.5 Force pods onto the tainted node (nodeSelector)

To force pods exclusively onto worker-03, combine the toleration with a nodeSelector:

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl patch deployment with-toleration --type=json -p='[
  {"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"worker-03"}}
]'
kubectl get pods -l app=with-toleration -o wide
```

All pods now run exclusively on worker-03.

### 2.6 Remove the taint

> 🖥️ **Run on bootstrap (vm1).** The trailing `-` removes the taint.

```bash
kubectl taint node worker-03 dedicated=gpu:NoSchedule-
kubectl describe node worker-03 | grep Taints
```

Expected output:

```
Taints: <none>
```

### 2.7 Clean up

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl delete deployment no-toleration with-toleration
rm toleration-deploy.yaml
```

---

## Part 3 — PodDisruptionBudget

::image-box
---
:src: __static__/kubectl-drain-v1.png
:alt: 'kubectl uncordon worker-02 output followed by kubectl get nodes showing worker-02 back to Ready status'
---
_⚠️ Placeholder — replace with real playground screenshot before course launch._
::

A **PodDisruptionBudget (PDB)** limits how many pods of a deployment can be down simultaneously during voluntary disruptions (drain, rolling update). It prevents a drain from taking down more replicas than your application can tolerate.

### 3.1 Deploy an app

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl create deployment pdb-app --image=nginx:alpine --replicas=4
kubectl get pods -l app=pdb-app -o wide
```

### 3.2 Create a PDB — minimum 3 pods always available

> 🖥️ **Run on bootstrap (vm1).** Create the PDB manifest and apply it.

```bash
cat > pdb.yaml <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pdb-app
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: pdb-app
EOF
kubectl apply -f pdb.yaml
kubectl get pdb
```

Expected output:

```
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
pdb-app   3               N/A               1                     5s
```

`ALLOWED DISRUPTIONS: 1` — only one pod can be disrupted at a time.

### 3.3 Test drain with PDB active

> 🖥️ **Run on bootstrap (vm1).** Watch how the drain respects the PDB.

```bash
kubectl drain worker-01 --ignore-daemonsets --delete-emptydir-data
```

The drain evicts one pod at a time, waiting for it to reschedule before evicting the next. If evicting a pod would violate the PDB, drain blocks and waits until a replacement is Running.

### 3.4 Uncordon and clean up

> 🖥️ **Run on bootstrap (vm1).**

```bash
kubectl uncordon worker-01
kubectl delete deployment pdb-app
kubectl delete pdb pdb-app
rm pdb.yaml
```

---

## Summary

| Operation | Command | When to use |
|---|---|---|
| Mark node unschedulable | `kubectl cordon <node>` | Before maintenance |
| Evict all pods from node | `kubectl drain <node> --ignore-daemonsets` | Before OS patch / shutdown |
| Return node to service | `kubectl uncordon <node>` | After maintenance complete |
| Add a taint | `kubectl taint node <node> key=value:effect` | Reserve node for specific workloads |
| Remove a taint | `kubectl taint node <node> key=value:effect-` | Release node |
| Protect availability during drain | `kubectl apply -f pdb.yaml` | Stateful / critical apps |

---

## Next steps

➡️ [Module 4, Lesson 3 — Node Failure: Simulating and Recovering from a Node Loss](../3.lesson-node-failure/unit-1.md)
