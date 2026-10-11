# Lesson 3.2 — Workloads: Deployments, Services, ConfigMaps, and Storage

> **Tier:** 2 — Single-VM interactive
> **Playground:** single vm1 (bootstrap image, pre-loaded cluster kubeconfig)
> **VMs used:** vm1 only
> **Duration:** ~35 minutes

---

## What you will do

Build and operate the core Kubernetes workload primitives you will use in every Tier 3 lab:

- **Deployment** — declare desired state for a set of pods
- **Service** — expose pods on a stable network endpoint
- **ConfigMap** — inject configuration without rebuilding images
- **PersistentVolumeClaim** — request durable storage for stateful workloads

All steps run against the pre-loaded cluster from Lesson 3.1. No new infrastructure needed.

---

## Part 1 — Deployments

A Deployment describes a desired number of identical pod replicas and manages rolling updates and rollbacks.

### 1.1 Create a Deployment

```bash
kubectl create deployment web --image=nginx:alpine --replicas=3
```

### 1.2 Inspect it

```bash
kubectl get deployment web
kubectl get replicaset -l app=web
kubectl get pods -l app=web -o wide
```

Notice:
- The Deployment created a **ReplicaSet** automatically
- Each pod lands on a different node (scheduler spreads by default)
- Pod names follow: `web-<replicaset-hash>-<pod-hash>`

### 1.3 Rolling update

Update the image version:

```bash
kubectl set image deployment/web nginx=nginx:1.27-alpine
kubectl rollout status deployment/web
```

```
Waiting for deployment "web" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "web" rollout to finish: 2 out of 3 new replicas have been updated...
deployment "web" successfully rolled out
```

Kubernetes replaced pods one at a time — zero downtime.

### 1.4 Rollback

```bash
kubectl rollout history deployment/web
kubectl rollout undo deployment/web
kubectl rollout status deployment/web
```

### 1.5 Scale

```bash
kubectl scale deployment web --replicas=5
kubectl get pods -l app=web -o wide
```

### 1.6 Clean up

```bash
kubectl delete deployment web
```

---

## Part 2 — Services

A Service gives a stable IP and DNS name to a group of pods. Without a Service, pod IPs change every restart.

### 2.1 Deploy an app

```bash
kubectl create deployment app --image=nginx:alpine --replicas=2
```

### 2.2 ClusterIP Service (internal only)

```bash
kubectl expose deployment app --port=80 --target-port=80 --name=app-svc
kubectl get service app-svc
```

```
NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
app-svc   ClusterIP   10.43.12.100   <none>        80/TCP    5s
```

The `CLUSTER-IP` is stable — it never changes even if pods are replaced. Test it from another pod:

```bash
kubectl run curl --image=curlimages/curl --restart=Never --rm -it -- \
    curl -s http://app-svc/
```

### 2.3 NodePort Service (reachable from outside the cluster)

```bash
kubectl expose deployment app --port=80 --target-port=80 \
    --name=app-nodeport --type=NodePort
kubectl get service app-nodeport
```

```
NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
app-nodeport   NodePort   10.43.12.101   <none>        80:31234/TCP   5s
```

Reach it from vm1 using any node IP and the assigned port:

```bash
curl http://172.16.0.11:31234/
```

### 2.4 Service DNS

Every Service gets a DNS name inside the cluster:

```
<service-name>.<namespace>.svc.cluster.local
```

Test:

```bash
kubectl run curl --image=curlimages/curl --restart=Never --rm -it -- \
    curl -s http://app-svc.default.svc.cluster.local/
```

### 2.5 Clean up

```bash
kubectl delete deployment app
kubectl delete service app-svc app-nodeport
```

---

## Part 3 — ConfigMaps

ConfigMaps decouple configuration from container images. You change the ConfigMap — not the image — when config needs updating.

### 3.1 Create a ConfigMap from literals

```bash
kubectl create configmap app-config \
    --from-literal=APP_ENV=production \
    --from-literal=LOG_LEVEL=info
kubectl describe configmap app-config
```

