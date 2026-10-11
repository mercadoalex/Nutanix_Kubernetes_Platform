---
kind: unit
title: "Lesson 4.3 — Node Failure: Simulating and Recovering from a Node Loss"
name: 3.lesson-node-failure-unit-1
---

# Lesson 4.3 — Node Failure: Simulating and Recovering from a Node Loss

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running across vm2–vm5
> **Duration:** ~30 minutes

---

## What you will do

Kill a worker node and observe Kubernetes self-heal the cluster:

1. Deploy a workload spread across all workers
2. Abruptly stop vm4 — simulating a hardware failure
3. Watch Kubernetes detect the failure and reschedule pods
4. Bring vm4 back and watch it rejoin cleanly

This is the capstone of Module 4 — combining everything from Lessons 4.1 and 4.2 into a real failure scenario.

---

## Lab topology

```
vm2  172.16.0.11   control plane   (do not touch)
vm3  172.16.0.12   worker-01
vm4  172.16.0.13   worker-02       ← this is the node we will kill
vm5  172.16.0.14   worker-03
```

---

## Part 1 — Deploy a workload

### 1.1 Create a Deployment with a PodDisruptionBudget

```yaml
# failure-test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: failure-test
spec:
  replicas: 6
  selector:
    matchLabels:
      app: failure-test
  template:
    metadata:
      labels:
        app: failure-test
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: failure-test
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: failure-test-pdb
spec:
  minAvailable: 4
  selector:
    matchLabels:
      app: failure-test
```

```bash
kubectl apply -f failure-test.yaml
kubectl get pods -l app=failure-test -o wide
```

`topologySpreadConstraints` ensures pods are spread evenly across nodes — 2 pods per worker node.

```
NAME                            READY   NODE   ...
failure-test-xxx-aaa            1/1     vm3
failure-test-xxx-bbb            1/1     vm3
failure-test-xxx-ccc            1/1     vm4
failure-test-xxx-ddd            1/1     vm4
failure-test-xxx-eee            1/1     vm5
failure-test-xxx-fff            1/1     vm5
```

### 1.2 Open a watch in a second terminal

Keep this running throughout the exercise:

```bash
kubectl get pods -l app=failure-test -o wide -w
```

---

## Part 2 — Kill vm4

Switch to the **vm4** terminal and abruptly stop the RKE2 agent. This simulates a hard node failure — no graceful drain, no cordon.

```bash
# On vm4 — simulate a hard failure
systemctl stop rke2-agent
# Optionally make it more dramatic:
# ip link set eth0 down
```

> ℹ️ In a real failure scenario (power loss, kernel panic, network partition), the node simply disappears. Stopping the agent achieves the same effect from Kubernetes' perspective.

---

## Part 3 — Watch Kubernetes respond

Back on **vm1**, watch what happens:

### 3.1 Node status changes

```bash
kubectl get nodes -w
```

```
NAME   STATUS     ROLES    AGE
vm2    Ready      master   2h
vm3    Ready      <none>   2h
vm4    Ready      <none>   2h     ← still Ready initially
vm5    Ready      <none>   2h
...
vm4    NotReady   <none>   2h     ← after ~40 seconds
```

Kubernetes uses a **node lease** heartbeat. The kubelet on vm4 stops sending heartbeats when the agent stops. After the `node-monitor-grace-period` (default **40 seconds**), the Node Controller marks vm4 `NotReady`.

### 3.2 Pods are evicted

After the node becomes `NotReady`, the pod eviction timer starts. After `pod-eviction-timeout` (default **5 minutes** in standard Kubernetes — RKE2 uses a shorter default), pods on vm4 are marked `Terminating`:

```bash
kubectl get pods -l app=failure-test -o wide
```

