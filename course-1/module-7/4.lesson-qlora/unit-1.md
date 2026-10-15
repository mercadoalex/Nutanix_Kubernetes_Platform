---
kind: unit
title: "What is QLoRA? Fine-Tuning LLMs on One GPU"
name: lesson-qlora-unit-1
---

::remark-box
This is a **concept-only lesson** — no lab, no terminal. It is written for DevOps and platform engineers who need to understand what ML engineers are asking them to provision. You do not need to know how neural networks work. By the end you will be able to answer the question: "why does this fine-tuning job need only 1 GPU when the base model has 70 billion parameters?"
::

## The problem — LLMs are too big to fine-tune

A pre-trained large language model like Llama 3.1 70B has **70 billion parameters** — the numerical values that define its behaviour. In full FP16 precision, each parameter takes 2 bytes:

```
70,000,000,000 parameters × 2 bytes = 140 GB (weights alone)

Full fine-tuning also needs:
  + gradients:       140 GB
  + optimizer state: 560 GB  (Adam keeps 2 momentum terms per parameter)
  ─────────────────────────
  Total:            ~840 GB minimum VRAM
```

Even 8× H100 80GB = 640 GB. A 70B full fine-tune doesn't fit in any standard GPU cluster without techniques like ZeRO-3 / FSDP (covered in [Lesson 7-3 — Sizing](../3.lesson-ai-sizing/unit-1.md)).

For most fine-tuning use cases — adapting a model to a specific domain or task — this is complete overkill. You don't need to update all 70 billion parameters.

---

## LoRA — only train a tiny fraction of the model

**LoRA (Low-Rank Adaptation)** is a technique from 2021 (Hu et al.) that makes fine-tuning practical by only updating a small fraction of the model's weights.

### The idea

Instead of updating the full weight matrices in the model's attention layers, LoRA **freezes the original weights** and injects small "adapter" matrices alongside them:

```
Original weight matrix W  (frozen, 4096 × 4096 = 16M params)
                         + LoRA adapter: A × B
                           A: 4096 × 16 = 65K params
                           B: 16 × 4096 = 65K params
                           Total adapter: 130K params  (0.8% of W)
```

During training, only A and B are updated. The original W never changes.

**What this means for infra:**
- Training only needs to store gradients and optimizer state for the LoRA adapters — not the full model
- Adapter parameters are typically **1–5% of the original model**
- Memory for gradients + optimizer shrinks by the same ratio

The trained adapter is saved as a small file (~100–500 MB for a 7B model). To deploy, you load the original base model + the adapter on top.

---

## QLoRA — LoRA + 4-bit quantization

**QLoRA (Quantized LoRA)** adds one more trick: store the frozen base model in **4-bit NF4 (NormalFloat4)** instead of 16-bit.

### What quantization means

Quantization reduces the numerical precision of the stored weights:

| Precision | Bits per parameter | 70B model size | VRAM |
|---|---|---|---|
| FP32 | 32 bits | 280 GB | 280 GB |
| FP16 / BF16 | 16 bits | 140 GB | 140 GB |
| INT8 | 8 bits | 70 GB | 70 GB |
| **NF4 (QLoRA)** | **4 bits** | **35 GB** | **35 GB** |

> NF4 is not just "round to fewer bits". It uses a specially calibrated 4-bit quantization format designed for normally-distributed neural network weights — it preserves more information than naive 4-bit rounding and causes less quality loss.

### QLoRA combined effect

```
QLoRA = frozen base model in NF4 (4-bit) + trainable LoRA adapters in FP16

70B model in NF4:    ~35 GB
LoRA adapters (1%):  ~1.5 GB
Optimizer state:     ~3 GB  (only for the adapters, not the base model)
─────────────────────────────
Total VRAM needed:   ~40 GB
```

**A 70B model that would need 840 GB of VRAM for full fine-tuning now fits in 40 GB — on a single H100 80GB with headroom to spare.**

---

## What this means for the platform engineer

Your ML team says "we want to fine-tune Llama 3.1 70B". Your first question should be: **"which technique?"**

