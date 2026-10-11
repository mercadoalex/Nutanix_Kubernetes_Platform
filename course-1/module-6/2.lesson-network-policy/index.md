---
kind: lesson
title: "Network Policy: Cilium and Namespace Isolation"
description: |
  Apply default-deny ingress and egress policies to a namespace, selectively allow
  only the traffic you need, and use CiliumNetworkPolicy to enforce HTTP path-level
  L7 rules — implementing zero-trust namespace isolation with the NKP default CNI.
name: lesson-network-policy
slug: lesson-network-policy
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - security
  - networking
tagz:
  - cilium
  - network-policy
  - zero-trust
  - namespace-isolation
  - l7
playground:
  name: flexbox
tasks:
  verify_default_deny:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get networkpolicy default-deny-ingress -n backend &>/dev/null \
        || { echo "default-deny-ingress policy not found in backend namespace"; exit 1; }
      echo "default-deny-ingress policy applied ✓"

  verify_traffic_blocked:
    machine: bootstrap
    user: laborant
    needs:
      - verify_default_deny
    run: |
      RESULT=$(kubectl run curl-test --image=curlimages/curl --restart=Never --rm \
        --namespace=default -q \
        -- curl -s --max-time 3 http://backend-svc.backend.svc.cluster.local/ 2>&1 || true)
      echo "$RESULT" | grep -qiE "timed out|Connection refused|Could not resolve" \
        || { echo "Traffic not blocked — policy may not be applied"; exit 1; }
      echo "Cross-namespace traffic blocked ✓"
---
