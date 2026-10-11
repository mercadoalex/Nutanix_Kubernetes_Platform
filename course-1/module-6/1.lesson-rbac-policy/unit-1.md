# Lesson 6.1 — RBAC & Policy: ClusterRoles, RoleBindings, and OPA/Gatekeeper

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 4.1 complete — Management Cluster running
> **Duration:** ~45 minutes

---

## What you will do

Lock down your cluster using two complementary security layers:

1. **RBAC** — control who can do what with the Kubernetes API (authentication + authorization)
2. **OPA/Gatekeeper** — enforce what workloads are allowed to run (admission control)

---

## The two security layers

```
kubectl apply -f deployment.yaml
         │
         ▼
┌─────────────────────┐
│  Authentication     │  "Who are you?"
│  (certificates/     │  kubeconfig client cert or OIDC token
│   OIDC token)       │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  RBAC Authorization │  "Are you allowed to do this?"
│  ClusterRole +      │  Does your identity have a binding
│  RoleBinding        │  to a role that permits this verb+resource?
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  Admission Control  │  "Does this object meet our policies?"
│  OPA/Gatekeeper     │  Image registry allowed? Resource limits set?
│  ConstraintTemplate │  No privileged containers?
└────────┬────────────┘
         │
         ▼
     Resource created
```

---

## Part 1 — RBAC

### 1.1 Core objects

| Object | Scope | What it defines |
|---|---|---|
| `Role` | Namespace | Permissions within one namespace |
| `ClusterRole` | Cluster-wide | Permissions across all namespaces or non-namespaced resources |
| `RoleBinding` | Namespace | Grants a Role to a user/group/ServiceAccount in one namespace |
| `ClusterRoleBinding` | Cluster-wide | Grants a ClusterRole to a user/group/ServiceAccount cluster-wide |

### 1.2 Create a read-only Role for a namespace

```yaml
# readonly-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

```bash
kubectl apply -f readonly-role.yaml
```

### 1.3 Create a ServiceAccount and bind the Role

```bash
kubectl create serviceaccount dev-user -n default
```

```yaml
# readonly-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-user-pod-reader
  namespace: default
subjects:
  - kind: ServiceAccount
    name: dev-user
    namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f readonly-binding.yaml
```

### 1.4 Test the permissions

Use `kubectl auth can-i` to check what a ServiceAccount is allowed to do:

```bash
# Can dev-user list pods in default?
kubectl auth can-i list pods \
    --namespace=default \
    --as=system:serviceaccount:default:dev-user
```

```
yes
```

```bash
# Can dev-user delete pods?
kubectl auth can-i delete pods \
    --namespace=default \
    --as=system:serviceaccount:default:dev-user
```

```
no
```

```bash
# Can dev-user list pods in kube-system?
kubectl auth can-i list pods \
    --namespace=kube-system \
    --as=system:serviceaccount:default:dev-user
```

```
no
```

The Role only grants access within the `default` namespace.

### 1.5 ClusterRole — read access across all namespaces

```yaml
# cluster-readonly.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "namespaces", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ops-cluster-reader
subjects:
  - kind: ServiceAccount
    name: dev-user
    namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f cluster-readonly.yaml

kubectl auth can-i list pods \
    --namespace=kube-system \
    --as=system:serviceaccount:default:dev-user
```

```
yes
```

### 1.6 Impersonate to verify access end-to-end

```bash
kubectl get pods -n kube-system \
    --as=system:serviceaccount:default:dev-user
```

```bash
kubectl delete pod <any-pod> -n kube-system \
    --as=system:serviceaccount:default:dev-user
```

```
Error from server (Forbidden): pods "<name>" is forbidden: User "system:serviceaccount:default:dev-user"
cannot delete resource "pods" in API group "" in the namespace "kube-system"
```

### 1.7 Audit all permissions for a subject

```bash
kubectl auth can-i --list \
    --namespace=default \
    --as=system:serviceaccount:default:dev-user
