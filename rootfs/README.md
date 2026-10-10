# rootfs — NKP Lab Image Build

This directory contains the Dockerfiles and build scripts that produce the three
Firecracker rootfs images used by the iximious Flexbox playground.

```
nkp-bootstrap.ext4    — vm1  (Ubuntu 24.04 + nkp CLI + Docker + kind + k9s)
nkp-controlplane.ext4 — vm2  (Rocky Linux 9.7 + RKE2 server + airgap images)
nkp-worker.ext4       — vm3–5 (Rocky Linux 9.7 + RKE2 agent  + airgap images)
```

---

## Recommended build method — GitHub Actions ✅

The CI workflow at [`.github/workflows/build-rootfs.yml`](../.github/workflows/build-rootfs.yml)
runs on a GitHub-hosted `ubuntu-latest` runner which already has Docker, `sudo`,
`mkfs.ext4`, and all required tools. It builds all three images in parallel,
compresses them with `zstd`, and attaches them to a GitHub Release.

**No secrets or portal accounts required.** The `nkp` binary is downloaded automatically
during CI from the D2iQ public CDN — NKP is the renamed D2iQ DKP product and the
standalone binary remains publicly accessible:

```
https://downloads.d2iq.com/dkp/v2.17.1/nkp_v2.17.1_linux_amd64.tar.gz
```

#### How this URL was discovered

NKP is a rebranding of **D2iQ DKP** (Nutanix acquired D2iQ in 2023 and renamed the
product). D2iQ historically published standalone CLI binaries on their own CDN at:

```
https://downloads.d2iq.com/dkp/v<VERSION>/dkp_v<VERSION>_linux_amd64.tar.gz
```

After the rebrand, Nutanix kept the same CDN path but changed the binary name from
`dkp` to `nkp`:

```
https://downloads.d2iq.com/dkp/v<VERSION>/nkp_v<VERSION>_linux_amd64.tar.gz
```

Versions up to **v2.15.2** ship the old `dkp`-named binary (still functional, just
named differently). From **v2.16.0** onward the binary is named `nkp`. Both v2.16.x
and v2.17.x are publicly accessible on this CDN with no authentication required.

> ⚠️ **v2.17.2+ and v2.18.x** currently return HTTP 403 on this CDN — Nutanix may
> be migrating newer releases to `portal.nutanix.com`. Always verify with a HEAD
> request before bumping the version:
> ```bash
> curl -sI "https://downloads.d2iq.com/dkp/v<VERSION>/nkp_v<VERSION>_linux_amd64.tar.gz" | head -1
> ```

### Step 1 — Trigger the build

**On push:** any push to `main` that changes a file under `rootfs/` triggers the
workflow automatically.

**Manually:** go to **Actions → Build rootfs images → Run workflow**. Optionally
enter a release tag (e.g. `v2.17.1`) to attach the built images to that Release.

### Step 2 — Download and decompress

Images are attached to the GitHub Release as `.zst` files.
Download and decompress before uploading to iximious:

```bash
# Download from the GitHub Release (example — adjust tag and filenames)
gh release download v2.17.1 --pattern "*.zst"

# Decompress
zstd -d nkp-bootstrap.ext4.zst
zstd -d nkp-controlplane.ext4.zst
zstd -d nkp-worker.ext4.zst
```

Then reference the `.ext4` files in your Flexbox playground YAML (`playground/nkp-flexbox.yaml`).

---

## Images produced

| Image | VM | Uncompressed | Compressed (~) | Base OS |
|---|---|---|---|---|
| `nkp-bootstrap.ext4` | vm1 | 8 GB | ~2 GB | Ubuntu 24.04 |
| `nkp-controlplane.ext4` | vm2 | 12 GB | ~4 GB | Rocky Linux 9.7 |
| `nkp-worker.ext4` | vm3, vm4, vm5 | 10 GB | ~3 GB | Rocky Linux 9.7 |

---

## Local build (Linux only)

> **macOS cannot run this build.** The scripts use `mkfs.ext4`, loop mounts
> (`sudo mount -o loop`), and `dd`. Use a Linux x86-64 host.

### Prerequisites

- **Docker**
- **`e2fsprogs`** (`sudo apt install e2fsprogs` / `sudo dnf install e2fsprogs`)
- **`sudo`** with loop device support
- **`make`**, **`curl`**, **`dd`**, **`zstd`** (optional, for compression)

### Quick setup on Ubuntu 24.04

```bash
sudo apt-get update
sudo apt-get install -y docker.io e2fsprogs make curl git zstd
sudo usermod -aG docker $USER && newgrp docker
```

### Get the nkp binary (optional — for manual/offline builds)

The Docker build downloads `nkp` automatically. If you need it locally (e.g. for
an airgapped build host), fetch it directly from the D2iQ CDN — no login required:

```bash
curl -fsSL \
  "https://downloads.d2iq.com/dkp/v2.17.1/nkp_v2.17.1_linux_amd64.tar.gz" \
  | tar xz -C rootfs/bootstrap/ nkp
chmod +x rootfs/bootstrap/nkp
```

### Build

```bash
cd rootfs
make all            # all three images → ../dist/
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
| k9s | `0.32.5` | `K9S_VERSION` (bootstrap only) |

When NKP bumps to 2.18 (K8s 1.35.x), update all versions above and rebuild all three images.

---

## `.gitignore` note

The `nkp` binary and compiled images are excluded from git:

```
rootfs/bootstrap/nkp
dist/
```
