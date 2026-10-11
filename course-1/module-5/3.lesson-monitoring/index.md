---
kind: lesson
title: "Monitoring: Prometheus and Grafana"
description: |
  Deploy the kube-prometheus-stack via Flux, explore pre-built Kubernetes dashboards
  in Grafana, write PromQL queries to inspect cluster metrics, and create a custom
  Alertmanager rule for node memory pressure.
name: lesson-monitoring
slug: lesson-monitoring
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - observability
tagz:
  - prometheus
  - grafana
  - alertmanager
  - promql
  - monitoring
playground:
  name: nkp-lab
tasks:
  verify_prometheus_running:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get helmrelease kube-prometheus-stack -n monitoring \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
        | grep -q True || { echo "kube-prometheus-stack not Ready"; exit 1; }
      echo "kube-prometheus-stack Ready ✓"

  verify_grafana_accessible:
    machine: bootstrap
    user: laborant
    needs:
      - verify_prometheus_running
    run: |
      NODE_PORT=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring \
        -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
      curl -s -o /dev/null -w "%{http_code}" http://172.16.0.11:${NODE_PORT}/login \
        | grep -q 200 || { echo "Grafana not reachable"; exit 1; }
      echo "Grafana reachable on port $NODE_PORT ✓"
---