### 3.2 Create a ConfigMap from a file

```bash
cat > nginx.conf <<'EOF'
server {
    listen 80;
    location /health {
        return 200 "ok\n";
    }
}
EOF
kubectl create configmap nginx-config --from-file=nginx.conf
```

### 3.3 Mount a ConfigMap as environment variables

```yaml
# env-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-pod
spec:
  containers:
    - name: app
      image: busybox:stable
      command: ["sh", "-c", "echo APP_ENV=$APP_ENV LOG_LEVEL=$LOG_LEVEL && sleep 3600"]
      envFrom:
        - configMapRef:
            name: app-config
```

```bash
kubectl apply -f env-pod.yaml
kubectl logs env-pod
```

```
APP_ENV=production LOG_LEVEL=info
```

### 3.4 Mount a ConfigMap as a volume (file)

```yaml
# vol-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: vol-pod
spec:
  volumes:
    - name: config-vol
      configMap:
        name: nginx-config
  containers:
    - name: nginx
      image: nginx:alpine
      volumeMounts:
        - name: config-vol
          mountPath: /etc/nginx/conf.d/
```

```bash
kubectl apply -f vol-pod.yaml
kubectl exec vol-pod -- cat /etc/nginx/conf.d/nginx.conf
```

### 3.5 Clean up

```bash
kubectl delete pod env-pod vol-pod
kubectl delete configmap app-config nginx-config
```

---

## Part 4 — PersistentVolumeClaims

A PersistentVolumeClaim (PVC) requests durable storage from the cluster. The storage survives pod restarts — unlike the container filesystem.

### 4.1 Check available StorageClasses

```bash
kubectl get storageclass
```

The lab cluster has `local-path` provisioner (provided by RKE2) as the default:

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

In a production NKP cluster on AHV you would also see the Nutanix CSI StorageClass here.

### 4.2 Create a PVC

```yaml
# my-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f my-pvc.yaml
kubectl get pvc my-pvc
```

```
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
my-pvc   Pending   —        —          RWO            local-path     5s
```

Status is `Pending` — `local-path` uses `WaitForFirstConsumer`, meaning the volume is not provisioned until a pod actually mounts it.

### 4.3 Mount the PVC in a pod

```yaml
# storage-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-pod
spec:
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-pvc
  containers:
    - name: writer
      image: busybox:stable
      command: ["sh", "-c", "echo 'Hello from PVC' > /data/hello.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
```

```bash
kubectl apply -f storage-pod.yaml
kubectl get pvc my-pvc
```

PVC is now `Bound`:

```
NAME     STATUS   VOLUME                                     CAPACITY   ACCESS MODES
my-pvc   Bound    pvc-abc123...                              1Gi        RWO
```

```bash
kubectl exec storage-pod -- cat /data/hello.txt
```

```
Hello from PVC
```

### 4.4 Verify data survives pod deletion

```bash
kubectl delete pod storage-pod
kubectl apply -f storage-pod.yaml
kubectl exec storage-pod -- cat /data/hello.txt
```

```
Hello from PVC
```

The data persisted across pod deletion and recreation.

### 4.5 Clean up

```bash
kubectl delete pod storage-pod
kubectl delete pvc my-pvc
```

---

## Summary

| Resource | Purpose | Key command |
|---|---|---|
| Deployment | Manage N identical pod replicas | `kubectl create deployment` |
| Service ClusterIP | Internal stable endpoint | `kubectl expose --type=ClusterIP` |
| Service NodePort | External access via node IP | `kubectl expose --type=NodePort` |
| ConfigMap | Inject config as env vars or files | `kubectl create configmap` |
| PVC | Request durable storage | `kubectl apply -f pvc.yaml` |
| Rolling update | Zero-downtime image change | `kubectl set image` / `kubectl rollout` |
| Rollback | Revert to previous version | `kubectl rollout undo` |

---

## Next steps

➡️ [Module 4, Lesson 1 — Bootstrap & Pivot: Building the Management Cluster](../../module-4/1.lesson-bootstrap-pivot/unit-1.md)
