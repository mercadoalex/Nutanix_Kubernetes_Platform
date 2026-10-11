---
kind: unit
title: "Lesson 13 — GPU Support on NKP"
name: 1.lesson-gpu-unit-1
---

# Lesson 13 — GPU Support on NKP

> **Tier:** Mixed  
> **Part A — AHV GPU assignment:** 📺 Walkthrough (requires real Nutanix hardware)  
> **Part B — GPU Operator + lab simulation:** 💻 Interactive (Flexbox 5-VM playground)  
> **Playground:** `nkp-flexbox` (vm1 = bootstrap, vm2–vm5 = cluster)

---

## What you will learn

- How to assign a physical GPU to a VM on Nutanix AHV (passthrough and vGPU)
- How NKP's NVIDIA GPU Operator catalog add-on works and how to enable it
- How to verify GPU availability in a Kubernetes cluster
- How to schedule GPU workloads with `nvidia.com/gpu` resource requests
- How to share a GPU across multiple pods using **time-slicing**
- How to partition an A100/H100 with **MIG** for hard memory isolation
- How to test GPU scheduling in the lab **without physical hardware**

---

## Version reference

| Component | Version used |
|---|---|
| NKP | 2.17 |
| NVIDIA GPU Operator | v24.9.1 |
| CUDA base image | 12.4.0-base-ubuntu22.04 |
| RKE2 (cluster runtime) | v1.34.3+rke2r1 |

---

## Part A — Adding a GPU to a Nutanix AHV VM

> 📺 **Demo only** — requires Prism Central with physical GPU hardware installed in the AHV host.

NKP worker VMs are standard AHV VMs. Before the GPU Operator can see a GPU, the physical device must be assigned to the VM at the hypervisor level. AHV supports two modes:

### PCIe Passthrough (dedicated GPU per VM)

The entire physical GPU is reserved for one VM. No NVIDIA licensing required.

1. **Power off** the target VM in Prism Central (passthrough requires cold assignment — hot-plug is not supported)
2. Prism Central → **Virtual Infrastructure** → **VMs** → select the VM → **Update**
3. Scroll to the **GPU** section → **+ Add GPU**
4. Set type to **Passthrough**
5. Select the GPU device (e.g. `NVIDIA A100 80GB PCIe`)
6. **Save** → **Power On**

> ⚠️ Enable **CPU Pinning** and **NUMA alignment** on the VM to avoid cross-NUMA GPU-to-CPU memory latency: VM → Update → **CPU Pinning** → Enable.

### NVIDIA vGPU (shared GPU across multiple VMs)

One physical GPU is time-sliced at the hypervisor level into multiple vGPU instances, each VM gets a slice with dedicated framebuffer. Requires an **NVIDIA vGPU software license**.

1. Same path: VM → Update → GPU → **+ Add GPU** → type = **Virtual GPU (vGPU)**
2. Select a **compute profile** — for Kubernetes/AI workloads use `C` suffix profiles:
   - `A100-40C` — 40 GB framebuffer, full compute
   - `A10-4C` — 4 GB, suits smaller inference workloads
   - `A16-4C` — cost-effective, 4× A16 cards per GPU board

**AHV vGPU profile suffix guide:**

| Suffix | Type | Use case |
|---|---|---|
| `-xC` | Compute (vCS) | ML training, inference — **use this for NKP** |
| `-xQ` | Quadro Virtual Workstation | Pro graphics + compute |
| `-xA` | Virtual Application | Lightweight VDI |
| `-xB` | Virtual PC | Standard VDI desktops |

### AOS / Prism Central version requirements

| Feature | AOS min | PC min |
|---|---|---|
| PCIe passthrough | 5.15 | pc.2022.1 |
| NVIDIA vGPU | 6.5 | pc.2022.6 |
| vGPU live migration | 6.7 | pc.2023.3 |
| NKP 2.17 full support | **7.3** | **pc.7.3** |

---

## Part B — Enabling the GPU Operator on NKP

> 💻 **Interactive** — run from vm1 (bootstrap) against the cluster on vm2–vm5.

### How the GPU Operator works

The NVIDIA GPU Operator is a Kubernetes Operator that manages the **entire GPU software stack** as DaemonSets — you never need to bake GPU drivers into the node OS image.

```
ClusterPolicy (CRD)
    │
    ▼
GPU Operator controller
    ├── Driver DaemonSet         → compiles + loads NVIDIA kernel module
    ├── Container Toolkit DS     → injects nvidia-container-runtime into containerd
    ├── Device Plugin DS         → registers nvidia.com/gpu as K8s Extended Resource
    ├── GFD (Feature Discovery)  → labels nodes: nvidia.com/gpu.product, .memory, etc.
    ├── DCGM Exporter DS         → Prometheus metrics (utilization, temp, ECC errors)
    └── MIG Manager DS           → manages MIG partitioning on A100/H100
```

