---
kind: unit
title: "Lesson 5.1 — Add-ons Catalog: Deploying Platform Services with Flux"
name: 1-lesson-addons-catalog-unit-1
---

# Lesson 5.1 — Add-ons Catalog: Deploying Platform Services with Flux

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running
> **Duration:** ~45 minutes

---

## What you will do

NKP ships an **add-ons catalog** — a curated set of platform services deployed and managed via **Flux CD**. In this lesson you deploy two of them manually to understand the underlying mechanism:

1. **cert-manager** — automatic TLS certificate lifecycle management
2. **Longhorn** — distributed block storage across all worker nodes

Understanding how Flux `HelmRelease` and `HelmRepository` objects work is the foundation for Lesson 5.2 (full GitOps loop).

---

## How NKP add-ons work

```
NKP Kommander
  └─► creates HelmRepository (where to find charts)
       └─► creates HelmRelease (which chart + values to deploy)
            └─► Flux helm-controller reconciles
                 └─► Helm installs/upgrades the chart on the cluster
```

Every add-on is a `HelmRelease` CR. Flux continuously reconciles them — if someone manually deletes a chart, Flux reinstalls it. This is the GitOps guarantee.

---

## Part 1 — Install Flux CLI

Flux CLI is already installed on vm1 from the bootstrap image:

```bash
flux version
```

```
flux: v2.5.1
```

Check Flux controllers are running in the cluster:

```bash
kubectl get pods -n flux-system
```

> ℹ️ Flux is deployed as part of the NKP bootstrap. If the lab cluster was started fresh from Lesson 4.1, Flux may not be installed yet. Install it now:

```bash
flux install
kubectl get pods -n flux-system
```

```
NAME                                      READY   STATUS
helm-controller-xxx                       1/1     Running
kustomize-controller-xxx                  1/1     Running
notification-controller-xxx               1/1     Running
source-controller-xxx                     1/1     Running
```

---

## Part 2 — Deploy cert-manager

cert-manager automates TLS certificate issuance and renewal using Let's Encrypt, Vault, or self-signed CAs.

### 2.1 Create the HelmRepository

A `HelmRepository` tells Flux where to find Helm charts:

```yaml
# cert-manager-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: cert-manager
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

```bash
kubectl apply -f cert-manager-repo.yaml
kubectl get helmrepository -n flux-system
```

```
NAME           URL                          AGE   READY   STATUS
cert-manager   https://charts.jetstack.io   10s   True    stored artifact...
```

### 2.2 Create the HelmRelease

A `HelmRelease` declares which chart to install, at what version, with what values:

```yaml
# cert-manager-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 10m
  chart:
    spec:
      chart: cert-manager
      version: "1.16.x"
      sourceRef:
        kind: HelmRepository
        name: cert-manager
        namespace: flux-system
  install:
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
  values:
    crds:
      enabled: true
```

```bash
kubectl create namespace cert-manager
kubectl apply -f cert-manager-release.yaml
```

### 2.3 Watch Flux reconcile

```bash
flux get helmrelease -A
```

```
NAMESPACE      NAME          REVISION   SUSPENDED   READY   MESSAGE
cert-manager   cert-manager  1.16.3     False       True    Release reconciliation succeeded
```

```bash
kubectl get pods -n cert-manager
```

```
NAME                                      READY   STATUS
cert-manager-xxx                          1/1     Running
cert-manager-cainjector-xxx               1/1     Running
cert-manager-webhook-xxx                  1/1     Running
```

### 2.4 Create a self-signed ClusterIssuer

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
```

```bash
kubectl apply -f cluster-issuer.yaml
kubectl get clusterissuer
```

```
NAME         READY   AGE
selfsigned   True    5s
```

---

## Part 3 — Deploy Longhorn

Longhorn is a distributed block storage system. It creates replicated volumes across all worker nodes — so a PVC survives a worker node failure.

### 3.1 Longhorn prerequisites

