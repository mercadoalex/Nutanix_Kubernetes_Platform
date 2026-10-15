---
kind: unit
title: "Lesson 04 — The NKP CLI: kubeconfig, Contexts, and Cluster Access"
name: 4-lesson-nkp-cli-unit-1
---

# Lesson 04 — The NKP CLI: kubeconfig, Contexts, and Cluster Access

> **Tier:** 2 — Single-VM interactive  
> **Playground:** single vm1 (bootstrap image, pre-loaded cluster kubeconfig)  
> **VMs used:** vm1 only  
> **Duration:** ~20 minutes

---

## What you will do

After `nkp create cluster` succeeds, your first practical task is always the same: **get a kubeconfig and connect to the cluster**. This lesson covers the `nkp` CLI commands you use for that, plus how to manage multiple cluster contexts so you never accidentally run a command against the wrong cluster.

---

## Version reference

| Tool | Version |
|---|---|
| `nkp` CLI | 2.17.1 |
| `kubectl` | 1.34.3 |

---

## Part 1 — The `nkp` CLI

::image-box
---
:src: __static__/placeholder-nkp-help-output.png
:alt: 'Terminal showing nkp --help output listing all top-level subcommands'
---
_TODO: Replace with actual screenshot — Terminal output of `nkp --help` showing the full list of top-level commands (create, delete, get, move, describe, check, etc.) with their one-line descriptions_
::

### 1.1 Verify the installation

```bash
nkp version
```

```
v2.17.1
```

### 1.2 Explore top-level commands

```bash
nkp --help
```

The commands you will use most often:

| Command | What it does |
|---|---|
| `nkp create bootstrap` | Create the temporary kind Bootstrap Cluster |
| `nkp create cluster` | Provision a new Managed Cluster (requires Prism Central) |
| `nkp get kubeconfig` | Download a cluster's kubeconfig from Kommander |
| `nkp move` | Pivot CAPI controllers from Bootstrap → Management Cluster |
| `nkp delete bootstrap` | Tear down the Bootstrap Cluster |
| `nkp describe cluster` | Show cluster health and component status |

### 1.3 Get help for any subcommand

```bash
nkp get --help
nkp create cluster --help | head -60
```

