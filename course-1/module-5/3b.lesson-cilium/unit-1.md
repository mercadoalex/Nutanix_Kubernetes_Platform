---
kind: unit
title: "Cilium: NKP's Default CNI — Deep Dive"
name: lesson-cilium-unit-1
---

::remark-box
Cilium is installed automatically by NKP on every cluster. Most operators use it for years without looking inside. This lesson changes that. By the end you'll understand why NKP chose Cilium, how eBPF works, how to observe live traffic with Hubble, and how to write network policies that work at L3, L4, and L7.
::

## What a CNI does (30-second recap)

A **CNI (Container Network Interface)** plugin is responsible for three things in a Kubernetes cluster:

1. **Assigning IP addresses** to pods when they start
2. **Routing traffic** between pods across nodes
3. **Enforcing NetworkPolicy** — deciding which pods can talk to which

Without a CNI, pods have no IP addresses and cannot communicate. The CNI is not optional.

NKP's default CNI is **Cilium**. It is installed automatically by CAREN during cluster creation and managed by Flux CD as a HelmRelease.

---

## The iptables problem — why Cilium exists

To understand why Cilium matters, you need to understand what was broken before it.

### How traditional CNIs enforce policy — iptables

Traditional CNIs (Calico in iptables mode, Flannel, Weave) enforce NetworkPolicy using **iptables** — the Linux kernel's packet filtering framework, originally designed in 1998 for simple firewall rules on a single machine.

In Kubernetes, every pod-to-pod connection requires the CNI to translate a NetworkPolicy rule into a chain of iptables rules on every node. For a cluster with 500 pods and 50 NetworkPolicy rules, that means:

```
500 pods × 50 rules × ~5 iptables rules per policy rule
  = ~125,000 iptables rules per node
  = evaluated sequentially for every packet
```

### Why this doesn't scale

iptables has three fundamental problems at Kubernetes scale:

**1. O(n) packet evaluation**
iptables rules are evaluated as a sequential list. Every packet entering a node must walk through every rule until it matches (or falls through). At 125,000 rules, this means 125,000 comparisons per packet, per node — on every microsecond of network traffic.

**2. Full rebuild on every change**
When you add one new pod or change one NetworkPolicy rule, iptables cannot append a single rule. It must **replace the entire ruleset** atomically. On a large cluster, this rebuild takes seconds — during which packets are dropped.

```bash
# What happens when a new pod starts on a node with 500 pods:
# 1. CNI adds pod IP
# 2. CNI flushes all iptables rules on this node
# 3. CNI rebuilds all 125,000 rules from scratch
# 4. Duration: 2–10 seconds
# 5. During rebuild: existing connections may drop
```

**3. No visibility**
iptables rules are binary — allow or deny. They produce no logs, no flow records, no latency metrics. When a pod can't reach a service, you have no native way to see why.

### The scale numbers in practice

| Cluster size | iptables rules per node | Rebuild time on change | Packet evaluation overhead |
|---|---|---|---|
| 50 pods | ~5,000 | < 100ms | Negligible |
| 500 pods | ~50,000 | 1–3 seconds | Measurable |
| 5,000 pods | ~500,000 | 30–120 seconds | Significant CPU overhead |
| 50,000 pods | ~5,000,000 | Minutes | Cluster-destabilising |

NKP targets enterprise deployments with hundreds to thousands of pods. iptables was not designed for this.

---

## eBPF — the foundation of Cilium

**eBPF (extended Berkeley Packet Filter)** is a Linux kernel subsystem that allows you to run sandboxed programs directly inside the kernel — triggered by kernel events — without modifying kernel source code or loading kernel modules.

Think of it as a safe, programmable hook system inside the kernel:

```
Traditional kernel extension:
  Write kernel module → compile against kernel headers → load → crash risk

eBPF:
  Write eBPF program (restricted C) → compile to eBPF bytecode
  → kernel verifier checks safety → JIT-compiled to machine code
  → attached to kernel event (network packet, syscall, function call)
  → runs at kernel speed, safely isolated
```

### The eBPF verifier — why it's safe

Before an eBPF program runs, the kernel **verifier** statically analyzes it:
- No unbounded loops (programs must terminate)
- No out-of-bounds memory access
- No privileged operations that could crash the kernel
- Maximum instruction count enforced

If the program passes verification, the JIT compiler translates it to native machine code. It then runs **in the kernel**, attached to the hook you specified, with no user-space context switches.

### What eBPF replaces in Cilium

Cilium uses eBPF programs attached to network hooks to replace the entire iptables path:

```
Traditional CNI (iptables):
  Packet arrives → netfilter → iptables chains → 125,000 rule walk → decision

Cilium (eBPF):
  Packet arrives → eBPF hook at XDP/TC layer → hash lookup in eBPF map → decision
  (O(1) hash lookup instead of O(n) sequential scan)
```

