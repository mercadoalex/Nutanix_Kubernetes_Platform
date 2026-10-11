---
kind: lesson
title: "The NKP CLI: kubeconfig, Contexts, and Cluster Access"
description: |
  Master the nkp CLI commands for retrieving kubeconfigs, switching cluster contexts,
  and confirming cluster identity — the daily workflow after any cluster is deployed.
name: lesson-nkp-cli
slug: lesson-nkp-cli
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - nkp
  - kubectl
  - kubeconfig
  - contexts
playground:
  name: flexbox
tasks:
  verify_kubectl_context:
    machine: bootstrap
    user: laborant
    run: |
      kubectl config current-context || { echo "No active context"; exit 1; }
      echo "Active context: $(kubectl config current-context) ✓"
---
