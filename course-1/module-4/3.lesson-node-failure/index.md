---
kind: lesson
title: "Node Failure: Simulating and Recovering from a Node Loss"
description: |
  Kill the RKE2 agent on vm4 to simulate a hard node failure, observe Kubernetes
  detect the failure and reschedule pods automatically, then bring the node back
  and watch it rejoin the cluster cleanly.
name: lesson-node-failure
slug: lesson-node-failure
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
tagz:
  - node-failure
  - rescheduling
  - resilience
  - rke2
playground:
  name: flexbox
tasks:
  verify_vm4_notready:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get node vm4 --no-headers | grep -q NotReady \
        || { echo "vm4 is still Ready — stop the rke2-agent first"; exit 1; }
      echo "vm4 NotReady ✓"

  verify_pods_rescheduled:
    machine: bootstrap
    user: laborant
    needs:
      - verify_vm4_notready
    run: |
      PENDING=$(kubectl get pods -l app=failure-test --no-headers | grep -c Pending || echo 0)
      [ "$PENDING" -eq 0 ] || { echo "$PENDING pods still Pending"; exit 1; }
      echo "All pods rescheduled and Running ✓"

  verify_vm4_rejoined:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get node vm4 --no-headers | grep -q ' Ready ' \
        || { echo "vm4 has not rejoined"; exit 1; }
      echo "vm4 rejoined and Ready ✓"
---
