# downloads/rke2/

Pre-downloaded RKE2 files used as Docker build context for `nkp-controlplane`
and `nkp-worker` images. Copying local files is dramatically faster than
downloading inside QEMU emulation on Apple Silicon.

## Files needed

```
downloads/rke2/
├── install.sh                              ← RKE2 installer script
├── rke2-images.linux-amd64.tar.zst         ← main image bundle   (~1.5 GB)
├── rke2-images-core.linux-amd64.tar.zst    ← core image bundle   (~500 MB)
└── rke2-images-cilium.linux-amd64.tar.zst  ← Cilium CNI bundle   (~300 MB)
```

## Download command

```bash
RKE2_VERSION="v1.34.3+rke2r1"
cd downloads/rke2

curl -fsSL "https://get.rke2.io" -o install.sh

curl -fsSL "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images.linux-amd64.tar.zst" \
  -o rke2-images.linux-amd64.tar.zst &

curl -fsSL "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-core.linux-amd64.tar.zst" \
  -o rke2-images-core.linux-amd64.tar.zst &

curl -fsSL "https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2-images-cilium.linux-amd64.tar.zst" \
  -o rke2-images-cilium.linux-amd64.tar.zst &

wait && echo "Done" && ls -lh
```

These files are excluded from git (`.gitignore`) — download them once before
running `make controlplane` or `make worker`.
