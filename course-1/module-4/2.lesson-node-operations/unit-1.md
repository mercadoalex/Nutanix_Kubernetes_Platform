---
kind: unit
title: "Lesson 4.2 — Node Operations: drain, cordon, taints, and tolerations"
name: 2-lesson-node-operations-unit-1
---

# Lesson 4.2 — Node Operations: drain, cordon, taints, and tolerations

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running across vm2–vm5
> **Duration:** ~40 minutes

---

## What you will do

Safely take nodes in and out of service — the operations you perform during OS patching, hardware maintenance, and rolling cluster upgrades:

- **cordon** — mark a node unschedulable (no new pods land here)
- **drain** — evict all running pods from a node gracefully
- **uncordon** — return a node to service
- **taints & tolerations** — restrict which pods can run on which nodes

All commands run from **vm1** against the live cluster.

---

## Lab topology reminder

```
vm2  172.16.0.11   control plane
vm3  172.16.0.12   worker-01
vm4  172.16.0.13   worker-02
vm5  172.16.0.14   worker-03
```

---

## Part 1 — cordon and drain

### 1.1 Deploy a test workload spread across workers

```bash
kubectl create deployment drain-test --image=nginx:alpine --replicas=6
kubectl get pods -l app=drain-test -o wide
```

Confirm pods are spread across vm3, vm4, and vm5.

### 1.2 Cordon vm4

Cordoning marks a node **unschedulable** — the scheduler will not place new pods on it. Existing pods are not evicted.

```bash
kubectl cordon vm4
kubectl get nodes
```

```
NAME   STATUS                     ROLES                       AGE
vm2    Ready                      control-plane,etcd,master   1h
vm3    Ready                      <none>                      1h
vm4    Ready,SchedulingDisabled   <none>                      1h
vm5    Ready                      <none>                      1h
```

`SchedulingDisabled` — vm4 is cordoned. Existing pods on vm4 are still running.

```bash
kubectl get pods -l app=drain-test -o wide
```

Pods on vm4 are untouched. Only new pods are blocked from landing there.

### 1.3 Drain vm4

Drain evicts all non-daemonset, non-mirror pods from a node gracefully. Each pod is given a chance to terminate cleanly before it is killed.

```bash
kubectl drain vm4 \
    --ignore-daemonsets \
    --delete-emptydir-data
```

- `--ignore-daemonsets` — DaemonSet pods (like Cilium agents) cannot be evicted; this flag skips them
- `--delete-emptydir-data` — allows evicting pods that use `emptyDir` volumes (data is lost — expected for stateless pods)

Watch pods reschedule in real time in a second terminal:

```bash
kubectl get pods -l app=drain-test -o wide -w
```

Pods that were on vm4 are terminated and rescheduled onto vm3 and vm5.

### 1.4 Verify

```bash
kubectl get pods -l app=drain-test -o wide
```

No pods on vm4. vm3 and vm5 carry the full 6 replicas.

### 1.5 Perform maintenance (simulated)

```bash
# On vm4 — simulate an OS patch
echo "Patching vm4..."
sleep 5
echo "Done"
```

### 1.6 Uncordon vm4

```bash
kubectl uncordon vm4
kubectl get nodes
```

vm4 returns to `Ready`. The scheduler can now place new pods on it again.

Scale the deployment up to trigger rescheduling onto vm4:

```bash
kubectl scale deployment drain-test --replicas=9
kubectl get pods -l app=drain-test -o wide
```

New pods land on vm4.

### 1.7 Clean up

```bash
kubectl delete deployment drain-test
```

---

## Part 2 — Taints and tolerations

**Taints** prevent pods from being scheduled onto a node unless the pod explicitly **tolerates** the taint. Used to:
- Reserve nodes for specific workloads (GPU, high-memory)
- Mark nodes as degraded or under maintenance
- Enforce placement constraints without affinity rules

### 2.1 Taint a node

```bash
kubectl taint node vm5 dedicated=gpu:NoSchedule
```

Format: `key=value:effect`

| Effect | Behavior |
|---|---|
| `NoSchedule` | New pods without the toleration are not scheduled here |
| `PreferNoSchedule` | Scheduler avoids this node but will use it if no other option exists |
| `NoExecute` | New pods blocked AND existing pods without toleration are evicted |

### 2.2 Verify the taint is applied

```bash
kubectl describe node vm5 | grep -A5 Taints
```

```
Taints: dedicated=gpu:NoSchedule
```

### 2.3 Deploy without a toleration

```bash
kubectl create deployment no-toleration --image=nginx:alpine --replicas=9
kubectl get pods -l app=no-toleration -o wide
```

No pods land on vm5 — they all go to vm3 and vm4. vm5 is reserved.

### 2.4 Deploy with a toleration

```yaml
# toleration-deploy.yaml
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
```

```bash
kubectl apply -f toleration-deploy.yaml
kubectl get pods -l app=with-toleration -o wide
```

These pods **can** land on vm5. They may also land on vm3/vm4 — tolerations allow scheduling on a tainted node, they do not force it. To force pods onto a specific node, combine a toleration with a **nodeSelector** or **nodeAffinity**.

### 2.5 Force pods onto the tainted node (nodeSelector)

```bash
kubectl patch deployment with-toleration --type=json -p='[
  {"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"vm5"}}
]'
kubectl get pods -l app=with-toleration -o wide
```

All pods now run exclusively on vm5.

### 2.6 Remove the taint

```bash
kubectl taint node vm5 dedicated=gpu:NoSchedule-
```

The trailing `-` removes the taint.

```bash
kubectl describe node vm5 | grep Taints
```

```
Taints: <none>
```

### 2.7 Clean up

```bash
kubectl delete deployment no-toleration with-toleration
```

---

## Part 3 — PodDisruptionBudget

A **PodDisruptionBudget (PDB)** limits how many pods of a deployment can be down simultaneously during voluntary disruptions (drain, rolling update). It prevents a drain from taking down more replicas than your application can tolerate.

### 3.1 Deploy an app

```bash
kubectl create deployment pdb-app --image=nginx:alpine --replicas=4
```

### 3.2 Create a PDB — minimum 3 pods always available

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: pdb-app
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: pdb-app
```

```bash
kubectl apply -f pdb.yaml
kubectl get pdb
```

```
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
pdb-app   3               N/A               1                     5s
```

`ALLOWED DISRUPTIONS: 1` — only one pod can be disrupted at a time.

### 3.3 Test drain with PDB active

```bash
kubectl drain vm3 --ignore-daemonsets --delete-emptydir-data
```

The drain proceeds but respects the PDB — it evicts one pod at a time, waiting for it to reschedule before evicting the next. If the PDB would be violated, drain blocks and waits.

### 3.4 Uncordon and clean up

```bash
kubectl uncordon vm3
kubectl delete deployment pdb-app
kubectl delete pdb pdb-app
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
