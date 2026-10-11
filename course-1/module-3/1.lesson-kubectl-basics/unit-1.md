---
kind: unit
title: "Lesson 05 — kubectl Basics: Day-2 Cluster Operations"
name: 1.lesson-kubectl-basics-unit-1
---

# Lesson 05 — kubectl Basics: Day-2 Cluster Operations

> **Tier:** 2 — Single-VM interactive  
> **Playground:** single vm1 (bootstrap image, pre-loaded cluster kubeconfig)  
> **VMs used:** vm1 only  
> **Duration:** ~30 minutes

---

## What you will do

You have a running cluster and a kubeconfig. Now learn the `kubectl` commands you will use every single day — inspecting resources, reading logs, executing into containers, and understanding what is happening inside the cluster.

This lesson uses the pre-loaded cluster (Management Cluster, 4 nodes). No new infrastructure is needed.

---

## Part 1 — The kubectl mental model

Every Kubernetes resource lives in a **namespace** (or is cluster-scoped). The `kubectl` command follows a consistent pattern:

```
kubectl <verb> <resource-type> <name> [flags]
         get    pod             nginx   -n kube-system
         describe
         logs
         exec
         delete
         apply
         edit
```

The most important flag: `-n <namespace>` (or `--namespace`). Without it, `kubectl` defaults to the `default` namespace and you miss 90% of what is running.

---

## Part 2 — Namespaces

### 2.1 List all namespaces

```bash
kubectl get namespaces
```

```
NAME              STATUS   AGE
default           Active   2h
kube-node-lease   Active   2h
kube-public       Active   2h
kube-system       Active   2h
```

In a cluster with Kommander deployed you would also see `kommander`, `kommander-flux`, `cert-manager`, `monitoring`, etc.

### 2.2 See everything in a namespace

```bash
kubectl get all -n kube-system
```

### 2.3 See everything across all namespaces

```bash
kubectl get pods -A
```

`-A` is short for `--all-namespaces`. This is your first "what is running?" command.

---

## Part 3 — Pods

### 3.1 List pods

```bash
kubectl get pods -n kube-system
```

### 3.2 Get more detail

```bash
kubectl get pods -n kube-system -o wide
```

`-o wide` adds the node name and pod IP — essential for understanding placement.

### 3.3 Describe a pod

`describe` is your primary debugging tool. It shows events, resource limits, image, volumes, and conditions:

```bash
# Pick any running pod name from the previous output
kubectl describe pod <pod-name> -n kube-system
```

Key sections to read in describe output:

| Section | What to look for |
|---|---|
| `Status` | Should be `Running` |
| `Conditions` | All should be `True` |
| `Events` | Most recent events at the bottom — errors appear here first |
| `Containers` → `State` | `Running` + `Started` timestamp |
| `Containers` → `Last State` | Shows if the container has restarted and why |

### 3.4 Watch pods in real time

```bash
kubectl get pods -n kube-system -w
```

`-w` streams updates. Press `Ctrl+C` to stop. Useful when deploying something and waiting for `Running`.

### 3.5 Deploy a test pod

```bash
kubectl run test --image=nginx:alpine --restart=Never
kubectl get pod test -w
```

Wait for `Running`:

```
NAME   READY   STATUS              RESTARTS   AGE
test   0/1     ContainerCreating   0          3s
test   1/1     Running             0          8s
```

---

## Part 4 — Logs

### 4.1 Read pod logs

```bash
kubectl logs test
```

### 4.2 Follow logs in real time

```bash
kubectl logs test -f
```

`-f` streams new lines as they are written. Press `Ctrl+C` to stop.

### 4.3 Logs for a previous container instance

If a container has restarted, read the logs from the previous run:

```bash
kubectl logs <pod-name> -n kube-system --previous
```

### 4.4 Logs from a specific container in a multi-container pod

```bash
kubectl logs <pod-name> -n kube-system -c <container-name>
```

List the containers in a pod first:

```bash
kubectl get pod <pod-name> -n kube-system -o jsonpath='{.spec.containers[*].name}'
```

---

## Part 5 — Executing into containers

### 5.1 Open an interactive shell

```bash
kubectl exec -it test -- /bin/sh
```

