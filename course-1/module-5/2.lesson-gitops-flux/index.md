---
kind: lesson
title: "GitOps with Flux: The Full Loop"
description: |
  Create a Git repository, connect Flux to it with a GitRepository source, deploy
  an application by pushing a manifest, update it via Git push, and observe drift
  detection automatically restore manually deleted resources.
name: lesson-gitops-flux
slug: lesson-gitops-flux
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - gitops
  - flux
  - kustomization
  - drift-detection
playground:
  name: nkp-lab
tasks:
  verify_gitrepo_ready:
    machine: bootstrap
    user: laborant
    run: |
      kubectl get gitrepository nkp-gitops -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
        | grep -q True || { echo "GitRepository not Ready"; exit 1; }
      echo "GitRepository nkp-gitops Ready ✓"

  verify_app_deployed:
    machine: bootstrap
    user: laborant
    needs:
      - verify_gitrepo_ready
    run: |
      READY=$(kubectl get deployment web -n web --no-headers 2>/dev/null | awk '{print $2}' | grep -c '3/3' || echo 0)
      [ "$READY" -eq 1 ] || { echo "Deployment web not 3/3 Ready"; exit 1; }
      echo "Deployment web 3/3 Ready via GitOps ✓"
---
