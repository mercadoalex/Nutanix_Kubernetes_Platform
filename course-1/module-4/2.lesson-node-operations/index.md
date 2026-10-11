---
kind: lesson
title: "Node Operations: drain, cordon, taints, and tolerations"
description: |
  Safely take nodes in and out of service using cordon, drain, and uncordon.
  Control workload placement with taints and tolerations. Protect availability
  during maintenance with PodDisruptionBudgets.
name: lesson-node-operations
slug: lesson-node-operations
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
tagz:
  - drain
  - cordon
  - taints
  - tolerations
  - pdb
playground:
  name: flexbox
tasks:
  verify_node_cordoned:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get node vm4 --no-headers | grep -q SchedulingDisabled \
        || { echo "vm4 is not cordoned"; exit 1; }
      echo "vm4 cordoned ✓"

  verify_node_uncordoned:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get node vm4 --no-headers | grep -qv SchedulingDisabled \
        || { echo "vm4 is still cordoned"; exit 1; }
      echo "vm4 uncordoned ✓"
---
