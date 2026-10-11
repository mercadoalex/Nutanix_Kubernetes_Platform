# downloads/bootstrap/

Pre-downloaded binaries for the `nkp-bootstrap` rootfs image build.

**These files are git-ignored** (large binaries). Run `fetch.sh` to populate this directory before building.

## Usage

```bash
# Step 1 — download all binaries (once)
cd downloads/bootstrap
bash fetch.sh

# Step 2 — build and push the image
cd ../../rootfs
bash bootstrap/build.sh
```

## Contents after fetch.sh

| File | Version | Source |
|---|---|---|
| `kubectl` | 1.34.3 | dl.k8s.io |
| `kind` | 0.27.0 | kind.sigs.k8s.io |
| `nkp_v2.17.1_linux_amd64.tar.gz` | 2.17.1 | downloads.d2iq.com |
| `helm-v3.17.3-linux-amd64.tar.gz` | 3.17.3 | get.helm.sh |
| `flux_2.5.1_linux_amd64.tar.gz` | 2.5.1 | github.com/fluxcd/flux2 |
| `k9s_Linux_amd64.tar.gz` | 0.32.5 | github.com/derailed/k9s |

## Build flow

```mermaid
flowchart TD
    subgraph BEFORE["❌ Before — Online build (6 network fetches)"]
        direction TB
        B1["docker build"] --> B2["curl kubectl\n dl.k8s.io"]
        B2 --> B3["curl helm\n get.helm.sh"]
        B3 --> B4["curl flux\n github.com/fluxcd"]
        B4 --> B5["curl kind\n kind.sigs.k8s.io"]
        B5 --> B6["curl k9s\n github.com/derailed"]
        B6 --> B7["curl nkp\n downloads.d2iq.com"]
        B7 --> B8["✅ image built\n ~500 MB fetched\n fails if any CDN is down"]
    end

    subgraph AFTER["✅ After — Airgap build (fetch once, build offline)"]
        direction TB
        A1["bash fetch.sh\n run ONCE"] --> A2["downloads/bootstrap/\n kubectl · kind · nkp\n helm · flux · k9s"]
        A2 --> A3["docker build"]
        A3 --> A4["FROM scratch AS downloads\n COPY kubectl\n COPY kind\n COPY nkp.tar.gz\n COPY helm.tar.gz\n COPY flux.tar.gz\n COPY k9s.tar.gz"]
        A4 --> A5["apt-get Docker CE\n ⚠️ only online step"]
        A5 --> A6["COPY --from=downloads\n install all tools"]
        A6 --> A7["✅ image built\n reproducible · offline · fast"]
    end

    BEFORE ~~~ AFTER
```

