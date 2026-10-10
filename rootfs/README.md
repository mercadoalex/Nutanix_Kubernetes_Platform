# rootfs — NKP Lab Image Build

Dockerfiles and build scripts for the three NKP lab OCI images, served as
Firecracker VM rootfs images via iximious Flexbox.

| Image | VM | Base OS | GHCR |
|---|---|---|---|
| `nkp-bootstrap` | vm1 | Ubuntu 24.04 | `ghcr.io/mercadoalex/nkp-bootstrap:latest` |
| `nkp-controlplane` | vm2 | Rocky Linux 9.7 | `ghcr.io/mercadoalex/nkp-controlplane:latest` |
| `nkp-worker` | vm3–5 | Rocky Linux 9.7 | `ghcr.io/mercadoalex/nkp-worker:latest` |

---

## Build locally on macOS ✅

Docker Desktop on macOS handles the cross-compile to `linux/amd64` via `buildx`.
No Linux host, no CI runner, no loop mounts required.

### Prerequisites

- **Docker Desktop** running
- **Logged in to GHCR:**

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u mercadoalex --password-stdin
```

### Build and push all three images

```bash
cd rootfs
make all
```

Or individually:

```bash
make bootstrap      # vm1 — Ubuntu 24.04 + nkp + kubectl + helm + flux + kind + k9s
make controlplane   # vm2 — Rocky 9.7 + RKE2 server + airgap images
make worker         # vm3–5 — Rocky 9.7 + RKE2 agent + airgap images
```

Build only (no push, for local testing):

```bash
make build-all
```

---

## nkp binary

The `nkp` CLI is downloaded **automatically** during `docker buildx build` — no
pre-placement and no portal account required.

It is fetched from the public D2iQ CDN:

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

Versions up to **v2.15.2** ship the old `dkp`-named binary. From **v2.16.0** onward
the binary is named `nkp`. Both v2.16.x and v2.17.x are publicly accessible with no
authentication required.

> ⚠️ **v2.17.2+ and v2.18.x** currently return HTTP 403 — Nutanix may be migrating
> newer releases to `portal.nutanix.com`. Always verify before bumping the version:
> ```bash
> curl -sI "https://downloads.d2iq.com/dkp/v<VERSION>/nkp_v<VERSION>_linux_amd64.tar.gz" | head -1
> ```

---

## CI build (GitHub Actions)

The workflow at [`.github/workflows/build-rootfs.yml`](../.github/workflows/build-rootfs.yml)
does the same `docker buildx build --push` on every push to `main` that touches `rootfs/`.
Uses `secrets.GITHUB_TOKEN` to push to GHCR — no extra secrets needed.

---

## Directory structure

```
rootfs/
├── Makefile                  ← build + push orchestration (macOS-native)
├── README.md                 ← this file
├── bootstrap/
│   ├── Dockerfile            ← Ubuntu 24.04 + nkp, kubectl, helm, flux, Docker, kind, k9s
│   ├── build.sh              ← convenience wrapper (prefer: make bootstrap)
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

| Component | Version | Dockerfile ARG |
|---|---|---|
| RKE2 | `v1.34.3+rke2r1` | `RKE2_VERSION` |
| kubectl | `1.34.3` | `KUBECTL_VERSION` |
| nkp CLI | `2.17.1` | `NKP_VERSION` (bootstrap) |
| helm | `3.17.3` | `HELM_VERSION` (bootstrap) |
| flux CLI | `2.5.1` | `FLUX_VERSION` (bootstrap) |
| kind | `0.27.0` | `KIND_VERSION` (bootstrap) |
| k9s | `0.32.5` | `K9S_VERSION` (bootstrap) |

When NKP bumps to 2.18 (K8s 1.35.x), update all versions above and run `make all`.
