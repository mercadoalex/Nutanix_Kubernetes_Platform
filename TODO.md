# TODO / Handoff Notes

Open items to revisit as lessons are built out. Not blockers for early labs.

---

## Lesson 06 — Bootstrap & Pivot

### RKE2 image pull latency (deferred)

**Context:**  
The `nkp-controlplane` and `nkp-worker` OCI images no longer include the
RKE2 airgap bundles (`rke2-images*.tar.zst`). The 1.7 GB bundles exceeded
the iximiuz platform's rootfs bake size limit (~1.5 GB uncompressed), causing
`RootfsBaked` failures on every playground start.

**Current behaviour:**  
When a student runs `systemctl start rke2-server` on `controlplane` for the
first time, RKE2 pulls ~1 GB of system images live from `registry.rancher.com`.
This takes **3–5 minutes** before the API server is ready. Worker nodes have a
similar delay on `systemctl start rke2-agent`.

**Options evaluated:**

| Option | Effort | UX |
|---|---|---|
| **A) Re-add `rke2-images-core` only** (595 MB compressed) | Low | Fast control-plane start; Cilium still pulls live |
| **B) Accept live pull + lesson note** | Zero | Students wait 3–5 min; good teaching moment about airgap vs online installs |
| **C) Systemd prefetch service** (pull at VM boot during warm-up) | Medium | Transparent to student; needs testing on iximiuz |
| **D) Local registry on vm1** (Harbor or `registry:2` pre-loaded) | High | Zero pull latency; mirrors production Harbor setup |

**Recommended path when building Lesson 06:**
1. Try **Option A** first — add only `rke2-images-core.linux-amd64.tar.zst`
   back to both Dockerfiles and measure the resulting uncompressed image size.
   Target: ≤ 1.4 GB uncompressed.
2. If it fits under the bake limit, ship with core bundle only.
3. If it doesn't fit, go with **Option B** and add a note in the lesson body:
   > ⏳ RKE2 is pulling its system images (~1 GB) from the internet on first
   > start. This is normal. In production NKP deployments these come from the
   > airgap bundle or your local Harbor registry. Watch progress with:
   > `journalctl -u rke2-server -f`

**Files to edit:**
- [`rootfs/controlplane/Dockerfile`](rootfs/controlplane/Dockerfile) — add `COPY rke2/rke2-images-core.linux-amd64.tar.zst` back
- [`rootfs/worker/Dockerfile`](rootfs/worker/Dockerfile) — same
- [`rootfs/.dockerignore`](rootfs/.dockerignore) — re-add `!rke2/rke2-images-core.linux-amd64.tar.zst`
- [`lessons/06-bootstrap-pivot/README.md`](lessons/06-bootstrap-pivot/README.md) — add pull-wait note if going Option B

---

## General

- [ ] Lesson 06 — write `README.md` (bootstrap kind cluster → pivot to RKE2)
- [ ] Lesson 07 — write `README.md` (node drain, cordon, taints)
- [ ] Lesson 08 — write `README.md` (NKP add-ons via Flux HelmReleases)
- [ ] Lesson 09 — write `README.md` (GitOps loop with Flux)
- [ ] Lesson 10 — write `README.md` (RBAC, ClusterRoles, Gatekeeper)
- [ ] Lesson 11 — write `README.md` (Prometheus + Grafana)
- [ ] Lesson 12 — write `README.md` (node failure simulation)
- [ ] Verify `laborant` sudo works correctly on all 5 VMs once playground boots
- [ ] Test RKE2 server start + worker join end-to-end in the live playground
- [ ] Confirm MetalLB L2 works on `172.16.0.100–120` subnet
