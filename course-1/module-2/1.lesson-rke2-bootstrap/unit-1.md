---
kind: unit
title: "Bootstrap the RKE2 Control Plane"
name: lesson-rke2-bootstrap-unit-1
---

## Five VMs. Zero Kubernetes. Let's fix that.

Open the **controlplane** terminal (vm2). RKE2 is installed but not running.
You're going to start it and watch a Kubernetes cluster come to life.

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

RKE2 started as a single binary that launched:
1. **etcd** — the cluster database
2. **kube-apiserver** — the Kubernetes API
3. **kube-controller-manager** — control loops
4. **kube-scheduler** — pod placement
5. **kubelet** — node agent (registering vm2 as a node)
6. **Cilium** — CNI from the airgap image bundle

The airgap bundles in `/var/lib/rancher/rke2/agent/images/` meant no internet
access was needed — all container images were already on disk.