Key eBPF data structures Cilium uses:

| eBPF Map Type | Cilium use | Performance characteristic |
|---|---|---|
| **Hash map** | Policy lookup: "is this endpoint ID allowed to talk to that endpoint ID?" | O(1) — constant time regardless of policy count |
| **LRU hash map** | Connection tracking (CT table) | O(1) per connection |
| **Array map** | Per-CPU statistics counters | Lock-free, per-CPU |
| **Prog array** | Tail calls between eBPF programs | Zero overhead function dispatch |

---

## Cilium's identity model — not IP-based

Traditional network policy is IP-based: "allow traffic from 10.0.0.5 to 10.0.0.12". This breaks in Kubernetes because pod IPs change constantly — when a pod restarts, it gets a new IP.

Cilium uses a fundamentally different model: **identity-based policy**.

### How identities work

Every pod gets a **Cilium identity** — a numeric ID derived from its Kubernetes labels, not its IP address:

```
Pod: app=frontend, env=production, version=v2
  → Cilium computes identity hash from labels
  → Identity: 12345
  → eBPF maps: "identity 12345 can talk to identity 67890"

Pod restarts, gets new IP (10.0.0.42 → 10.0.0.87):
  → Same labels → same identity 12345
  → Policy still valid, no update needed
```

### Identity scopes

Cilium defines several identity scopes beyond pod labels:

| Identity type | What it represents | Example |
|---|---|---|
| **Pod** | K8s pod (derived from labels) | `app=frontend` |
| **Service** | K8s Service object | `svc/my-service` |
| **Node** | K8s Node | `node/worker-01` |
| **World** | External traffic (outside cluster) | Internet, on-prem systems |
| **Host** | The node's host network | kubelet, node-local services |
| **Remote node** | Traffic from another cluster node | Cross-node pod traffic |
| **Ingress** | Traffic entering via an Ingress | From load balancer to pod |

This means you can write a policy like "allow traffic from the `world` identity only on port 443" without knowing any IP addresses — and it works across pod restarts, node migrations, and cluster rescales.

---

## CiliumNetworkPolicy — writing policies at L3, L4, and L7

Kubernetes has a standard `NetworkPolicy` resource. Cilium supports it fully, but also provides `CiliumNetworkPolicy` — an extended CRD with L7 capabilities that standard `NetworkPolicy` cannot express.

### The OSI layer hierarchy

| Layer | What Cilium can filter | Standard NetworkPolicy? |
|---|---|---|
| **L3** (Network) | Source/destination IP CIDR, identity | ✅ Yes |
| **L4** (Transport) | TCP/UDP port, protocol | ✅ Yes |
| **L7** (Application) | HTTP method/path/header, DNS name, Kafka topic, gRPC method | ❌ No — Cilium only |

### L3/L4 policy — allow traffic between specific pods

A basic policy: allow `frontend` pods to talk to `backend` pods on port 8080, deny everything else:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: frontend-to-backend
  namespace: production
spec:
  # This policy applies to pods with label app=backend
  endpointSelector:
    matchLabels:
      app: backend

  # Allow ingress from pods with label app=frontend, on port 8080
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

Key points:
- `endpointSelector` — which pods this policy applies to (the destination)
- `fromEndpoints` — which pods are allowed to send traffic (the source)
- No `ingress` rule = **deny all** ingress (default deny when a policy exists)
- `egress` rules work the same way in reverse

### L4 policy — allow only specific ports

Restrict a database pod to only accept connections on port 5432, from any pod in the same namespace:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: postgres-ingress
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: postgres

  ingress:
    - fromEndpoints:
        - {}    # any pod in the same namespace (empty selector = all)
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
```

### L7 policy — allow only specific HTTP methods and paths

This is where Cilium goes beyond what standard NetworkPolicy can do. Allow `frontend` to call the `backend` API, but only GET requests to `/api/v1/products` — block everything else at L7:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: frontend-api-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend

  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/api/v1/products"
              - method: "GET"
                path: "/api/v1/products/.*"   # regex supported
```

With this policy:
- `GET /api/v1/products` → ✅ allowed
- `POST /api/v1/products` → ❌ blocked (wrong method)
- `GET /admin/reset` → ❌ blocked (wrong path)
- Any other pod → ❌ blocked (not `app=frontend`)

Cilium enforces this **inside the kernel via eBPF** — the packet is parsed at L7 and the policy decision is made before the application ever sees the request.

### L7 DNS policy — control which domains pods can resolve