```
NAME                  READY   STATUS        NODE
failure-test-xxx-aaa  1/1     Running       vm3
failure-test-xxx-bbb  1/1     Running       vm3
failure-test-xxx-ccc  1/1     Terminating   vm4   ← evicted
failure-test-xxx-ddd  1/1     Terminating   vm4   ← evicted
failure-test-xxx-eee  1/1     Running       vm5
failure-test-xxx-fff  1/1     Running       vm5
failure-test-xxx-ggg  0/1     Pending       <none> ← replacement
failure-test-xxx-hhh  0/1     Pending       <none> ← replacement
```

The Deployment controller sees fewer than 6 replicas and creates replacements. They start `Pending` until they are scheduled onto vm3 or vm5.

### 3.3 Replacements become Running

```bash
kubectl get pods -l app=failure-test -o wide
```

```
NAME                  READY   STATUS    NODE
failure-test-xxx-aaa  1/1     Running   vm3
failure-test-xxx-bbb  1/1     Running   vm3
failure-test-xxx-eee  1/1     Running   vm5
failure-test-xxx-fff  1/1     Running   vm5
failure-test-xxx-ggg  1/1     Running   vm3   ← rescheduled
failure-test-xxx-hhh  1/1     Running   vm5   ← rescheduled
```

All 6 replicas are running. The cluster is self-healed. vm4 is gone from the picture.

### 3.4 Check events

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

Key events to find:
- `NodeNotReady` — node controller detected the failure
- `TaintManagerEviction` — pods evicted from the unreachable node
- `SuccessfulCreate` — replacement pods created by the Deployment controller
- `Scheduled` — replacement pods placed on healthy nodes

---

## Part 4 — Recover vm4

### 4.1 Restart the RKE2 agent on vm4

Switch to the **vm4** terminal:

```bash
systemctl start rke2-agent
```

Watch the node rejoin on **vm1**:

```bash
kubectl get nodes -w
```

```
vm4    NotReady   <none>   2h
vm4    Ready      <none>   2h    ← rejoined after ~30 seconds
```

### 4.2 Check vm4's status

```bash
kubectl describe node vm4 | grep -A10 Conditions
```

All conditions should return to `True` / `False` normal values.

### 4.3 Verify no lingering Terminating pods

```bash
kubectl get pods -l app=failure-test -o wide
```

The stale `Terminating` pods from vm4 are cleaned up once the node rejoins and the kubelet confirms the pods are gone.

### 4.4 Rebalance pods (optional)

The scheduler does not proactively move pods back to vm4 after recovery — that would cause unnecessary churn. If you want to rebalance:

```bash
kubectl rollout restart deployment/failure-test
kubectl get pods -l app=failure-test -o wide
```

Pods are now redistributed evenly across vm3, vm4, and vm5.

---

## Part 5 — Key timers explained

| Timer | Default | What triggers it |
|---|---|---|
| Node heartbeat interval | 10s | kubelet sends a lease heartbeat to the API server |
| `node-monitor-grace-period` | 40s | After missing heartbeats for this long, node is marked `NotReady` |
| Pod eviction timeout | 5min (K8s default) / ~1min (RKE2 tuned) | After `NotReady` for this long, pods are evicted |
| Pod termination grace period | 30s | Time given to each pod for graceful shutdown before SIGKILL |

In production NKP clusters you may tune these values down for faster recovery (at the cost of more false-positive evictions on transient network blips).

---

## Clean up

```bash
kubectl delete -f failure-test.yaml
```

---

## Summary

| Event | What Kubernetes does | Time |
|---|---|---|
| Node stops heartbeating | Waits for grace period | 0–40s |
| Grace period expires | Marks node `NotReady`, adds `NoExecute` taint | ~40s |
| Eviction timeout expires | Evicts pods from `NotReady` node | ~40s–5min |
| Deployment sees fewer replicas | Creates replacement pods | Immediate |
| Replacement pods scheduled | Scheduler places them on healthy nodes | Seconds |
| Node rejoins | Node `Ready`, stale pods cleaned up | ~30s after agent restart |

---

## Next steps

➡️ [Module 5, Lesson 1 — Add-ons Catalog: Deploying Platform Services with Flux](../../module-5/1.lesson-addons-catalog/unit-1.md)
