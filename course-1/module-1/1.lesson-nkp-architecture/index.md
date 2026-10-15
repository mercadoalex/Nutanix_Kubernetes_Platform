---
kind: lesson
title: "NKP Uses Kubernetes to Manage Kubernetes"
description: |
  NKP isn't just one cluster — it's a fleet management system built on Cluster API.
  In this lesson you'll understand the four cluster roles, trace a cluster creation
  request from the nkp CLI all the way down to a running VM, and learn why the
  Bootstrap cluster exists and disappears.
name: lesson-nkp-architecture
slug: lesson-nkp-architecture
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - nkp
  - capi
  - rke2
  - kommander
playground:
  name: nkp-lab-b2fa17d3
tasks:
  verify_tools_ready:
    init: false
    machine: bootstrap
    user: laborant
    run: |
      nkp version > /dev/null 2>&1 || { echo "nkp not found"; exit 1; }
      kubectl version --client > /dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
      kind version > /dev/null 2>&1 || { echo "kind not found"; exit 1; }
      echo "all tools present ✓"

  verify_cluster_roles:
    machine: bootstrap
    user: laborant
    needs:
      - verify_tools_ready
    run: |
      # Student must create /tmp/cluster-roles.txt listing the 4 cluster roles
      [ -f /tmp/cluster-roles.txt ] || { echo "Create /tmp/cluster-roles.txt first"; exit 1; }
      grep -qi "bootstrap" /tmp/cluster-roles.txt || { echo "Missing: Bootstrap Cluster"; exit 1; }
      grep -qi "management" /tmp/cluster-roles.txt || { echo "Missing: Management Cluster"; exit 1; }
      grep -qi "workload\|managed" /tmp/cluster-roles.txt || { echo "Missing: Workload/Managed Cluster"; exit 1; }
      grep -qi "attached" /tmp/cluster-roles.txt || { echo "Missing: Attached Cluster"; exit 1; }
      echo "All 4 cluster roles identified ✓"
    hintcheck: |
      echo "The file should list all 4 NKP cluster roles, one per line:"
      echo "  Bootstrap, Management, Workload (Managed), Attached"

  verify_capx_namespace:
    machine: bootstrap
    user: laborant
    needs:
      - verify_cluster_roles
    run: |
      # Student must create /tmp/capx-namespace.txt with the correct namespace
      [ -f /tmp/capx-namespace.txt ] || { echo "Create /tmp/capx-namespace.txt first"; exit 1; }
      grep -q "capx-system" /tmp/capx-namespace.txt || { echo "Wrong namespace — check the CAPX section"; exit 1; }
      echo "CAPX namespace correct ✓"
    hintcheck: |
      echo "Re-read the 'CAPX — the Nutanix provider' section."
      echo "The namespace is mentioned explicitly."
---
