---
kind: lesson
title: "Bootstrap the RKE2 Control Plane"
description: |
  Start RKE2 server on vm2, watch etcd and kube-apiserver come up, copy the
  kubeconfig to vm1, and run your first kubectl get nodes.
name: lesson-rke2-bootstrap
slug: lesson-rke2-bootstrap
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - rke2
  - etcd
  - kubeconfig
playground:
  name: flexbox
tasks:
  verify_rke2_running:
    machine: controlplane
    user: root
    run: |
      systemctl is-active rke2-server || { echo "rke2-server not active"; exit 1; }
      echo "rke2-server is active ✓"

  verify_node_ready:
    machine: bootstrap
    user: laborant
    needs:
      - verify_rke2_running
    run: |
      export KUBECONFIG=/home/laborant/.kube/config
      READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo 0)
      [ "$READY" -ge 1 ] || { echo "No Ready nodes found"; exit 1; }
      echo "$READY node(s) Ready ✓"
---