Longhorn requires `open-iscsi` on every node. It is already enabled in the worker rootfs (the `iscsid.service` symlink in the Dockerfile). Verify:

```bash
# On each worker node (vm3, vm4, vm5)
systemctl is-active iscsid
```

```
active
```

### 3.2 HelmRepository and HelmRelease

```yaml
# longhorn.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: longhorn
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.longhorn.io
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 10m
  chart:
    spec:
      chart: longhorn
      version: "1.7.x"
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: flux-system
  values:
    defaultSettings:
      defaultReplicaCount: 2
    persistence:
      defaultClass: true
      defaultClassReplicaCount: 2
```

```bash
kubectl create namespace longhorn-system
kubectl apply -f longhorn.yaml
```

`defaultReplicaCount: 2` — each volume is replicated to 2 of the 3 workers. Tolerates one worker failure without data loss.

### 3.3 Wait for Longhorn to be ready

Longhorn takes 3–5 minutes to start — it deploys an instance manager and replica manager pod on every node:

```bash
flux get helmrelease -n longhorn-system -w
```

```bash
kubectl get pods -n longhorn-system
```

```
NAME                                   READY   STATUS
longhorn-manager-xxx (×3)              1/1     Running   ← one per worker
longhorn-driver-deployer-xxx           1/1     Running
longhorn-ui-xxx                        1/1     Running
instance-manager-xxx (×3)             1/1     Running
```

### 3.4 Verify the StorageClass

```bash
kubectl get storageclass
```

```
NAME                 PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE    DEFAULT
local-path           rancher.io/...       Delete          WaitForFirstConsumer
longhorn (default)   driver.longhorn.io   Delete          Immediate            ✅
```

Longhorn sets itself as the default StorageClass.

### 3.5 Test a Longhorn PVC

```yaml
# longhorn-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f longhorn-pvc.yaml
kubectl get pvc longhorn-test
```

```
NAME            STATUS   VOLUME           CAPACITY   STORAGECLASS
longhorn-test   Bound    pvc-abc123...    1Gi        longhorn
```

Check the volume is replicated across two nodes:

```bash
kubectl get volume -n longhorn-system
```

### 3.6 Clean up test PVC

```bash
kubectl delete pvc longhorn-test
```

---

## Part 4 — Inspect the Flux reconciliation loop

This is the core of how NKP manages add-ons:

```bash
# List all HelmReleases across all namespaces
flux get helmrelease -A

# List all HelmRepositories
flux get source helm -A

# Force an immediate reconciliation
flux reconcile helmrelease cert-manager -n cert-manager

# Suspend a HelmRelease (pause reconciliation — useful for debugging)
flux suspend helmrelease cert-manager -n cert-manager

# Resume
flux resume helmrelease cert-manager -n cert-manager
```

### 4.1 Break and watch Flux self-heal

Delete the cert-manager deployment directly — bypassing Flux:

```bash
kubectl delete deployment cert-manager -n cert-manager
kubectl get pods -n cert-manager
```

Wait 10 seconds — Flux detects the drift and restores it:

```bash
kubectl get pods -n cert-manager
```

```
cert-manager-xxx   1/1   Running   ← Flux restored it
```

This is the GitOps guarantee: declared state always wins over manual changes.

---

## Summary

| Resource | Purpose | Example |
|---|---|---|
| `HelmRepository` | Where to find charts | `url: https://charts.jetstack.io` |
| `HelmRelease` | What to install + values | chart: cert-manager, version: 1.16.x |
| `flux get helmrelease -A` | Status of all releases | Ready / Not Ready |
| `flux reconcile` | Force immediate sync | After a manual values change |
| `flux suspend` / `resume` | Pause GitOps for a release | Safe manual intervention window |

---

## Next steps

➡️ [Module 5, Lesson 2 — GitOps with Flux: The Full Loop](../2.lesson-gitops-flux/unit-1.md)
