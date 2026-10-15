---
kind: unit
title: "Sizing NKP for AI/ML Workloads"
name: lesson-ai-sizing-unit-1
---

::remark-box
This is a **reference / walkthrough lesson** — no lab playground needed. Use it when you need to answer the question: "how many GPUs, how much RAM, and how many nodes do I need for this LLM job?" Three real scenarios with hardware specs, pod YAML, and Kueue configuration.
::

## The two questions sizing answers

Every AI/ML workload on NKP starts with two questions:

1. **How much VRAM does the job need?** (determines GPU count)
2. **How does the job run — single-node or multi-node?** (determines network requirements)

Everything else — vCPU, RAM, disk, storage — follows from those two answers.

---

## VRAM sizing rules

These formulas hold across all transformer-based LLMs (GPT, LLaMA, Mistral, Qwen, etc.):

| Training mode | VRAM per billion parameters | Example: 70B model |
|---|---|---|
| **Full Fine-Tuning (FP16)** + Adam optimizer | ~16 GB / 1B params | ~1,120 GB → 14× H100 80GB |
| **Full Fine-Tuning (BF16)** + AdamW 8-bit | ~8 GB / 1B params | ~560 GB → 7× H100 80GB |
| **QLoRA (4-bit NF4)** + LoRA adapters | ~6–10 GB / 1B params | ~40–50 GB → 1× H100 80GB |
| **Inference only (FP16)** | ~2 GB / 1B params | ~140 GB → 2× H100 80GB |
| **Inference only (INT8)** | ~1 GB / 1B params | ~70 GB → 1× H100 80GB |

> For QLoRA, see [Lesson 7-4 — What is QLoRA?](../4.lesson-qlora/unit-1.md) for a detailed explanation of why 4-bit quantization drops VRAM so dramatically.

---

## The CVM tax — always subtract first

Before sizing any NKP node, subtract the **CVM reservation**. This is non-negotiable — the CVM always holds these resources and they are never available to pods:

| Resource | Reserved per node | Impact |
|---|---|---|
| vCPU | 12 vCPU | A node with 32 vCPU has 20 vCPU available to NKP |
| RAM | 48 GB | A node with 128 GB RAM has 80 GB available to NKP |

**Rule of thumb:** When a Nutanix spec sheet says "NX-9151-G9: 40 vCPU / 512 GB RAM", the NKP-available budget is **28 vCPU / 464 GB RAM** (after CVM tax).

---

## Scenario 1 — Small: 7B–13B QLoRA (single GPU)

**Workload:** QLoRA fine-tuning of Llama 3.1 8B or Qwen2.5 7B–13B.  
**VRAM needed:** ~40–50 GB → **1× H100 80GB** is sufficient.

### Cluster topology

| Component | Count | Specs per unit | Available to NKP |
|---|---|---|---|
| NKP Control Plane VMs | 3 | 4 vCPU / 16 GB / 150 GB | 3× (4 vCPU / 16 GB) |
| GPU Node (NX-9151-G9) | 1 | 4× H100 80GB, 40 vCPU / 256 GB (node) | 28 vCPU / 208 GB |
| Storage (min 3 nodes for RF2) | 3 | 3× NVMe 3.84 TB + 4× HDD 16 TB | ~60 TB usable |

> Only 1 GPU is in use — the other 3 H100s on the node are available for future jobs or parallel experiments.

### Training pod spec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: qlora-7b-finetune
  namespace: ai-training
spec:
  restartPolicy: OnFailure
  nodeSelector:
    nvidia.com/gpu.product: "NVIDIA-H100-80GB-HBM3"
  containers:
  - name: trainer
    image: 172.16.0.10/ai/training:latest   # from Harbor
    command: ["python", "train_qlora.py"]
    resources:
      limits:
        nvidia.com/gpu: "1"
        memory: 64Gi
        cpu: "16"
      requests:
        nvidia.com/gpu: "1"
        memory: 32Gi
        cpu: "8"
    volumeMounts:
    - name: model-cache
      mountPath: /models
    - name: dataset
      mountPath: /data
  volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: model-storage
  - name: dataset
    persistentVolumeClaim:
      claimName: dataset-storage
