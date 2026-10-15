---
kind: lesson
title: "Cilium: NKP's Default CNI — Deep Dive"
description: |
  Why did NKP choose Cilium over Calico, Flannel, or Weave? The answer is eBPF.
  This lesson explains how eBPF replaces iptables, how Hubble gives you L7
  observability across your cluster, and how to write CiliumNetworkPolicy
  for L3, L4, and L7 rules — with a full hands-on lab on the 5-VM cluster.
name: lesson-cilium
slug: lesson-cilium
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - networking
tagz:
  - cilium
  - ebpf
  - cni
  - hubble
  - network-policy
playground:
  name: nkp-lab-b2fa17d3
tasks:
  verify_cilium_status:
    machine: bootstrap
    user: laborant
    run: |
      cilium status --wait 2>/dev/null | grep -q "OK" \
        || kubectl -n kube-system get pods -l k8s-app=cilium \
           | grep -q "Running" \
        || { echo "Cilium is not healthy — check: kubectl -n kube-system get pods -l k8s-app=cilium"; exit 1; }
      echo "Cilium is healthy ✓"

  verify_hubble_flows:
    machine: bootstrap
    user: laborant
    needs:
      - verify_cilium_status
    run: |
      hubble observe --last 1 > /dev/null 2>&1 \
        || { echo "Hubble CLI not working — check: cilium hubble enable"; exit 1; }
      echo "Hubble flows visible ✓"
    hintcheck: |
      echo "Enable Hubble if not already enabled:"
      echo "  cilium hubble enable"
      echo "Then port-forward: cilium hubble port-forward &"

  verify_network_policy:
    machine: bootstrap
    user: laborant
    needs:
      - verify_cilium_status
    run: |
      kubectl get ciliumnetworkpolicy -A 2>/dev/null | grep -q "." \
        || { echo "No CiliumNetworkPolicy found — apply the policy from the lab steps"; exit 1; }
      echo "CiliumNetworkPolicy applied ✓"
    hintcheck: |
      echo "Apply the demo network policy from the lab:"
      echo "  kubectl apply -f /home/laborant/labs/cilium/demo-policy.yaml"
---