| Technique | VRAM | Nodes | Network | Cost |
|---|---|---|---|---|
| Full Fine-Tuning | ~840 GB | 3+ nodes × 4× H100 | 200 Gbps mandatory | ~$500–700K hardware |
| QLoRA | ~40 GB | 1 node × 1× H100 | None needed | ~$150–200K hardware |
| LoRA (FP16 base) | ~150 GB | 2 nodes × 1× H100 | 200 Gbps if multi-node | ~$200–300K hardware |
| Inference only (INT8) | ~70 GB | 1 node × 1× H100 | None | Existing hardware |

Most domain adaptation and instruction fine-tuning tasks can be done with QLoRA. The quality difference vs. full fine-tuning is measurable but often acceptable for enterprise use cases. If the ML team doesn't know which technique to use, QLoRA is the correct starting point.

### The pod resource spec for a QLoRA job

```yaml
# qlora-70b.yaml
apiVersion: v1
kind: Pod
metadata:
  name: qlora-llama-70b
  namespace: ai-training
spec:
  restartPolicy: OnFailure
  nodeSelector:
    nvidia.com/gpu.product: "NVIDIA-H100-80GB-HBM3"
  containers:
  - name: trainer
    image: 172.16.0.10/ai/training:latest
    resources:
      limits:
        nvidia.com/gpu: "1"    # just 1 GPU — QLoRA fits in 40 GB of 80 GB
        memory: 64Gi
        cpu: "16"
      requests:
        nvidia.com/gpu: "1"
        memory: 32Gi
        cpu: "8"
```

Compare this to the full fine-tuning equivalent, which needs `nvidia.com/gpu: "4"` across two nodes with a PyTorchJob and 200 Gbps networking.

---

## The implementation stack (read-only — what the ML engineer runs)

This is what the ML team's training script looks like. You don't need to understand it — it's here so you can recognize what libraries a QLoRA job needs and size the container image accordingly.

```python
# qlora_train.py — ~20 lines for the core setup
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import get_peft_model, LoraConfig, TaskType
import torch

# 1. Load base model in 4-bit NF4 (the "Q" in QLoRA)
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",          # NormalFloat4 quantization
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,     # extra memory saving
)
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-70B",
    quantization_config=bnb_config,
    device_map="auto",
)

# 2. Add LoRA adapters (the "LoRA" in QLoRA)
lora_config = LoraConfig(
    task_type=TaskType.CAUSAL_LM,
    r=16,               # rank — controls adapter size
    lora_alpha=32,
    target_modules=["q_proj", "v_proj"],   # which attention layers to adapt
    lora_dropout=0.05,
)
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# trainable params: 41,943,040 || all params: 70,554,116,096 || trainable%: 0.0595
```

**What the ML team needs from you (the platform engineer):**
- A node with 1× H100 80GB (or similar)
- The `bitsandbytes` library available in the container image (requires CUDA 11.8+)
- The `transformers` and `peft` libraries (Hugging Face ecosystem)
- Storage for the base model weights (~35 GB as NF4, ~140 GB as FP16 from Hugging Face)
- The NVIDIA driver version to be compatible with CUDA 12.x (GPU Operator handles this)

---

## Summary

| Concept | One-line definition |
|---|---|
| **LoRA** | Fine-tune only tiny adapter matrices (1–5% of params); freeze the base model |
| **Quantization** | Reduce weight precision from FP16 to 4-bit NF4 — cuts base model VRAM by 4× |
| **QLoRA** | LoRA + 4-bit quantization: 70B fine-tune fits in 40 GB VRAM on 1 GPU |
| **bitsandbytes** | The Python library that implements NF4 quantization on CUDA |
| **peft** | Hugging Face library that implements LoRA / QLoRA adapters |
| **Your job** | 1× H100, `nvidia.com/gpu: 1`, 64 GB RAM limit, storage for base model |

> See [Lesson 7-3 — Sizing NKP for AI/ML](../3.lesson-ai-sizing/unit-1.md) for how QLoRA maps to Scenario 1 (the cheapest configuration) and how it compares to full fine-tuning scenarios.
