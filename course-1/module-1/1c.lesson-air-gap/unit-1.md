---
kind: unit
title: "What is Air-Gapped? (and why NKP is built for it)"
name: lesson-air-gap-unit-1
---

::remark-box
**Air-gapped** is one of those terms that shows up everywhere in enterprise Kubernetes without much explanation. This lesson defines it precisely, explains why enterprises require it, and shows exactly how NKP handles it — including what breaks without it and how Harbor fixes that.
::

## What "air-gapped" means

An **air-gapped environment** is a network that has no outbound internet access — either by firewall policy, physical network isolation, or regulatory requirement.

The name comes from the original security concept: a physical "air gap" between two networks means there are literally no cables connecting them. In modern enterprise IT, "air-gapped" is used more broadly to mean any environment where outbound internet traffic is blocked or heavily restricted.

```
Traditional internet-connected deployment:
  Kubernetes node → pulls images from docker.io, quay.io, gcr.io, nvcr.io
  Helm → fetches charts from charts.helm.sh, artifacthub.io
  (works fine — as long as internet is available)

Air-gapped deployment:
  Kubernetes node → ❌ cannot reach docker.io
  Helm → ❌ cannot reach charts.helm.sh
  (everything breaks unless you have a local mirror)
```

---

## Why enterprises run air-gapped Kubernetes

Three drivers, all common in NKP's target market:

| Reason | Who requires it | Example |
|---|---|---|
| **Security / compliance** | Financial services, healthcare, government | PCI-DSS, HIPAA, FedRAMP — regulations may prohibit or restrict outbound connections from production systems |
| **Sovereign cloud** | Government, defense, regulated industries | Data and workloads must stay within a specific geographic or network boundary |
| **Operational reliability** | Any large enterprise | Production clusters should not depend on third-party registries being up — Docker Hub has had outages; quay.io has had rate limiting incidents |

For Nutanix specifically: NKP targets enterprise data centre deployments. A significant portion of those environments are air-gapped by policy, even if there is no formal regulatory requirement — the security team simply blocks outbound internet from the cluster network.

---

## What breaks in an air-gap (without preparation)

When a Kubernetes cluster has no internet access, every operation that pulls external resources fails silently or explicitly:

| Operation | Source | Breaks because |
|---|---|---|
| Pod creation | Container images from `docker.io`, `quay.io`, `gcr.io`, `registry.k8s.io` | `ImagePullBackOff` — node cannot reach the registry |
| NKP add-on install | Helm charts from `charts.helm.sh` | Flux HelmRelease cannot fetch the chart |
| NVIDIA GPU Operator | Images from `nvcr.io` (NVIDIA Container Registry) | Operator pod stuck in `ImagePullBackOff` |
| cert-manager | Images from `quay.io/jetstack` | Certificate issuance broken |
| Cluster creation itself | CAPI/CAPX controller images | Bootstrap cluster cannot start controllers |

The failure mode is always the same: pods stuck in `ImagePullBackOff` or `ErrImagePull`, with no useful error about connectivity — just "image not found".

---

## The NKP solution — image bundles + local registry mirror

NKP is designed for air-gapped deployments from the ground up. The solution has two parts:

### Part 1 — The NKP image bundle

Nutanix ships a pre-packaged **image bundle** containing every container image needed to run NKP:

```
kommander-image-bundle-v2.17.1.tar   (~30–50 GB compressed)
```

This is a single `.tar` file you download once from the Nutanix support portal on an internet-connected machine, transfer to your air-gapped environment, and load into a local registry. It contains:
- All CAPI / CAPX / CAREN controller images
- All Kommander component images
- All default add-on images (Cilium, CoreDNS, metrics-server, cert-manager, Flux...)
- The RKE2 system images

### Part 2 — Harbor as the local registry mirror

**Harbor** is an open-source container registry (Apache 2.0 license, CNCF Graduated project). It started as an internal VMware project in 2016 and was donated to the community. Think of it as your own private Docker Hub — installed inside your data center, fully under your control.

::details-box
---
:summary: "Why Harbor is critical in an air-gapped environment"
---

In an air-gapped environment, cluster nodes cannot reach any external registry — no `docker.io`, no `quay.io`, no `gcr.io`, no `registry.k8s.io`. But Kubernetes needs images for everything:

| Category | Examples |
|---|---|
| **Kubernetes system components** | `coredns`, `kube-proxy`, `pause`, `etcd` |
| **NKP platform components** | Flux CD, cert-manager, Cilium, MetalLB, Traefik |
| **NKP add-ons** | Prometheus, Grafana, Velero, Longhorn, GPU Operator |
| **Customer workloads** | Any application image the dev teams deploy |

Without a local registry, every one of these results in `ImagePullBackOff` — the node tries to reach the internet, fails, and the pod never starts. The cluster bootstraps but nothing runs.

Harbor solves this by being the **single local source** for all images. You pre-load it once from the NKP bundle (on a connected machine or via secure media transfer), and from that point on every node pulls from Harbor — no internet required at runtime.
::

