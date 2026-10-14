---
kind: unit
title: "Bootstrap the RKE2 Control Plane"
name: lesson-rke2-bootstrap-unit-1
---

## Five VMs. Zero Kubernetes. Let's fix that.

Open the **controlplane** terminal (vm2). RKE2 is installed but not running.
You're going to start it and watch a Kubernetes cluster come to life.

---

## What is rke2-server?

**RKE2** (Rancher Kubernetes Engine 2) is the Kubernetes distribution NKP uses on every node. It replaces kubeadm with a single hardened binary that ships everything pre-bundled.

When you run `systemctl start rke2-server`, one process starts and it launches all of these inside it:

```
rke2-server
├── etcd                    — the cluster database (stores all K8s state)
├── kube-apiserver          — the API you talk to with kubectl
├── kube-controller-manager — watches objects, drives them toward desired state
├── kube-scheduler          — decides which node a new pod runs on
├── kubelet                 — manages the node's own pods
├── kube-proxy              — handles network rules for Services
├── containerd              — the container runtime
└── Cilium                  — CNI (pod networking)
```

RKE2 has two modes — **server** runs on control plane nodes, **agent** runs on workers:

| Process | Runs on | What it does |
|---|---|---|
| `rke2-server` | vm2 (control plane) | Runs etcd + all control plane components + kubelet |
| `rke2-agent` | vm3–5 (workers) | Runs kubelet + kube-proxy + containerd only — no etcd, no apiserver |

You start `rke2-server` on vm2 first. Once it's up you start `rke2-agent` on vm3–5, pointing them at vm2. That gives you a 1 control plane + 3 worker cluster.

### NKP vs AWS — who owns the control plane?

On AWS EKS the control plane is **managed** — AWS runs etcd and kube-apiserver invisibly on their infrastructure. You never see the control plane nodes, you can't SSH into them.

NKP is the opposite — **you own the control plane VMs**:

```
AWS EKS                          NKP on AHV
─────────────────────────────    ──────────────────────────────
[AWS managed — invisible]        [Your AHV VMs — fully visible]
  etcd                             VM: nkp-cp-1 (etcd + apiserver)
  kube-apiserver                   VM: nkp-cp-2 (etcd + apiserver)
  └─► you pay, can't touch         VM: nkp-cp-3 (etcd + apiserver)
                                   VIP: 10.x.x.50  ← kube-vip

[Your EC2 nodes]                 [Your AHV VMs]
  worker-1                         VM: nkp-worker-1
  worker-2                         VM: nkp-worker-2
```

This is why `nkp create cluster` needs `--control-plane-replicas 3` and `--control-plane-endpoint-ip` — it's provisioning real VMs with a floating VIP, not delegating to a cloud provider.

In the lab vm2 plays the role of all three control plane VMs. One node is enough to learn on — production NKP uses 3 for HA.

---

## 1. Configure the RKE2 server

The config file is already in place at `/etc/rancher/rke2/config.yaml`. Review it:

```bash
# On vm2 (controlplane)
cat /etc/rancher/rke2/config.yaml
```

You should see:
```yaml
cni: cilium
tls-san:
  - 172.16.0.11
write-kubeconfig-mode: "0644"
```

Three important settings:
- `cni: cilium` — RKE2 will deploy Cilium as the CNI instead of Canal
- `tls-san` — adds the VM's IP to the API server TLS certificate
- `write-kubeconfig-mode` — makes the kubeconfig readable without root

---

## 2. Start RKE2 server

```bash
# On vm2 (controlplane)
systemctl start rke2-server
```

Watch the logs in real time:

```bash
journalctl -u rke2-server -f
```

You will see (after 30–60 seconds):
```
Starting etcd...
Starting kube-apiserver...
Starting kube-controller-manager...
Starting kube-scheduler...
Node vm2 registered...
```

Wait until you see `Node vm2 registered` before continuing.

---

## 3. Verify the control plane is up

```bash
# On vm2 — RKE2 ships its own kubectl
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

kubectl get nodes
```

Expected:
```
NAME   STATUS   ROLES                       AGE   VERSION
vm2    Ready    control-plane,etcd,master   2m    v1.34.3+rke2r1
```

One node, `Ready`. That's your control plane.

---

## 4. Copy kubeconfig to vm1

Switch to the **bootstrap** terminal (vm1). Copy the kubeconfig from vm2:

```bash
# On vm1 (bootstrap)
mkdir -p ~/.kube
scp laborant@172.16.0.11:/etc/rancher/rke2/rke2.yaml ~/.kube/config

# Fix the server address (rke2.yaml uses 127.0.0.1, not the VM IP)
sed -i 's|127.0.0.1|172.16.0.11|g' ~/.kube/config

# Test it
kubectl get nodes
```

You should see vm2 Ready from vm1. From now on, run all `kubectl` commands from vm1.

---

## 5. Watch with k9s

```bash
# On vm1
k9s
```

Press `0` to see all namespaces. You'll see the system pods starting up:
- `etcd-vm2`
- `kube-apiserver-vm2`
- `kube-controller-manager-vm2`
- `kube-scheduler-vm2`
- `cilium-*` (CNI)
- `coredns-*` (DNS)

Wait until all pods are `Running` before proceeding to the next lesson.

Press `q` to exit k9s.

---

## What just happened

`rke2-server` started as a single binary and launched every control plane component as a static pod. On first start it had to pull its system images (~1 GB) from `registry.rancher.com` — that's the 3–5 minute wait. In production NKP deployments these come from the airgap bundle pre-loaded into the image.

vm2 is now running:
1. **etcd** — the cluster database, storing all K8s objects
2. **kube-apiserver** — the HTTPS API that `kubectl` talks to on port 6443
3. **kube-controller-manager** — reconciliation loops (Deployments → ReplicaSets → Pods)
4. **kube-scheduler** — watches for unscheduled pods and assigns them to nodes
5. **kubelet** — registers vm2 as a node and manages its pods
6. **Cilium** — pod networking, installed by RKE2 from the `cni: cilium` config

vm3–5 know nothing about this yet. The next lesson adds them as workers.
