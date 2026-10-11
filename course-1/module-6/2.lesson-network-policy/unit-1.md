# Lesson 6.2 — Network Policy: Cilium and Namespace Isolation

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running with Cilium CNI
> **Duration:** ~35 minutes

---

## What you will do

Control network traffic between pods and namespaces using **Kubernetes NetworkPolicy** and **Cilium** (the NKP default CNI):

1. Observe the default open-network behavior
2. Apply a default-deny policy to a namespace
3. Selectively allow only the traffic you need
4. Use Cilium-specific `CiliumNetworkPolicy` for L7 (HTTP path) rules

---

## How Cilium enforces NetworkPolicy

Cilium operates at the eBPF layer — policies are compiled into BPF programs loaded directly into the kernel on each node, making enforcement extremely fast (no iptables chains).

```
Pod A  ──► eBPF hook ──► policy check ──► Pod B
                              │
                         NetworkPolicy
                         (L3/L4 rules)
                              │
                         CiliumNetworkPolicy
                         (L7 HTTP/gRPC rules)
```

Policies are **additive** — multiple NetworkPolicy objects targeting the same pod are unioned. There is no explicit deny syntax in the standard API (use `CiliumNetworkPolicy` for that).

---

## Part 1 — Default behavior (no policies)

By default, Kubernetes allows all pod-to-pod communication across all namespaces.

### 1.1 Set up two namespaces

```bash
kubectl create namespace frontend
kubectl create namespace backend
```

### 1.2 Deploy a backend service

```bash
kubectl run backend --image=nginx:alpine \
    --namespace=backend \
    --labels=app=backend \
    --port=80
kubectl expose pod backend \
    --namespace=backend \
    --port=80 \
    --name=backend-svc
```

### 1.3 Reach the backend from the frontend namespace

```bash
kubectl run curl --image=curlimages/curl \
    --namespace=frontend \
    --restart=Never \
    --rm -it -- \
    curl -s http://backend-svc.backend.svc.cluster.local/
```

You get the nginx welcome page — unrestricted cross-namespace access.

---

## Part 2 — Default-deny ingress

Apply a **default-deny** policy to the `backend` namespace. This blocks all ingress traffic to any pod in `backend` unless explicitly allowed.

### 2.1 Apply the default-deny policy

```yaml
# default-deny-backend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}        # matches ALL pods in the namespace
  policyTypes:
    - Ingress
```

```bash
kubectl apply -f default-deny-backend.yaml
```

### 2.2 Verify traffic is now blocked

```bash
kubectl run curl --image=curlimages/curl \
    --namespace=frontend \
    --restart=Never \
    --rm -it -- \
    curl -s --max-time 5 http://backend-svc.backend.svc.cluster.local/
```

```
curl: (28) Connection timed out after 5001 milliseconds
```

All ingress to `backend` pods is blocked.

---

## Part 3 — Allow only specific traffic

Now open exactly the traffic you need: frontend pods can reach the backend on port 80. Nothing else.

### 3.1 Label the frontend namespace

NetworkPolicy uses namespace labels to match allowed sources:

```bash
kubectl label namespace frontend purpose=frontend
kubectl get namespace frontend --show-labels
```

### 3.2 Apply the allow policy

```yaml
# allow-frontend-to-backend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              purpose: frontend
          podSelector:
            matchLabels: {}    # any pod in the frontend namespace
      ports:
        - protocol: TCP
          port: 80
```

```bash
kubectl apply -f allow-frontend-to-backend.yaml
```

### 3.3 Test — frontend can reach backend

```bash
kubectl run curl --image=curlimages/curl \
    --namespace=frontend \
    --restart=Never \
    --rm -it -- \
    curl -s http://backend-svc.backend.svc.cluster.local/
```

```
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title>...
```

### 3.4 Test — default namespace is still blocked

```bash
kubectl run curl --image=curlimages/curl \
    --namespace=default \
    --restart=Never \
    --rm -it -- \
    curl -s --max-time 5 http://backend-svc.backend.svc.cluster.local/
```

```
curl: (28) Connection timed out after 5001 milliseconds
```

Only `frontend` namespace traffic is allowed — all other sources are denied.

---

## Part 4 — Egress control

NetworkPolicy also controls outbound traffic from pods. This is useful for preventing compromised pods from reaching external services or other internal namespaces they should not talk to.

### 4.1 Default-deny egress from a namespace

```yaml
# deny-egress-backend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53     # always allow DNS so pod names resolve
```

```bash
kubectl apply -f deny-egress-backend.yaml
```

Backend pods can now only make outbound DNS queries — nothing else.

---

## Part 5 — Cilium L7 NetworkPolicy

Standard Kubernetes NetworkPolicy operates at L3/L4 (IP + port). **CiliumNetworkPolicy** extends this to L7 — you can allow or deny specific HTTP paths and methods.

### 5.1 Deploy an API with two paths

```bash
kubectl run api --image=nginx:alpine \
    --namespace=backend \
    --labels=app=api \
    --port=80
kubectl expose pod api --namespace=backend --port=80 --name=api-svc
```

Create a custom nginx config that returns different content per path:

```bash
kubectl exec -n backend api -- sh -c '
cat > /etc/nginx/conf.d/api.conf <<EOF
server {
    listen 80;
    location /public  { return 200 "public\n"; }
    location /private { return 200 "private\n"; }
}
EOF
nginx -s reload'
```

### 5.2 Apply an L7 CiliumNetworkPolicy

Allow access to `/public` only — block `/private`:

```yaml
# cilium-l7-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-public-only
  namespace: backend
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: /public
```

```bash
kubectl apply -f cilium-l7-policy.yaml
```

### 5.3 Test L7 enforcement

```bash
# /public — allowed
kubectl run curl --image=curlimages/curl \
    --namespace=frontend \
    --restart=Never \
    --rm -it -- \
    curl -s http://api-svc.backend.svc.cluster.local/public
```

```
public
```

```bash
# /private — blocked at L7
kubectl run curl --image=curlimages/curl \
    --namespace=frontend \
    --restart=Never \
    --rm -it -- \
    curl -s http://api-svc.backend.svc.cluster.local/private
```

```
Access denied
```

Cilium enforced an HTTP path rule — the TCP connection was allowed but the specific HTTP request was rejected.

---

## Clean up

```bash
kubectl delete namespace frontend backend
```

---

## Summary

| Policy type | Scope | Enforced by |
|---|---|---|
| `NetworkPolicy` default-deny | Block all ingress or egress | Cilium (eBPF) |
| `NetworkPolicy` allow by namespace | Open traffic from specific namespaces | Cilium (eBPF) |
| `NetworkPolicy` allow by label | Open traffic from specific pods | Cilium (eBPF) |
| `CiliumNetworkPolicy` L7 | Allow/deny by HTTP method + path | Cilium L7 proxy |

### Zero-trust namespace isolation pattern

For production clusters apply this pattern to every application namespace:

```
1. default-deny-ingress (blocks everything)
2. default-deny-egress  (blocks everything except DNS)
3. explicit allow rules (open only what is needed)
```

This is the **least-privilege network model** — nothing communicates unless explicitly permitted.

---

## Next steps

➡️ [Module 7, Lesson 1 — GPU: Passthrough, Operator, MIG, and Time-Slicing](../../module-7/1.lesson-gpu/unit-1.md)
