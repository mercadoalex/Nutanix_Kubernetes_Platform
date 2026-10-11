# Lesson 5.3 — Monitoring: Prometheus and Grafana

> **Tier:** 3 — Full Flexbox (5 VMs)
> **Playground:** `nkp-flexbox.yaml`
> **VMs used:** all five
> **Prerequisite:** Lesson 5.1 complete — Flux running
> **Duration:** ~40 minutes

---

## What you will do

Deploy the NKP observability stack and use it to monitor your cluster:

1. Deploy **Prometheus** (metrics collection) and **Grafana** (visualization) via Flux HelmReleases
2. Explore the pre-built Kubernetes dashboards
3. Write a PromQL query to inspect node and pod metrics
4. Set up an Alertmanager rule that fires when a node's memory usage exceeds a threshold

---

## The NKP observability stack

```
Node exporters (every node)
  └─► scrapes OS metrics (CPU, memory, disk, network)

kube-state-metrics
  └─► scrapes Kubernetes object metrics (pod restarts, deployment health)

Prometheus
  └─► stores all metrics with a 15-day retention window
  └─► evaluates alerting rules → Alertmanager

Alertmanager
  └─► routes alerts to Slack / PagerDuty / email

Grafana
  └─► queries Prometheus → renders dashboards
  └─► pre-built dashboards: Node Exporter, Kubernetes cluster, Pods
```

---

## Part 1 — Deploy kube-prometheus-stack

The `kube-prometheus-stack` Helm chart bundles Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics in a single release.

### 1.1 HelmRepository and HelmRelease

```yaml
# monitoring.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kube-prometheus-stack
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: kube-prometheus-stack
      version: "65.x"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    prometheus:
      prometheusSpec:
        retention: 7d
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: longhorn
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
    grafana:
      adminPassword: "nkp-lab-grafana"
      persistence:
        enabled: true
        storageClassName: longhorn
        size: 2Gi
      service:
        type: NodePort
    alertmanager:
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: longhorn
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 2Gi
```

```bash
kubectl create namespace monitoring
kubectl apply -f monitoring.yaml
```

### 1.2 Wait for the stack to be ready

This takes 5–8 minutes — Prometheus needs to create its PVC and load the Longhorn volume:

```bash
flux get helmrelease kube-prometheus-stack -n monitoring -w
```

```bash
kubectl get pods -n monitoring
```

Wait for all pods to be `Running`:

```
NAME                                              READY   STATUS
alertmanager-kube-prometheus-stack-xxx            2/2     Running
kube-prometheus-stack-grafana-xxx                 3/3     Running
kube-prometheus-stack-kube-state-metrics-xxx      1/1     Running
kube-prometheus-stack-operator-xxx                1/1     Running
kube-prometheus-stack-prometheus-node-exporter-xxx (×4) 1/1 Running
prometheus-kube-prometheus-stack-prometheus-xxx   2/2     Running
```

---

## Part 2 — Access Grafana

### 2.1 Get the NodePort

```bash
kubectl get service kube-prometheus-stack-grafana -n monitoring
```

```
NAME                              TYPE       PORT(S)
kube-prometheus-stack-grafana     NodePort   80:3xxxx/TCP
```

### 2.2 Open in browser

```
http://172.16.0.11:<nodeport>
```

Login: `admin` / `nkp-lab-grafana`

### 2.3 Explore pre-built dashboards

Navigate to **Dashboards** → **Browse**. Key dashboards:

| Dashboard | What it shows |
|---|---|
| **Kubernetes / Compute Resources / Cluster** | Cluster-wide CPU and memory usage |
| **Kubernetes / Compute Resources / Node** | Per-node breakdown |
| **Kubernetes / Compute Resources / Pod** | Per-pod CPU/memory |
| **Node Exporter / Nodes** | OS-level: disk I/O, network, CPU modes |
| **Kubernetes / Persistent Volumes** | PVC usage and Longhorn volume health |

Click **Kubernetes / Compute Resources / Cluster**. You will see:

- CPU usage across all 4 nodes (vm2–vm5)
- Memory usage with requests/limits comparison
- Network traffic per namespace

---

## Part 3 — PromQL queries

Prometheus uses **PromQL** (Prometheus Query Language) to select and aggregate metrics.

### 3.1 Open the Prometheus UI

```bash
kubectl get service kube-prometheus-stack-prometheus -n monitoring
# Access on port 9090 via NodePort
```

Or query from within the cluster:

```bash
kubectl run prom-query --image=curlimages/curl --restart=Never --rm -it -- \
    curl -sG 'http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/query' \
    --data-urlencode 'query=up'
```

### 3.2 Useful PromQL examples

Run these in the Grafana Explore view (**Explore** → select Prometheus datasource):

```promql
# Is every node up?
up{job="node-exporter"}

# CPU usage per node (percentage)
100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage per node (percentage)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod restart count (spot crashlooping pods)
increase(kube_pod_container_status_restarts_total[1h]) > 0

# Disk usage per node
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Number of running pods per node
count by (node) (kube_pod_info{node!=""})
```

### 3.3 Generate load to see metrics change

```bash
kubectl run load --image=busybox:stable --restart=Never -- \
    sh -c "while true; do dd if=/dev/zero of=/dev/null bs=1M count=100; done"
```

Watch the CPU metric spike on the node where this pod lands. Kill it:

```bash
kubectl delete pod load
```

---

## Part 4 — Alerting rules

### 4.1 Create a custom PrometheusRule

```yaml
# memory-alert.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: node-memory-alert
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: node.memory
      rules:
        - alert: NodeMemoryHigh
          expr: |
            (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Node {{ $labels.instance }} memory > 80%"
            description: "Node memory usage is {{ $value | humanize }}%"
```

```bash
kubectl apply -f memory-alert.yaml
```

### 4.2 Verify the rule is loaded

```bash
# Check Prometheus picked up the rule
kubectl exec -n monitoring \
    $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o name | head -1) \
    -- promtool check rules /etc/prometheus/rules/*/*
```

### 4.3 View firing alerts

In the Grafana sidebar: **Alerting** → **Alert rules** → look for `NodeMemoryHigh`.

In Prometheus UI: **Alerts** → shows all rules and their current state (`Inactive`, `Pending`, `Firing`).

---

## Part 5 — Inspect metrics from the CLI

```bash
# List all available metric names
kubectl exec -n monitoring \
    $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o name | head -1) \
    -- promtool query series http://localhost:9090 --match='kube_node_info'
```

```bash
# Direct API query
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -sG 'http://localhost:9090/api/v1/query' \
    --data-urlencode 'query=kube_node_info' | jq '.data.result[].metric.node'
```

---

## Summary

| Component | What it does | Access |
|---|---|---|
| Prometheus | Scrapes and stores metrics | NodePort 9090 |
| Grafana | Visualizes metrics | NodePort 80 |
| Alertmanager | Routes alerts | NodePort 9093 |
| node-exporter | OS metrics per node | In-cluster only |
| kube-state-metrics | Kubernetes object metrics | In-cluster only |
| PrometheusRule | Custom alerting rules | `kubectl apply` |

---

## Next steps

➡️ [Module 6, Lesson 1 — RBAC & Policy: ClusterRoles and Gatekeeper](../../module-6/1.lesson-rbac-policy/unit-1.md)
