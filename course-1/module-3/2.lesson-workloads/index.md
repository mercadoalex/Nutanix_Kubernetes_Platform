---
kind: lesson
title: "Workloads: Deployments, Services, ConfigMaps, and Storage"
description: |
  Build and operate the core Kubernetes workload primitives — Deployments, Services,
  ConfigMaps, and PersistentVolumeClaims — with hands-on exercises on a live cluster.
name: lesson-workloads
slug: lesson-workloads
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
tagz:
  - deployment
  - service
  - configmap
  - pvc
  - storage
playground:
  name: nkp-lab
tasks:
  verify_deployment_running:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get deployment web --no-headers 2>/dev/null | grep -q '3/3' \
        || { echo "Deployment 'web' not ready"; exit 1; }
      echo "Deployment web 3/3 Ready ✓"
---