You are now inside the running `nginx` container. Try:

```sh
# Inside the container
hostname
cat /etc/nginx/nginx.conf
curl localhost
exit
```

### 5.2 Run a one-shot command

```bash
kubectl exec test -- nginx -v
```

```
nginx version: nginx/1.27.x
```

### 5.3 Copy files in/out of a container

```bash
# Copy a file from the container to your local machine
kubectl cp test:/etc/nginx/nginx.conf ./nginx.conf

# Copy a file into the container
kubectl cp ./nginx.conf test:/tmp/nginx.conf
```

---

## Part 6 — Applying and managing resources

### 6.1 Apply a manifest

`kubectl apply` is the idempotent way to create or update resources. It is what Flux uses under the hood for every GitOps reconciliation.

Save this to `nginx-deploy.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
```

Apply it:

```bash
kubectl apply -f nginx-deploy.yaml
```

```
deployment.apps/nginx-deploy created
```

Apply it again — no change:

```bash
kubectl apply -f nginx-deploy.yaml
```

```
deployment.apps/nginx-deploy unchanged
```

### 6.2 Watch the rollout

```bash
kubectl rollout status deployment/nginx-deploy
```

```
deployment "nginx-deploy" successfully rolled out
```

### 6.3 Scale the deployment

```bash
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods -l app=nginx -w
```

Watch two new pods appear. Verify they are spread across nodes:

```bash
kubectl get pods -l app=nginx -o wide
```

### 6.4 Edit a resource live

```bash
kubectl edit deployment nginx-deploy
```

This opens the live resource in your `$EDITOR`. Any save triggers an immediate reconciliation.

### 6.5 Delete resources

```bash
kubectl delete -f nginx-deploy.yaml
kubectl delete pod test
```

Or by label:

```bash
kubectl delete pods -l app=nginx
```

---

## Part 7 — Events and troubleshooting

### 7.1 Cluster-wide events

Events are Kubernetes' audit log. When something goes wrong, events tell you what happened:

```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

Filter to only warnings:

```bash
kubectl get events -A --field-selector type=Warning
```

### 7.2 Describe a node

```bash
kubectl describe node vm3
```

Key sections:

| Section | What to check |
|---|---|
| `Conditions` | `Ready=True`, `MemoryPressure=False`, `DiskPressure=False` |
| `Allocatable` | Available CPU/memory for scheduling |
| `Non-terminated Pods` | What is currently running on this node |
| `Events` | Node-level events (kubelet restarts, network issues) |

### 7.3 Check resource usage

```bash
kubectl top nodes
kubectl top pods -A
```

> ℹ️ Requires the `metrics-server` to be running. On this lab cluster it is deployed as part of RKE2 (`rke2-metrics-server`).

---

## Part 8 — Output formats

`kubectl` supports multiple output formats via `-o`:

```bash
# Wide table (extra columns)
kubectl get nodes -o wide

# YAML — full resource definition
kubectl get pod test -o yaml

# JSON
kubectl get pod test -o json

# Custom columns
kubectl get pods -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName'

# JSONPath — extract a single field
kubectl get node vm2 -o jsonpath='{.status.nodeInfo.kubeletVersion}'
```

---

## Clean up

```bash
kubectl delete deployment nginx-deploy --ignore-not-found
kubectl delete pod test --ignore-not-found
```

---

## Summary

| Task | Command |
|---|---|
| List all pods across all namespaces | `kubectl get pods -A` |
| Describe a resource | `kubectl describe <type> <name> -n <ns>` |
| Read pod logs | `kubectl logs <pod> -n <ns> -f` |
| Shell into a container | `kubectl exec -it <pod> -- /bin/sh` |
| Apply a manifest | `kubectl apply -f <file.yaml>` |
| Scale a deployment | `kubectl scale deployment <name> --replicas=<n>` |
| Watch events | `kubectl get events -A --sort-by='.lastTimestamp'` |
| Resource usage | `kubectl top nodes` / `kubectl top pods -A` |

---

## Next steps

➡️ [Lesson 06 — Bootstrap & Pivot: Building the Management Cluster](../../module-4/1.lesson-bootstrap-pivot/unit-1.md)
