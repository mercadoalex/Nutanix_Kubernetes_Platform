# rootfs — NKP Lab Image Build

This directory contains the Dockerfiles and build scripts that produce the three
Firecracker rootfs images used by the iximious Flexbox playground.

## Images produced

| Image | VM | Size | Base OS |
|---|---|---|---|
| `nkp-bootstrap.ext4` | vm1 | ~8 GB | Ubuntu 24.04 |
| `nkp-controlplane.ext4` | vm2 | ~12 GB | Rocky Linux 9.7 |
| `nkp-worker.ext4` | vm3, vm4, vm5 | ~12 GB | Rocky Linux 9.7 |

Built images are written to `../dist/`.

---

## Prerequisites

- **Docker** running on the build host (Linux recommended; macOS works with Docker Desktop)
- **`sudo`** available — needed to loop-mount the ext4 image during export
- **`make`**, **`curl`**, **`dd`**, **`mkfs.ext4`** (standard on Linux; install `e2fsprogs` on macOS)
- **Internet access** during the build — container images are pulled at build time and baked in

### One additional prerequisite for `bootstrap/`

The `nkp` CLI binary must be downloaded manually from the Nutanix Support Portal
(requires a free Nutanix account) and placed at `bootstrap/nkp` before building.

```bash
# 1. Go to https://portal.nutanix.com/page/downloads?product=nkp
# 2. Download "NKP for Linux" (the tar.gz)
# 3. Extract the nkp binary:
tar xz -C rootfs/bootstrap/ --strip-components=0 -f ~/Downloads/nkp-v2.17.1-linux-amd64.tar.gz nkp
```

---

## Build all images

```bash
cd rootfs
make all
```

Or build individually:

```bash
make bootstrap      # vm1 only
make controlplane   # vm2 only
make worker         # vm3–5 (single image shared by all three workers)
```

---

## Directory structure

```
rootfs/
├── Makefile                  ← top-level build orchestration
├── README.md                 ← this file
├── bootstrap/
│   ├── Dockerfile            ← Ubuntu 24.04 + nkp, kubectl, helm, flux, Docker, kind
│   ├── build.sh              ← builds and exports nkp-bootstrap.ext4
│   ├── nkp                   ← PLACE NKP BINARY HERE (not committed to git)
│   └── labs/                 ← lesson YAML files copied into /home/laborant/labs/
├── controlplane/
│   ├── Dockerfile            ← Rocky 9.7 + RKE2 server + airgap images
│   ├── build.sh
│   ├── config-server.yaml    ← default /etc/rancher/rke2/config.yaml
│   └── labs/
└── worker/
    ├── Dockerfile            ← Rocky 9.7 + RKE2 agent + airgap images
    ├── build.sh
    ├── config-agent.yaml     ← default /etc/rancher/rke2/config.yaml
    └── labs/
```

---

## Pinned versions

All versions are defined as `ARG` in each Dockerfile. Update them together when bumping NKP:

| Component | Pinned version | Dockerfile ARG |
|---|---|---|
| RKE2 | `v1.34.3+rke2r1` | `RKE2_VERSION` |
| kubectl | `1.34.3` | `KUBECTL_VERSION` |
| nkp CLI | `2.17.1` | `NKP_VERSION` (bootstrap only) |
| helm | `3.17.3` | `HELM_VERSION` (bootstrap only) |
| flux CLI | `2.5.1` | `FLUX_VERSION` (bootstrap only) |
| kind | `0.27.0` | `KIND_VERSION` (bootstrap only) |

When NKP bumps to 2.18 (K8s 1.35.x), update all versions above and rebuild all three images.

---

## `.gitignore` note

The `nkp` binary is excluded from git — it must not be committed (Nutanix license terms).
Add this to your `.gitignore`:

```
rootfs/bootstrap/nkp
dist/
```
