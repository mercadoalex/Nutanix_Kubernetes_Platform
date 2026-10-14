---
kind: lesson
title: "RBAC & Policy: ClusterRoles, RoleBindings, and OPA/Gatekeeper"
description: |
  Control who can call which Kubernetes API verbs with RBAC Roles and ClusterRoles.
  Enforce what workloads are allowed to run using OPA/Gatekeeper ConstraintTemplates
  and Constraints — the two-layer security model used in production NKP clusters.
name: lesson-rbac-policy
slug: lesson-rbac-policy
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - security
tagz:
  - rbac
  - clusterrole
  - rolebinding
  - gatekeeper
  - policy
playground:
  name: nkp-lab-b2fa17d3
tasks:
  verify_rbac_deny:
    machine: bootstrap
    user: laborant
    run: |
      RESULT=$(kubectl auth can-i delete pods -n default \
        --as=system:serviceaccount:default:dev-user 2>/dev/null)
      [ "$RESULT" = "no" ] || { echo "dev-user can delete pods — RBAC not applied correctly"; exit 1; }
      echo "dev-user cannot delete pods ✓"

  verify_gatekeeper_running:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get pods -n gatekeeper-system --no-headers | grep -q Running \
        || { echo "Gatekeeper not running"; exit 1; }
      echo "Gatekeeper running ✓"

  verify_policy_enforced:
    machine: bootstrap
    user: laborant
    needs:
      - verify_gatekeeper_running
    run: |
      kubectl create deployment policy-test --image=nginx:alpine --dry-run=server 2>&1 \
        | grep -q "denied" || { echo "Gatekeeper did not block the deployment"; exit 1; }
      echo "Gatekeeper blocked deployment without resource limits ✓"
---