Restrict an application pod to only resolve specific domains (useful in air-gapped or zero-trust environments):

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: restrict-dns
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: my-app

  egress:
    # Allow DNS queries to kube-dns only
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
          rules:
            dns:
              - matchPattern: "*.cluster.local"  # internal services only
              - matchPattern: "*.svc.cluster.local"
```

### Default-deny posture

Best practice in a production cluster is to apply a default-deny policy to every namespace, then explicitly allow what you need:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  # Applies to all pods in the namespace
  endpointSelector: {}

  # Deny all ingress (no ingress rules = deny all)
  ingress: []

  # Deny all egress except DNS (otherwise nothing works)
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

---

## Hubble — L7 observability built into Cilium

**Hubble** is Cilium's distributed observability layer. It records every network flow in the cluster — source, destination, port, protocol, HTTP method/path/status code, DNS queries, and the policy decision (allow/drop) — without any application instrumentation.

Hubble works by reading the eBPF flow records that Cilium's data plane produces as a side effect of packet processing. **There is no sampling, no agents to inject, no application changes needed.**

### Hubble components

```
Cilium agent (each node)
  └── produces eBPF flow records → Hubble observer (local gRPC server)

Hubble Relay
  └── aggregates flows from all nodes → single cluster-wide stream

Hubble UI
  └── service map, real-time flows, policy verdict visualisation

hubble CLI
  └── query flows from the terminal
```

### Enabling Hubble (if not already enabled)

In NKP, Hubble can be enabled via the add-on catalog or directly through the Cilium HelmRelease:

```bash
# Enable Hubble via cilium CLI (quickest in lab)
cilium hubble enable --ui

# Verify
cilium status | grep Hubble
# Expected: Hubble: Ok   Current/Max Flows: 4096/4096
```

### Using the hubble CLI

```bash
# Port-forward Hubble Relay to your local machine
cilium hubble port-forward &

# Watch all flows in real time
hubble observe --follow

# Filter: show only flows to a specific pod
hubble observe --follow --to-pod production/backend

# Filter: show only dropped flows (policy violations)
hubble observe --follow --verdict DROPPED

# Filter: show L7 HTTP flows
hubble observe --follow --protocol http

# Show flows between two labels
hubble observe \
  --from-label app=frontend \
  --to-label app=backend \
  --last 100
```

### Reading Hubble output

```
Feb 04 14:23:11.401: production/frontend-7d6b9c (id:12345) -> production/backend-5f8d2a (id:67890)
  TCP Flags: SYN  policy-verdict:allow INGRESS
  http: GET /api/v1/products -> 200 OK (12ms)

Feb 04 14:23:14.882: production/unknown-pod (id:99999) -> production/backend-5f8d2a (id:67890)
  TCP Flags: SYN  policy-verdict:DENY INGRESS
```

Each line tells you:
- **Timestamp** and **source/destination pod** (with Cilium identity IDs)
- **Protocol** and **flags**
- **Policy verdict**: `allow` or `DENY`
- **L7 details** (HTTP method, path, status code, latency) when available

### Hubble UI — the service map

The Hubble UI renders a live **service dependency map** — every service as a node, every active communication as an edge, colour-coded by policy verdict (green = allowed, red = denied).

```bash
# Access Hubble UI (port-forward)
cilium hubble port-forward &
# Open: http://localhost:12000
```

---

## Cilium vs. alternatives — when would you choose something else?

| CNI | Data plane | L7 policy | Observability | NKP support | Best for |
|---|---|---|---|---|---|
| **Cilium** | eBPF | ✅ Full (HTTP, DNS, gRPC, Kafka) | ✅ Hubble built-in | ✅ Default | Scale, security, observability |
| **Calico** | eBPF or iptables | ❌ L4 only (native) | ⚠️ Basic (with add-ons) | ✅ Supported | VMware/OpenStack migrations, existing Calico ops |
| **Flannel** | VXLAN / host-gw | ❌ None | ❌ None | ❌ Not in NKP | Simple dev clusters only |
| **Weave** | VXLAN | ❌ L4 only | ⚠️ Basic | ❌ Not in NKP | Legacy — no longer maintained |

### Can you use Calico with NKP?

Yes — but you have to override the default. CAREN injects Cilium automatically during cluster creation. To use Calico instead:

```bash
nkp create cluster nutanix \
  --cluster-name my-cluster \
  --cni calico \
  ...
```

**Why you probably shouldn't:** Calico in iptables mode has the scaling problems described above. Calico in eBPF mode is improving but lags Cilium's feature set (no L7, no Hubble equivalent). Unless you have an operational reason (existing Calico expertise, specific GlobalNetworkPolicy features), Cilium is the better choice.

**The honest answer**: keep the NKP default unless you have a specific reason to change it.

---

## Lab — Cilium on the 5-VM cluster

### Step 1 — Check Cilium status

```bash
# From vm1 (bootstrap), with the cluster kubeconfig loaded
cilium status