**Harbor** acts as a **local mirror** for all the external registries NKP needs. Instead of pulling from `docker.io` or `quay.io`, every cluster node pulls from Harbor.

```
Air-gapped deployment with Harbor:

  Kubernetes node → Harbor (local, 172.16.0.10) → serves cached images
                                                  (no internet needed)

  Internet-connected machine (one-time setup):
    → downloads NKP image bundle
    → pushes to Harbor
    → Harbor now has everything
```

Harbor can operate in two modes:

| Mode | How it works | Use case |
|---|---|---|
| **Proxy cache** | Forwards requests to upstream registries and caches results | Semi-connected environments — first pull goes to internet, subsequent pulls are cached |
| **Pre-loaded** | Images pushed directly into Harbor from the bundle | True air-gap — no internet access ever needed after initial setup |

In this course, Harbor is **pre-loaded** into the `nkp-bootstrap` rootfs (vm1). All images needed for the lab are already in Harbor before the lab starts.

---

## The REGISTRY_MIRROR_URL environment variable

NKP's `nkp create cluster` command accepts a registry mirror configuration. This is how you tell every NKP node to pull images from Harbor instead of the internet:

```bash
export REGISTRY_MIRROR_URL="172.16.0.10"

nkp create cluster nutanix \
  --cluster-name my-cluster \
  ...
  # NKP reads REGISTRY_MIRROR_URL and injects it into every node's
  # containerd configuration as a registry mirror
```

Under the hood, NKP injects this into each node VM's containerd configuration at `/etc/rancher/rke2/registries.yaml`:

```yaml
mirrors:
  "docker.io":
    endpoint:
      - "http://172.16.0.10"
  "quay.io":
    endpoint:
      - "http://172.16.0.10"
  "registry.k8s.io":
    endpoint:
      - "http://172.16.0.10"
```

Every image pull request — regardless of original registry — is redirected to Harbor first.

---

## Docker Hub rate limits — the other reason for Harbor

Even in non-air-gapped environments, Harbor pays for itself quickly because of **Docker Hub rate limits**:

| Account type | Pull limit |
|---|---|
| Anonymous | 100 pulls / 6 hours |
| Free (authenticated) | 200 pulls / 6 hours |
| Pro / Team | Unlimited |

A single `nkp create cluster` run pulls dozens of images per node. With a 4-node cluster, you can hit 200 pulls in a single deployment. If you iterate (destroy and recreate) during development or learning, you hit the limit in one session.

Harbor's proxy cache means each image is pulled from Docker Hub **once** and served locally for all subsequent pulls — the rate limit only applies to Harbor→Docker Hub, not to your cluster nodes.

---

## GPU Operator and air-gap

The NVIDIA GPU Operator pulls images from **NVIDIA's Container Registry (`nvcr.io`)** — a separate registry from Docker Hub. In an air-gap, this is a second source that needs to be pre-loaded into Harbor.

The GPU-specific air-gap steps (pre-pulling from `nvcr.io`, pushing to Harbor, configuring the GPU Operator to use the local mirror) are covered in [Module 7 — GPU Support on NKP](../../module-7/1.lesson-gpu/unit-2.md).

---

## Lab activity — confirm Harbor is running on vm1

In this course, Harbor is already running on **vm1 (bootstrap)** at `172.16.0.10`. Confirm it is reachable and the NKP images are loaded:

```bash
# 1. Check Harbor API is responding
curl -sf http://172.16.0.10/api/v2.0/ping && echo "Harbor ✓"

# 2. List the projects in Harbor (should include 'nkp' and 'rancher')
curl -sf http://172.16.0.10/api/v2.0/projects \
  | python3 -m json.tool \
  | grep '"name"'

# 3. Confirm containerd on vm1 is configured to use Harbor as mirror
cat /etc/rancher/rke2/registries.yaml
```

Expected output for step 3:
```yaml
mirrors:
  "docker.io":
    endpoint:
      - "http://172.16.0.10"
  "quay.io":
    endpoint:
      - "http://172.16.0.10"
  "registry.k8s.io":
    endpoint:
      - "http://172.16.0.10"
```

If Harbor is not reachable, check `docker ps` on vm1 — the Harbor containers (`harbor-core`, `harbor-registry`, `harbor-portal`) should be running.

---

## Summary

| Concept | One-line definition |
|---|---|
| **Air-gapped** | Network with no outbound internet access — by policy or physical isolation |
| **Image bundle** | Pre-packaged `.tar` of all NKP container images — load once, use offline |
| **Harbor** | Local container registry that mirrors external registries and serves cached images |
| **Registry mirror** | Containerd config that redirects all image pulls to a local registry first |
| **REGISTRY_MIRROR_URL** | NKP env var that injects the mirror config into every cluster node |

> The air-gap pattern you set up once in Module 1 carries through every module. Every `nkp create cluster`, every add-on install, every GPU Operator deployment in this course uses Harbor — you will never pull directly from the internet.