Students interact with a single `ClusterPolicy` object — the Operator reconciles all the moving parts.

### Option 1 — Enable via `nkp` CLI (recommended for NKP)

```bash
# On vm1, with KUBECONFIG pointing at the management cluster
export KUBECONFIG=/home/laborant/labs/mgmt.kubeconfig

# List available catalog applications
nkp get applications

# Enable the GPU Operator add-on on a workload cluster
nkp enable application nvidia-gpu-operator \
  --cluster-name=workload-01

# With custom values (e.g. disable driver if pre-installed in node image)
nkp enable application nvidia-gpu-operator \
  --cluster-name=workload-01 \
  --values=/home/laborant/labs/13-gpu/gpu-operator-values.yaml
```

### Option 2 — Enable via Kommander UI

1. Kommander Dashboard → **Clusters** → select the target cluster
2. → **Add-ons** → find **"GPU Operator"** in the catalog
3. Click **Enable** / **Deploy**
4. Expand **Configuration** to override values before deploying

### Option 3 — Direct Helm install (for non-Kommander clusters)

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --version v24.9.1 \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true \
  --set gfd.enabled=true \
  --wait
```

### RKE2-specific values override

NKP nodes run RKE2, which uses a **non-standard containerd socket path**. Recent GPU Operator versions (v23.9+) auto-detect this, but if you are pinning an older version:

```yaml
# gpu-operator-values.yaml
toolkit:
  env:
  - name: CONTAINERD_SOCKET
    value: /run/k3s/containerd/containerd.sock
  - name: CONTAINERD_CONFIG
    value: /var/lib/rancher/rke2/agent/etc/containerd/config.toml
```

---

## Part C — Verifying GPU availability

```bash
# 1. Check GPU Operator pods are all Running
kubectl get pods -n gpu-operator

# Expected: all pods Running or Completed
# NAME                                                        READY   STATUS
# gpu-operator-xxxxx                                          1/1     Running
# nvidia-container-toolkit-daemonset-xxxxx                    1/1     Running
# nvidia-dcgm-exporter-xxxxx                                  1/1     Running
# nvidia-device-plugin-daemonset-xxxxx                        1/1     Running
# nvidia-driver-daemonset-xxxxx                               1/1     Running
# nvidia-gpu-feature-discovery-xxxxx                          1/1     Running

# 2. Check node labels applied by GPU Feature Discovery
kubectl get nodes --show-labels | tr ',' '\n' | grep nvidia

# 3. Check GPU capacity registered on the node
kubectl describe node <gpu-node> | grep -A10 "Capacity:"
# nvidia.com/gpu: 1

# 4. Run nvidia-smi in a CUDA container
kubectl run -it --rm gpu-test \
  --image=nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04 \
  --restart=Never \
  --limits='nvidia.com/gpu=1' \
  -- nvidia-smi
```

---

## Part D — Scheduling a GPU workload

### Basic GPU pod

```yaml
# gpu-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vector-add
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-vector-add
    image: nvcr.io/nvidia/cuda:12.4.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: "1"    # request 1 GPU — whole-GPU allocation
      requests:
        nvidia.com/gpu: "1"
```

```bash
kubectl apply -f gpu-pod.yaml
kubectl logs cuda-vector-add
# Should print nvidia-smi output with GPU name, driver version, CUDA version
```

> **Important:** GPU resources cannot be fractional (`0.5` is not valid). For sub-GPU sharing, use time-slicing (§E) or MIG (§F).

### Targeting a specific GPU type with node selectors

GPU Feature Discovery labels nodes with GPU properties. Use these for precise placement:

```yaml
spec:
  nodeSelector:
    nvidia.com/gpu.product: "NVIDIA-A100-SXM4-80GB"
    # or:
    nvidia.com/gpu.memory: "81920"   # MB
```

---

## Part E — GPU Time-Slicing (sharing one GPU across pods)

Time-slicing oversubscribes a single GPU by advertising multiple logical units. There is **no memory isolation** between slices — use MIG for that.

### Step 1 — Create the time-slicing ConfigMap

```yaml
# time-slicing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
        - name: nvidia.com/gpu
          replicas: 4    # 1 physical GPU → advertised as 4
```

```bash
kubectl apply -f time-slicing-config.yaml
```

### Step 2 — Reference it from ClusterPolicy

```bash
kubectl patch clusterpolicy gpu-cluster-policy \
  --type=merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