```

### Summary

| | Value |
|---|---|
| GPUs | 1× H100 80GB |
| VRAM used | ~50 GB of 80 GB |
| Nodes | 3 minimum (RF2) |
| GPU east-west network | Not needed (single node) |
| Estimated time | 3–6 hours |
| Hardware cost estimate | ~$150,000–$200,000 |

---

## Scenario 2 — Medium: 13B Full FT or 70B QLoRA (2–4 GPUs)

**Workload A:** Full fine-tuning of Llama 3.1 13B → ~2× H100 80GB (~120 GB VRAM).  
**Workload B:** QLoRA of Llama 3.1 70B → can fit on 1× H100, but 4× speeds up epoch time.

### Cluster topology

| Component | Count | Specs | Available to NKP |
|---|---|---|---|
| NKP Control Plane VMs | 3 | 4 vCPU / 16 GB / 150 GB | 3× (4 vCPU / 16 GB) |
| GPU Nodes (NX-9151-G9) | 2 | 4× H100 80GB each, 40 vCPU / 256 GB | 28 vCPU / 208 GB each |
| CPU-only nodes (NX-8155) | 2 | 32 vCPU / 128 GB / 500 GB | 20 vCPU / 80 GB each |
| Storage | 4 nodes RF2 | Mixed NVMe/HDD | ~120 TB usable |

CPU-only nodes handle data pipeline, tokenization, and preprocessing — keeping the GPU nodes free for compute.

### Pod spec (2 GPUs, same node via NVLink)

```yaml
resources:
  limits:
    nvidia.com/gpu: "2"   # 2 H100s — must be on the same physical node for NVLink
    memory: 128Gi
    cpu: "32"
```

### Kueue gang scheduling — prevent GPU overbooking

When multiple training jobs compete for GPUs, Kueue ensures jobs only start when all their requested GPUs are available simultaneously (gang scheduling):

```yaml
# kueue-resource-flavor.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ResourceFlavor
metadata:
  name: h100-pool
spec:
  nodeLabels:
    nvidia.com/gpu.product: "NVIDIA-H100-80GB-HBM3"
---
# kueue-cluster-queue.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: ai-training-queue
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["nvidia.com/gpu", "cpu", "memory"]
    flavors:
    - name: h100-pool
      resources:
      - name: nvidia.com/gpu
        nominalQuota: "8"    # total GPUs in the pool (2 nodes × 4 GPUs)
      - name: cpu
        nominalQuota: "56"   # 2 nodes × 28 vCPU available
      - name: memory
        nominalQuota: "416Gi"
```

```yaml
# workload-admission.yaml — attach to your training job
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  name: training-queue
  namespace: ai-training
spec:
  clusterQueueName: ai-training-queue
```

### 200 Gbps east-west requirement

If the job needs to spread across 2 GPU nodes (e.g. 8 total GPUs via NCCL All-Reduce), the nodes must be on a **200 Gbps fabric**. On slower networks, NCCL collective communication becomes the bottleneck — the GPUs spend more time waiting for gradient sync than computing.

```
Node 1 (4× H100) ←──200 Gbps (CX7)──→ Node 2 (4× H100)
                        ↑
                  NCCL All-Reduce traffic
                  (gradient sync during training)
```

With 200 Gbps NICs and proper NCCL tuning, multi-node training achieves ~85–90% scaling efficiency (8 GPUs ≈ 7× single-GPU throughput).

### Summary

| | Value |
|---|---|
| GPUs | 2–4× H100 80GB |
| VRAM used | ~120–640 GB |
| GPU nodes | 2 |
| Total nodes | 4 |
| East-west network | 200 Gbps (Mellanox CX7) if multi-node |
| Estimated time | 6–24 hours |
| Hardware cost estimate | ~$350,000–$500,000 |

---

## Scenario 3 — Large: 70B Full Fine-Tuning (8 GPUs)

**Workload:** Full fine-tuning of Llama 3.1 70B with FSDP/ZeRO-3.  
**VRAM needed:** ~640 GB (8× H100 80GB) — 8-way tensor parallelism.

### The AHV ceiling

> ⚠️ **AHV maximum: 4 GPUs per node.** The NX-9151-G9 has 4× H100 maximum. There is no Nutanix AHV node with 8 GPUs. For an 8-GPU job you have two options:

| Option | How | Trade-off |
|---|---|---|
| **Option A: 2× AHV nodes** | 2 pods of 4 GPUs + NCCL All-Reduce over 200 Gbps | ~5–10% overhead vs. NVLink, needs dedicated GPU fabric |
| **Option B: NKP Metal** | 1 bare-metal DGX H100 (8× H100 + NVLink/NVSwitch) | No VM overhead, full NVLink bandwidth, requires NKP Metal license |

### Cluster topology (Option A — 2 AHV nodes)

| Component | Count | Specs | Available to NKP |
|---|---|---|---|
| NKP Control Plane VMs | 3 | 4 vCPU / 16 GB / 150 GB | 3× (4 vCPU / 16 GB) |
| GPU Nodes (NX-9151-G9) | 2 | 4× H100 80GB, 40 vCPU / 512 GB | 28 vCPU / 464 GB each |
| CPU nodes (data pipeline) | 2 | 32 vCPU / 128 GB / 500 GB | 20 vCPU / 80 GB each |
| Storage | 4 nodes RF2 | 3× NVMe 3.84 TB + 4× HDD 16 TB per node | ~200 TB usable |
| GPU east-west network | — | 200 Gbps CX7 (isolated from north-south) | — |
| North-south network | — | 100 Gbps (storage + management) | — |

> **Network isolation is critical** at this scale. GPU All-Reduce traffic saturates 200 Gbps links during backward passes. Running it on the same physical network as storage I/O causes packet loss and training instability.

### Pod spec (4 GPUs per pod, 2 pods for 8 total)

```yaml
# Each pod gets 4 GPUs from one node (NVLink on-node)
resources:
  limits:
    nvidia.com/gpu: "4"
    memory: 256Gi
    cpu: "64"