```

---

## Part 2 — OPA/Gatekeeper

RBAC controls *who* can call the API. Gatekeeper controls *what* objects are valid. It runs as an admission webhook — every resource creation or update passes through it before being accepted.

### 2.1 Install Gatekeeper via Flux

```yaml
# gatekeeper.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gatekeeper
  namespace: flux-system
spec:
  interval: 1h
  url: https://open-policy-agent.github.io/gatekeeper/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: gatekeeper
  namespace: gatekeeper-system
spec:
  interval: 10m
  chart:
    spec:
      chart: gatekeeper
      version: "3.17.x"
      sourceRef:
        kind: HelmRepository
        name: gatekeeper
        namespace: flux-system
  values:
    replicas: 1
```

```bash
kubectl create namespace gatekeeper-system
kubectl apply -f gatekeeper.yaml
kubectl get pods -n gatekeeper-system
```

Wait for `gatekeeper-controller-manager` and `gatekeeper-audit` to be `Running`.

### 2.2 ConstraintTemplate — define a policy

A `ConstraintTemplate` defines the policy logic in Rego (OPA's policy language). This one requires all Deployments to have resource limits set:

```yaml
# require-limits-template.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requireresourcelimits
spec:
  crd:
    spec:
      names:
        kind: RequireResourceLimits
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requireresourcelimits

        violation[{"msg": msg}] {
          container := input.review.object.spec.template.spec.containers[_]
          not container.resources.limits.cpu
          msg := sprintf("Container '%v' must set resources.limits.cpu", [container.name])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.template.spec.containers[_]
          not container.resources.limits.memory
          msg := sprintf("Container '%v' must set resources.limits.memory", [container.name])
        }
```

```bash
kubectl apply -f require-limits-template.yaml
```

### 2.3 Constraint — enforce the policy

A `Constraint` activates the template and scopes it to specific resources:

```yaml
# require-limits-constraint.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireResourceLimits
metadata:
  name: require-resource-limits
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    namespaces:
      - default
```

```bash
kubectl apply -f require-limits-constraint.yaml
```

### 2.4 Test — deploy without limits (should be blocked)

```bash
kubectl create deployment no-limits --image=nginx:alpine
```

```
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
  [require-resource-limits] Container 'nginx' must set resources.limits.cpu
  [require-resource-limits] Container 'nginx' must set resources.limits.memory
```

Gatekeeper blocked it.

### 2.5 Test — deploy with limits (should pass)

```yaml
# with-limits.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: with-limits
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: with-limits
  template:
    metadata:
      labels:
        app: with-limits
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
```

```bash
kubectl apply -f with-limits.yaml
```

```
deployment.apps/with-limits created
```

Policy satisfied — deployment created.

### 2.6 Audit existing violations

Gatekeeper also audits existing resources for policy violations (not just new ones):

```bash
kubectl get requireresourcelimits require-resource-limits -o json \
    | jq '.status.violations'
```

Any existing Deployments without resource limits appear here.

---

## Clean up

```bash
kubectl delete deployment with-limits
kubectl delete clusterrolebinding ops-cluster-reader
kubectl delete clusterrole cluster-pod-reader
kubectl delete rolebinding dev-user-pod-reader -n default
kubectl delete role pod-reader -n default
kubectl delete serviceaccount dev-user -n default
kubectl delete requireresourcelimits require-resource-limits
kubectl delete constrainttemplate requireresourcelimits
```

---

## Summary

| Tool | Controls | Enforcement point |
|---|---|---|
| RBAC `Role` + `RoleBinding` | Who can call which API verbs on which resources | API server authorization |
| RBAC `ClusterRole` + `ClusterRoleBinding` | Same but cluster-wide | API server authorization |
| Gatekeeper `ConstraintTemplate` | Policy logic (Rego) | Admission webhook |
| Gatekeeper `Constraint` | Where and to what the policy applies | Admission webhook |
| `kubectl auth can-i` | Test RBAC permissions | Dry-run check |

---

## Next steps

➡️ [Module 6, Lesson 2 — Network Policy: Cilium and Namespace Isolation](../2.lesson-network-policy/unit-1.md)
