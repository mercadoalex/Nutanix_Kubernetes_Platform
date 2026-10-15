---
kind: lesson
title: "What is Air-Gapped? (and why NKP is built for it)"
description: |
  Enterprise Kubernetes clusters often run in environments with no outbound
  internet access. This lesson explains what air-gapped means, why it matters,
  and how NKP handles it — with Harbor as the local registry mirror that keeps
  everything working offline.
name: lesson-air-gap
slug: lesson-air-gap
createdAt: 2026-10-10
updatedAt: 2026-10-10
categories:
  - kubernetes
  - cloud
  - security
tagz:
  - air-gap
  - harbor
  - registry
tasks:
  verify_harbor_running:
    machine: bootstrap
    user: laborant
    run: |
      curl -sf http://localhost:5000/v2/ > /dev/null 2>&1 \
        || curl -sf http://172.16.0.10:80/api/v2.0/ping > /dev/null 2>&1 \
        || { echo "Harbor not reachable — check the registry service"; exit 1; }
      echo "Harbor registry reachable ✓"
    hintcheck: |
      echo "Try: curl http://172.16.0.10:80/api/v2.0/ping"
      echo "Harbor should be running on vm1 (bootstrap). Check with: docker ps"
---