```

For the 2-pod gang job, use a Kueue `PodGroup` or a Kubeflow `PyTorchJob`:

```yaml
# pytorch-job-70b.yaml (Kubeflow Training Operator)
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: llama-70b-full-ft
  namespace: ai-training
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      template:
        spec:
          nodeSelector:
            nvidia.com/gpu.product: "NVIDIA-H100-80GB-HBM3"
          containers:
          - name: trainer
            image: 172.16.0.10/ai/training:latest
            resources:
              limits:
                nvidia.com/gpu: "4"
                memory: 256Gi
                cpu: "64"
    Worker:
      replicas: 1   # 1 master + 1 worker = 2 nodes × 4 GPUs = 8 GPUs total
      template:
        spec:
          nodeSelector:
            nvidia.com/gpu.product: "NVIDIA-H100-80GB-HBM3"
          containers:
          - name: trainer
            image: 172.16.0.10/ai/training:latest
            resources:
              limits:
                nvidia.com/gpu: "4"
                memory: 256Gi
                cpu: "64"
```

### ZeRO-3 / FSDP — why 8 GPUs work for 70B

Full fine-tuning of 70B in FP16 requires ~1,120 GB of VRAM (weights + gradients + optimizer states). 8× H100 80GB = 640 GB — not enough for naive data parallelism.

**FSDP (Fully Sharded Data Parallel) / ZeRO-3** shards the model across all 8 GPUs:

```
Without sharding:  each GPU holds full model (~1,120 GB) → impossible
With ZeRO-3:       each GPU holds 1/8 of weights + 1/8 of gradients + 1/8 of optimizer state
                   → 1,120 GB / 8 = ~140 GB per GPU → fits in 80 GB with mixed precision
```

The trade-off: every forward and backward pass requires All-Reduce collective communication across all 8 GPUs. This is why 200 Gbps inter-node networking is not optional.

### Summary

| | Value |
|---|---|
| GPUs | 8× H100 80GB (across 2 nodes) |
| VRAM used | ~640 GB (80 GB × 8) |
| GPU nodes | 2 (max per AHV ceiling) |
| Total nodes | 4 |
| East-west GPU fabric | 200 Gbps (isolated, mandatory) |
| Estimated time | 24–48 hours |
| Hardware cost estimate | ~$500,000–$700,000 |

---

## Quick-reference sizing rules

| Parameter | Rule |
|---|---|
| **VRAM (Full FT, FP16)** | 16 GB × B params + 20% overhead |
| **VRAM (QLoRA, 4-bit)** | 6–10 GB × B params |
| **VRAM (inference, INT8)** | 1 GB × B params |
| **vCPU per GPU node** | 20 vCPU minimum / 32 vCPU recommended (for data loading) |
| **RAM per GPU node** | 40 GB minimum / 64+ GB recommended |
| **Disk per GPU node** | 300 GB (model + checkpoints) / 500 GB (large datasets) |
| **CVM tax** | −12 vCPU / −48 GB per physical node |
| **Minimum nodes** | 3 (RF2, tolerates 1 node failure) |
| **GPU east-west** | 200 Gbps (CX7) if >1 GPU node; 100 Gbps if single node |
| **AHV GPU ceiling** | 4 GPUs per node maximum |
| **Kueue nominalQuota** | Set to total GPUs in pool — prevents overbooking |

---

## Scenario comparison

| | Scenario 1 | Scenario 2 | Scenario 3 |
|---|---|---|---|
| **Model** | 7B–13B QLoRA | 13B Full FT / 70B QLoRA | 70B Full FT |
| **GPUs** | 1× H100 | 2–4× H100 | 8× H100 |
| **VRAM used** | ~50 GB | ~120–640 GB | ~640 GB |
| **GPU nodes** | 1 | 2 | 2 |
| **Total nodes** | 3 | 4 | 4 |
| **East-west network** | Not needed | 200 Gbps | 200 Gbps (isolated) |
| **Estimated time** | 3–6 hrs | 6–24 hrs | 24–48 hrs |
| **Hardware cost** | ~$150–200K | ~$350–500K | ~$500–700K |

> **Key insight:** In AHV the bottleneck for large jobs is not the number of GPUs available (max 4/node), it is that jobs requiring more than 4 GPUs need multi-node NCCL over 200 Gbps, or migration to NKP Metal (bare-metal nodes with DGX H100 = 8 GPUs per node with NVLink/NVSwitch and no VM overhead).

---

## Next steps

➡️ [Lesson 7-4 — What is QLoRA?](../4.lesson-qlora/unit-1.md) — understand why QLoRA is so much cheaper than full fine-tuning  
➡️ [GPU Support Part 2](../1.lesson-gpu/unit-2.md) — install the NVIDIA GPU Operator and verify GPU availability in your cluster
