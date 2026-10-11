---
kind: lesson
title: "kubectl Basics: Day-2 Cluster Operations"
description: |
  Master the kubectl commands you use every day — listing resources, reading logs,
  exec into containers, applying manifests, and reading events for troubleshooting.
name: lesson-kubectl-basics
slug: lesson-kubectl-basics
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
tagz:
  - kubectl
  - pods
  - logs
  - events
  - troubleshooting
playground:
  name: nkp-lab
tasks:
  verify_kubectl_works:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get nodes --no-headers | grep -c Ready | grep -q '[1-9]' \
        || { echo "No Ready nodes"; exit 1; }
      echo "kubectl working, nodes Ready ✓"
---