```

### Step 3 — Verify

```bash
kubectl describe node <gpu-node> | grep "nvidia.com/gpu"
# Capacity:    nvidia.com/gpu: 4
# Allocatable: nvidia.com/gpu: 4
```

Four pods can now each request `nvidia.com/gpu: 1` and all land on the same physical GPU.

---

## Part F — MIG (Multi-Instance GPU) for hard isolation

MIG is only available on **NVIDIA A100, A30, H100, H200**. It partitions the GPU in hardware — each instance gets dedicated SM clusters, L2 cache, and HBM2 bandwidth. No interference between instances.

### A100 80 GB MIG profile options

| Profile | Instances per GPU | Memory | Use case |
|---|---|---|---|
| `1g.10gb` | 7 | 10 GB each | Many small inference workloads |
| `2g.20gb` | 3 | 20 GB each | Medium models |
| `3g.40gb` | 2 | 40 GB each | Large models |
| `7g.80gb` | 1 | 80 GB (full) | Single large training job |

### Enable MIG in ClusterPolicy

```yaml
# mig-parted-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mig-parted-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    mig-configs:
      all-1g.10gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "1g.10gb": 7
      all-3g.40gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "3g.40gb": 2
      all-disabled:
        - devices: all
          mig-enabled: false
```

```bash
kubectl apply -f mig-parted-config.yaml

kubectl patch clusterpolicy gpu-cluster-policy \
  --type=merge \
  -p '{
    "spec": {
      "mig": {"strategy": "single"},
      "migManager": {
        "enabled": true,
        "config": {"name": "mig-parted-config", "default": "all-1g.10gb"}
      }
    }
  }'
```

### Request a MIG slice in a pod

```yaml
resources:
  limits:
    nvidia.com/mig-1g.10gb: "1"    # one isolated MIG instance
```

### Time-slicing vs. MIG at a glance

| | Time-Slicing | MIG |
|---|---|---|
| GPU models | All NVIDIA | A100, A30, H100, H200 only |
| Memory isolation | ❌ Shared | ✅ Hardware partitioned |
| Fault isolation | ❌ | ✅ |
| Profile flexibility | Any replica count | Fixed profiles per model |
| Best for | Dev/test, small models | Production multi-tenant inference |

---

## Part G — Lab simulation (no physical GPU)

In the Flexbox playground there is no physical GPU. Use this technique to practice GPU-aware scheduling, node selectors, and resource requests without hardware.

### Advertise fake GPU capacity on a node

```bash
# On vm1 — patch a worker node to advertise 2 fake GPUs
kubectl proxy &
sleep 1

NODE=worker-01   # or worker-02, worker-03

curl -s -k -X PATCH \
  -H "Content-Type: application/json-patch+json" \
  "http://localhost:8001/api/v1/nodes/${NODE}/status" \
  -d '[{"op":"add","path":"/status/capacity/nvidia.com~1gpu","value":"2"}]'

# Verify
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'
```

### Deploy a fake GPU device plugin

For persistent fake GPU registration (survives kubelet restarts):

```yaml
# fake-gpu-plugin.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fake-gpu-device-plugin
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: fake-gpu-device-plugin
  template:
    metadata:
      labels:
        app: fake-gpu-device-plugin
    spec:
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      containers:
      - name: fake-plugin
        image: divineops/fake-gpu-device-plugin:latest
        env:
        - name: NUM_GPUS
          value: "2"
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
```

```bash
kubectl apply -f fake-gpu-plugin.yaml
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'
```

### Test GPU-aware scheduling

```bash
# Schedule a pod that requests 1 GPU — it will land on a fake-GPU node
kubectl run gpu-scheduled-test \
  --image=busybox \
  --restart=Never \
  --limits='nvidia.com/gpu=1' \
  -- sleep 60

# Confirm it scheduled (it won't have a real GPU device, but scheduling logic works)
kubectl get pod gpu-scheduled-test -o wide

# Confirm the node's GPU capacity was consumed
kubectl describe node worker-01 | grep -A5 "Allocated resources"
```

> ⚠️ `nvidia-smi` will fail inside the pod — there is no real device. This simulation exercises **scheduling**, **resource accounting**, and **node selector** logic only.

---

## What works in the lab vs. what requires real hardware

| Exercise | Lab (fake GPU) | Real hardware needed |
|---|---|---|
| Deploy GPU Operator CRDs and controller | ✅ | |
| Author `ClusterPolicy` YAML | ✅ | |
| Author time-slicing ConfigMap | ✅ | |
| Author MIG ConfigMap | ✅ | |
| `nvidia.com/gpu` pod scheduling | ✅ (with fake plugin) | |
| Node selector by `nvidia.com/gpu.product` | ✅ (with manual label) | |
| `nvidia-smi` inside a container | | ✅ |
| DCGM Prometheus metrics | | ✅ |
| Actual CUDA workload | | ✅ |
| AHV GPU passthrough assignment | | ✅ (Prism Central) |
| vGPU profile selection | | ✅ (Prism Central + NVIDIA license) |

---

## Next steps

➡️ [Module 7, Lesson 2 — Ansible Automation](../2.lesson-ansible/unit-1.md)
