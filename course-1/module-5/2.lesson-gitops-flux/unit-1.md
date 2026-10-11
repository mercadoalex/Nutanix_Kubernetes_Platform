---
kind: unit
title: "Lesson 5.2 — GitOps with Flux: The Full Loop"
name: 2-lesson-gitops-flux-unit-1
---

# Lesson 5.2 — GitOps with Flux: The Full Loop

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 5.1 complete — Flux running, Longhorn deployed
> **Duration:** ~40 minutes

---

## What you will do

Build and exercise a complete GitOps workflow:

1. Create a Git repository that declares cluster state
2. Connect Flux to that repository with a `GitRepository` source
3. Deploy an application by pushing a manifest to Git — no `kubectl apply` needed
4. Update the application by pushing a change to Git
5. Observe drift detection and automatic remediation

This is how NKP manages everything in a production cluster — every add-on, every policy, every configuration change goes through Git.

---

## The GitOps principle

```
Git repository          Flux (in-cluster)         Cluster state
─────────────           ─────────────────         ─────────────
manifests/              source-controller          running pods
  deployment.yaml  ──►  watches repo         ──►  deployments
  service.yaml          kustomize-controller       services
  configmap.yaml        detects drift              configmaps
                        reconciles every 1m
```

**Git is the single source of truth.** Anything applied directly with `kubectl` that is not in Git will be overwritten on the next reconciliation cycle.

---

## Part 1 — Set up a Git repository

For this lab we use a local bare Git repository served over HTTP from vm1. In production you would use GitHub, GitLab, Gitea, or any Git server.

### 1.1 Create a bare repository on vm1

```bash
mkdir -p /srv/git/nkp-gitops.git
git init --bare /srv/git/nkp-gitops.git
```

### 1.2 Serve it over HTTP

```bash
# Install git's HTTP backend (already available via git package)
cd /srv/git/nkp-gitops.git
git config http.receivepack true

# Serve with Python's built-in HTTP server + git's smart HTTP
# For a production setup use Gitea or Forgejo
nohup git daemon \
    --reuseaddr \
    --base-path=/srv/git \
    --export-all \
    --enable=receive-pack \
    /srv/git &

echo "Git daemon running on git://172.16.0.10/nkp-gitops.git"
```

### 1.3 Create a working clone

```bash
cd ~
git clone git://172.16.0.10/nkp-gitops.git
cd nkp-gitops
git config user.email "lab@nkp.local"
git config user.name "NKP Lab"
```

---

## Part 2 — Declare initial application state

### 2.1 Create the directory structure

```bash
mkdir -p apps/web
```

### 2.2 Write the manifests

```bash
cat > apps/web/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: web
EOF

cat > apps/web/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.26-alpine
          ports:
            - containerPort: 80
EOF

cat > apps/web/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: web
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

cat > apps/web/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
EOF
```

### 2.3 Commit and push

```bash
git add .
git commit -m "feat: add web application"
git push origin main
```

---

## Part 3 — Connect Flux to the repository

### 3.1 Create a GitRepository source

```yaml
# gitops-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: nkp-gitops
  namespace: flux-system
spec:
  interval: 1m
  url: git://172.16.0.10/nkp-gitops.git
  ref:
    branch: main
```

```bash
kubectl apply -f gitops-source.yaml
flux get source git -n flux-system
```

```
NAME         REVISION        SUSPENDED  READY  MESSAGE
nkp-gitops   main/abc1234    False      True   stored artifact for revision...
```

### 3.2 Create a Kustomization to deploy the apps

```yaml
# gitops-apps.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  path: ./apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: nkp-gitops
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: web
      namespace: web
```

```bash
kubectl apply -f gitops-apps.yaml
```

`prune: true` — if you delete a manifest from Git, Flux deletes the resource from the cluster. Git is authoritative.

### 3.3 Watch Flux deploy the application

```bash
flux get kustomization -n flux-system -w
```

```
NAME   REVISION       SUSPENDED  READY  MESSAGE
apps   main/abc1234   False      True   Applied revision: main/abc1234
```

```bash
kubectl get all -n web
```

```
NAME                       READY   STATUS    NODE
pod/web-xxx-aaa            1/1     Running   vm3
pod/web-xxx-bbb            1/1     Running   vm4
pod/web-xxx-ccc            1/1     Running   vm5

NAME          TYPE        CLUSTER-IP
service/web   ClusterIP   10.43.x.x

NAME                READY   UP-TO-DATE   AVAILABLE
deployment.apps/web 3/3     3            3
```

The application is running — and you never ran `kubectl apply`.

---

## Part 4 — Update via Git

### 4.1 Change the image version

```bash
cd ~/nkp-gitops
sed -i 's/nginx:1.26-alpine/nginx:1.27-alpine/' apps/web/deployment.yaml
git add apps/web/deployment.yaml
git commit -m "chore: bump nginx to 1.27-alpine"
git push origin main
```

### 4.2 Watch Flux apply the change

Flux polls every 1 minute. Force an immediate reconciliation:

```bash
flux reconcile kustomization apps -n flux-system
```

```bash
kubectl rollout status deployment/web -n web
```

```
deployment "web" successfully rolled out
```

```bash
kubectl get pods -n web -o jsonpath='{.items[*].spec.containers[*].image}'
```

```
nginx:1.27-alpine nginx:1.27-alpine nginx:1.27-alpine
```

All pods updated to the new image — triggered by a Git push, applied by Flux.

---

## Part 5 — Drift detection

### 5.1 Manually change a replica count

```bash
kubectl scale deployment web -n web --replicas=1
kubectl get pods -n web
```

```
NAME           READY   STATUS
web-xxx-aaa    1/1     Running    ← only 1 pod
```

### 5.2 Wait for Flux to correct it

Flux reconciles every 1 minute. Watch:

```bash
kubectl get pods -n web -w
```

Within 60 seconds:

```
web-xxx-bbb   0/1   Pending   0   1s    ← Flux restored replicas=3
web-xxx-ccc   0/1   Pending   0   1s
web-xxx-bbb   1/1   Running   0   5s
web-xxx-ccc   1/1   Running   0   5s
```

The manual change was overwritten. Git said `replicas: 3`. Flux enforced it.

---

## Part 6 — Prune: delete a resource via Git

### 6.1 Remove the service from Git

```bash
cd ~/nkp-gitops
# Remove service from kustomization
sed -i '/- service.yaml/d' apps/web/kustomization.yaml
git add apps/web/kustomization.yaml
git commit -m "chore: remove service (testing prune)"
git push origin main
flux reconcile kustomization apps -n flux-system
```

```bash
kubectl get service -n web
```

```
No resources found in web namespace.
```

The Service was deleted from the cluster because it was removed from Git. `prune: true` makes this happen automatically.

### 6.2 Restore it

```bash
echo "  - service.yaml" >> apps/web/kustomization.yaml
git add apps/web/kustomization.yaml
git commit -m "restore: re-add service"
git push origin main
flux reconcile kustomization apps -n flux-system
kubectl get service -n web
```

---

## Summary

| Concept | Resource | Key field |
|---|---|---|
| Where to pull state from | `GitRepository` | `url`, `branch` |
| What to apply from the repo | `Kustomization` | `path`, `prune`, `interval` |
| Drift correction | automatic | Flux reconciles every `interval` |
| Delete-on-remove | `prune: true` | Deletes cluster resources removed from Git |
| Force sync | `flux reconcile kustomization <name>` | Skips the interval wait |

---

## Next steps

➡️ [Module 5, Lesson 3 — Monitoring: Prometheus and Grafana](../3.lesson-monitoring/unit-1.md)
