---
kind: course
title: |-
  NKP — Nutanix Kubernetes Platform: From Zero to Production

description: |-
  A hands-on course for platform engineers who need to deploy, operate, and troubleshoot
  NKP (Nutanix Kubernetes Platform) — Nutanix's enterprise Kubernetes fleet management
  system. You will build a real multi-node RKE2 cluster from scratch inside 5 Firecracker
  microVMs, install the full NKP stack, and operate it the way production teams do.

categories:
- kubernetes
- containers
- cloud

tagz:
- nkp
- rke2
- capi
- kommander
- flux

createdAt: 2026-10-10
updatedAt: 2026-10-10

cover: __static__/cover.png

---

## What you'll learn

- The NKP architecture: Bootstrap, Management, Workload, and Attached clusters
- How Cluster API (CAPI) + RKE2 + Flux CD + Kommander work together
- Deploy a full 5-node RKE2 cluster inside iximious Flexbox microVMs
- Install and configure NKP add-ons: Cilium, MetalLB, Longhorn, Traefik, Prometheus, Grafana
- Day-2 operations: node drain/cordon, rolling restarts, Ansible automation
- GitOps with Flux CD — managing cluster state declaratively
- RBAC, policy, and multi-tenancy in NKP Kommander
- GPU workloads on NKP: device plugin, time-slicing, MIG

## Lab environment

All hands-on labs run inside **iximious Flexbox** — 5 Firecracker microVMs on a
shared flat L2 network. No cloud account or physical hardware required.

| VM | IP | Role | OS |
|---|---|---|---|
| `bootstrap` | `172.16.0.10` | Operator workstation (`nkp` CLI, `kind`, `k9s`, Ansible) | Ubuntu 24.04 |
| `controlplane` | `172.16.0.11` | RKE2 server (kube-apiserver, etcd, scheduler) | Rocky Linux 9.7 |
| `worker-01` | `172.16.0.12` | RKE2 agent | Rocky Linux 9.7 |
| `worker-02` | `172.16.0.13` | RKE2 agent | Rocky Linux 9.7 |
| `worker-03` | `172.16.0.14` | RKE2 agent | Rocky Linux 9.7 |

## Prerequisites

- Familiarity with Kubernetes basics (pods, deployments, services)
- Basic Linux command line (SSH, systemctl, journalctl)
- No Nutanix experience required — everything is explained from scratch