The `--help` output for `nkp create cluster` lists every flag — the most important ones are documented in the [nkp-quickstart repo](https://github.com/nutanixdev/nkp-quickstart/blob/main/nkp-create-mgmt-cluster.sh).

---

## Part 2 — Getting a kubeconfig

::image-box
---
:src: __static__/placeholder-nkp-get-kubeconfig-output.png
:alt: 'Terminal showing nkp get kubeconfig command writing YAML to a file successfully'
---
_TODO: Replace with actual screenshot — Terminal running `nkp get kubeconfig --cluster-name=nkp-lab > ~/clusters/nkp-lab.kubeconfig` followed by `kubectl --kubeconfig ... get nodes` returning all nodes Ready_
::

In production, after `nkp create cluster` completes you retrieve the kubeconfig with:

```bash
nkp get kubeconfig --cluster-name=<name> > ~/clusters/<name>.kubeconfig
```

This command connects to the **Management Cluster** (which hosts Kommander) and pulls the kubeconfig for the named cluster. It works for both Management Clusters and Workload Clusters.

For this lesson a kubeconfig is already pre-loaded at:

```bash
ls ~/.kube/
```

```
config          # default kubeconfig — points at the pre-loaded lab cluster
mgmt.kubeconfig # named kubeconfig for the management cluster
```

### 2.1 Inspect the kubeconfig

```bash
cat ~/.kube/config
```

Key sections:

```yaml
clusters:
  - name: nkp-lab
    cluster:
      server: https://172.16.0.11:6443   # API server endpoint
      certificate-authority-data: ...     # base64 CA cert

users:
  - name: nkp-lab-admin
    user:
      client-certificate-data: ...        # client cert (admin)
      client-key-data: ...                # client key

contexts:
  - name: nkp-lab
    context:
      cluster: nkp-lab
      user: nkp-lab-admin
      namespace: default

current-context: nkp-lab
```

A kubeconfig can hold **many clusters, users, and contexts**. A **context** is a named triple of (cluster, user, namespace). `current-context` is where `kubectl` sends commands by default.

---

## Part 3 — Managing contexts

### 3.1 List all contexts

```bash
kubectl config get-contexts
```

```
CURRENT   NAME       CLUSTER    AUTHINFO         NAMESPACE
*         nkp-lab    nkp-lab    nkp-lab-admin    default
```

The `*` marks the active context.

### 3.2 Switch context

If you have multiple clusters loaded into one kubeconfig:

```bash
kubectl config use-context <context-name>
```

### 3.3 Use a named kubeconfig file

Rather than merging all clusters into `~/.kube/config`, keep a separate file per cluster — safer in a multi-cluster environment:

```bash
# One-time export
export KUBECONFIG=~/.kube/mgmt.kubeconfig

# Or per-command
kubectl --kubeconfig ~/.kube/mgmt.kubeconfig get nodes
```

### 3.4 Merge two kubeconfigs

When you download a second cluster's kubeconfig and want both in one file:

```bash
KUBECONFIG=~/.kube/config:~/.kube/workload-01.kubeconfig \
    kubectl config view --flatten > ~/.kube/merged.kubeconfig
mv ~/.kube/merged.kubeconfig ~/.kube/config
```

> ⚠️ Always verify the merge with `kubectl config get-contexts` before deleting the originals.

---

## Part 4 — Cluster identity commands

::image-box
---
:src: __static__/placeholder-nkp-describe-cluster-output.png
:alt: 'Terminal showing nkp describe cluster output with component health status'
---
_TODO: Replace with actual screenshot — Terminal output of `nkp describe cluster --cluster-name=nkp-lab` showing the cluster health summary: CAPI object status, Flux reconciliation status, and add-on health indicators_
::

These are the first commands to run after connecting to any cluster to confirm you are talking to the right one.

### 4.1 Confirm which cluster you are connected to

```bash
kubectl cluster-info
```

```
Kubernetes control plane is running at https://172.16.0.11:6443
CoreDNS is running at https://172.16.0.11:6443/api/v1/namespaces/kube-system/...
```

### 4.2 Check the server version

```bash
kubectl version
```

```
Client Version: v1.34.3
Server Version: v1.34.3+rke2r1
```

RKE2 appends `+rke2r1` to the server version. The client and server minor versions must match (or be within one minor version of each other).

### 4.3 List nodes

```bash
kubectl get nodes -o wide
```

```
NAME   STATUS   ROLES                       AGE   VERSION           INTERNAL-IP    OS-IMAGE
vm2    Ready    control-plane,etcd,master   1h    v1.34.3+rke2r1   172.16.0.11    Rocky Linux 9.7
vm3    Ready    <none>                      1h    v1.34.3+rke2r1   172.16.0.12    Rocky Linux 9.7
vm4    Ready    <none>                      1h    v1.34.3+rke2r1   172.16.0.13    Rocky Linux 9.7
vm5    Ready    <none>                      1h    v1.34.3+rke2r1   172.16.0.14    Rocky Linux 9.7
```

### 4.4 `nkp describe cluster`

When Kommander is deployed, use `nkp describe cluster` to see a health summary across all components (CAPI objects, Flux reconciliation status, add-on health). This is the NKP-level health check, above the raw `kubectl` view:

```bash
nkp describe cluster --cluster-name=nkp-lab
```

> 📺 Full output requires Kommander to be deployed. The lab cluster has the core RKE2 cluster but not the full Kommander stack — this command is shown here for reference.

---

## Part 5 — Shell productivity

These are already configured in the bootstrap image but worth knowing explicitly.

### 5.1 Tab completion

```bash
# Already in /etc/bash.bashrc — just verify it works
kubectl get <TAB><TAB>
nkp <TAB><TAB>
```

### 5.2 The `k` alias

```bash
alias k=kubectl
k get nodes
```

### 5.3 Always-visible context prompt

Add this to `~/.bashrc` to see the active context in your shell prompt — prevents accidentally running commands against the wrong cluster:

```bash
parse_k8s_context() {
    if command -v kubectl &>/dev/null; then
        ctx=$(kubectl config current-context 2>/dev/null)
        [[ -n "$ctx" ]] && echo "($ctx) "
    fi
}
PS1='\u@\h \W $(parse_k8s_context)$ '
```

---

## Summary

::image-box
---
:src: __static__/placeholder-kommander-cluster-list.png
:alt: 'Kommander UI cluster list page showing registered clusters with their status'
---
_TODO: Replace with actual screenshot — Kommander → Clusters page listing nkp-management and any attached workload clusters, showing cluster name, status (Ready), Kubernetes version, and node count columns_
::

| Task | Command |
|---|---|
| Get cluster kubeconfig | `nkp get kubeconfig --cluster-name=<name> > cluster.kubeconfig` |
| List contexts | `kubectl config get-contexts` |
| Switch context | `kubectl config use-context <name>` |
| Use specific kubeconfig | `export KUBECONFIG=~/.kube/mgmt.kubeconfig` |
| Confirm cluster endpoint | `kubectl cluster-info` |
| Check versions | `kubectl version` |
| List nodes | `kubectl get nodes -o wide` |

---

## Next steps

➡️ [Lesson 05 — kubectl Basics: Day-2 Cluster Operations](../../module-3/1.lesson-kubectl-basics/unit-1.md)
