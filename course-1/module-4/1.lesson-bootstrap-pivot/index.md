---
kind: lesson
title: "Bootstrap & Pivot: Building the Management Cluster"
description: |
  Start the kind Bootstrap Cluster on vm1, bring up the RKE2 server on vm2, join
  vm3-5 as workers, copy the kubeconfig, and delete the Bootstrap Cluster — the
  hands-on replay of what nkp create cluster + nkp move does on real AHV.
name: lesson-bootstrap-pivot
slug: lesson-bootstrap-pivot
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - rke2
  - bootstrap
  - nkp-move
  - capi
  - kind
playground:
  name: nkp-lab-b2fa17d3
tasks:
  verify_rke2_server:
    machine: controlplane
    user: root
    run: |
      systemctl is-active rke2-server || { echo "rke2-server not active"; exit 1; }
      echo "rke2-server active ✓"

  verify_all_nodes_ready:
    machine: bootstrap
    user: laborant
    needs:
      - verify_rke2_server
    run: |
      READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)
      [ "$READY" -ge 4 ] || { echo "Expected 4 Ready nodes, got $READY"; exit 1; }
      echo "$READY/4 nodes Ready ✓"

  verify_bootstrap_deleted:
    machine: bootstrap
    user: laborant
    needs:
      - verify_all_nodes_ready
    run: |
      kind get clusters 2>/dev/null | grep -q . && { echo "Bootstrap cluster still exists"; exit 1; }
      echo "Bootstrap cluster deleted ✓"
---
