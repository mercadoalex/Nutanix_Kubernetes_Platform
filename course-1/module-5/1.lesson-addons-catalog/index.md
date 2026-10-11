---
kind: lesson
title: "Add-ons Catalog: Deploying Platform Services with Flux"
description: |
  Deploy cert-manager and Longhorn using Flux HelmRelease and HelmRepository objects.
  Understand how NKP's add-on catalog works and observe Flux's drift correction guarantee.
name: lesson-addons-catalog
slug: lesson-addons-catalog
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
tagz:
  - flux
  - helm
  - cert-manager
  - longhorn
  - storage
playground:
  name: nkp-lab
tasks:
  verify_flux_running:
    machine: bootstrap
    user: laborant
    run: |
      READY=$(kubectl get pods -n flux-system --no-headers | grep -c Running || echo 0)
      [ "$READY" -ge 4 ] || { echo "Flux pods not ready ($READY/4)"; exit 1; }
      echo "Flux system $READY pods Running ✓"

  verify_longhorn_running:
    machine: bootstrap
    user: laborant
    needs:
      - verify_flux_running
    run: |
      kubectl get helmrelease longhorn -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
        | grep -q True || { echo "Longhorn HelmRelease not Ready"; exit 1; }
      echo "Longhorn HelmRelease Ready ✓"
---