# Expected output:
#     /¯¯\
#  /¯¯\__/¯¯\    Cilium:         OK
#  \__/¯¯\__/    Operator:       OK
#  /¯¯\__/¯¯\    Hubble Relay:   OK
#  \__/¯¯\__/    ClusterMesh:    disabled
#     \__/
# ...
# Allocated identities:   47
# Current node/total:     4/4
```

```bash
# Check Cilium pods are running on all nodes
kubectl -n kube-system get pods -l k8s-app=cilium -o wide

# Each node should have one Cilium agent pod in Running state
```

### Step 2 — Inspect a Cilium endpoint

```bash
# List all Cilium endpoints (one per pod)
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list

# Get details for a specific endpoint
kubectl -n kube-system exec -it ds/cilium -- cilium endpoint get <ENDPOINT_ID>
# Look for: identity, labels, policy enforcement status
```

### Step 3 — Enable Hubble and observe flows

```bash
# Enable Hubble (if not already enabled in your cluster)
cilium hubble enable

# Wait for Hubble Relay to be ready
kubectl -n kube-system rollout status deployment/hubble-relay

# Start port-forward
cilium hubble port-forward &

# Deploy a simple two-tier app to generate traffic
kubectl create namespace demo
kubectl -n demo run frontend --image=nginx --labels="app=frontend"
kubectl -n demo run backend  --image=nginx --labels="app=backend"
kubectl -n demo expose pod backend --port=80 --name=backend-svc

# Generate some traffic
kubectl -n demo exec frontend -- curl -s http://backend-svc

# Watch the flows
hubble observe --namespace demo --follow
```

### Step 4 — Apply a L7 NetworkPolicy and watch it enforce

```bash
# Create the policy — allow frontend→backend GET only, block everything else
cat <<EOF | kubectl apply -f -
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: demo-l7-policy
  namespace: demo
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/"
EOF

# Test allowed request
kubectl -n demo exec frontend -- curl -sv http://backend-svc/
# Expected: 200 OK

# Test blocked method (POST)
kubectl -n demo exec frontend -- curl -sv -X POST http://backend-svc/
# Expected: 403 Access Denied (Cilium rejects at L7)

# Watch Hubble to see the policy verdicts
hubble observe --namespace demo --follow
# You will see: allow (GET /) and DENY (POST /)
```

### Step 5 — Inspect the eBPF maps directly

```bash
# SSH into a worker node (vm2 or vm3)
ssh laborant@172.16.0.12

# List eBPF programs loaded by Cilium
sudo bpftool prog list | grep -i cilium | head -20

# List eBPF maps
sudo bpftool map list | grep -i cilium | head -20

# Show the policy map for a specific endpoint
# First get the endpoint ID from step 2, then:
sudo bpftool map dump pinned /sys/fs/bpf/tc/globals/cilium_policy_<ENDPOINT_ID>
```

This lets you see the raw eBPF maps that Cilium uses to enforce policy — the actual data structures doing the work at kernel speed.

### Step 6 — Clean up

```bash
# Remove demo resources
kubectl delete namespace demo
# Stop Hubble port-forward
kill %1
```

---

## Key Cilium commands — reference

```bash
# Status
cilium status                          # overall health
cilium status --verbose                # detailed component status

# Endpoints
cilium endpoint list                   # all endpoints in the cluster
cilium endpoint get <ID>               # details for one endpoint

# Policy
cilium policy get                      # all active policies
cilium policy trace --src-k8s-pod ns/pod --dst-k8s-pod ns/pod --dport 80/TCP
                                       # trace policy decision for a flow

# Hubble
hubble observe --follow                # live flow stream
hubble observe --verdict DROPPED       # only denied flows
hubble observe --namespace <ns>        # flows in a namespace
hubble observe --from-label app=X --to-label app=Y  # between labels

# Connectivity test
cilium connectivity test               # full end-to-end connectivity check
```

---

## Check your understanding

1. Why does iptables-based policy enforcement degrade at scale?
2. What does the eBPF verifier check before allowing a program to run?
3. Why is Cilium's identity model better than IP-based policy for Kubernetes?
4. What is the difference between `endpointSelector` and `fromEndpoints` in a `CiliumNetworkPolicy`?
5. What L7 protocols can Cilium enforce policy on (name at least three)?
6. What does Hubble observe, and how does it get that information without instrumenting applications?
7. You want to allow `app=frontend` to call `GET /api/v1/orders` on `app=backend` port 8080, and block everything else. Write the `CiliumNetworkPolicy`.
8. A pod in your cluster cannot reach an external service. How would you use `hubble observe` to diagnose this?

Answers are in the lesson above — re-read the relevant sections before moving on.
