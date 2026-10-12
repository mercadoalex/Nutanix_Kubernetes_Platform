# rootfs/Makefile
# Build and push NKP lab OCI images to GHCR
#
# Usage:
#   make all          — build + push all three images
#   make bootstrap    — build + push nkp-bootstrap
#   make controlplane — build + push nkp-controlplane
#   make worker       — build + push nkp-worker
#   make build-all    — build only (no push)
#   make clean        — remove local images
#
# Prerequisites:
#   - Docker Desktop running (macOS is fine — buildx handles linux/amd64)
#   - Logged in to GHCR:
#       echo $GITHUB_TOKEN | docker login ghcr.io -u <your-github-user> --password-stdin

REGISTRY   ?= ghcr.io/mercadoalex
RELEASE    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
PLATFORM   := linux/amd64

BOOTSTRAP_IMAGE    := $(REGISTRY)/nkp-bootstrap
CONTROLPLANE_IMAGE := $(REGISTRY)/nkp-controlplane
WORKER_IMAGE       := $(REGISTRY)/nkp-worker

.PHONY: all bootstrap controlplane worker build-all clean login help

all: bootstrap controlplane worker

bootstrap:
	@echo "==> Building + pushing nkp-bootstrap (vm1)..."
	docker buildx build \
		--platform $(PLATFORM) \
		--provenance=false \
		--push \
		-t $(BOOTSTRAP_IMAGE):$(RELEASE) \
		-t $(BOOTSTRAP_IMAGE):latest \
		--progress=plain \
		-f bootstrap/Dockerfile \
		..
	@echo "✓ $(BOOTSTRAP_IMAGE):latest"

controlplane:
	@echo "==> Building + pushing nkp-controlplane (vm2)..."
	@echo "    (build context is rootfs/ root — downloads/rke2/ must exist)"
	docker buildx build \
		--platform $(PLATFORM) \
		--provenance=false \
		--push \
		-t $(CONTROLPLANE_IMAGE):$(RELEASE) \
		-t $(CONTROLPLANE_IMAGE):latest \
		--progress=plain \
		-f controlplane/Dockerfile \
		.
	@echo "✓ $(CONTROLPLANE_IMAGE):latest"

worker:
	@echo "==> Building + pushing nkp-worker (vm3–5)..."
	@echo "    (build context is rootfs/ root — downloads/rke2/ must exist)"
	docker buildx build \
		--platform $(PLATFORM) \
		--provenance=false \
		--push \
		-t $(WORKER_IMAGE):$(RELEASE) \
		-t $(WORKER_IMAGE):latest \
		--progress=plain \
		-f worker/Dockerfile \
		.
	@echo "✓ $(WORKER_IMAGE):latest"

build-all:
	@echo "==> Building all images (local only, no push)..."
	docker buildx build --platform $(PLATFORM) --load -t $(BOOTSTRAP_IMAGE):dev    bootstrap/
	docker buildx build --platform $(PLATFORM) --load -t $(CONTROLPLANE_IMAGE):dev -f controlplane/Dockerfile .
	docker buildx build --platform $(PLATFORM) --load -t $(WORKER_IMAGE):dev       -f worker/Dockerfile .

clean:
	docker rmi $(BOOTSTRAP_IMAGE):latest    $(BOOTSTRAP_IMAGE):dev    2>/dev/null || true
	docker rmi $(CONTROLPLANE_IMAGE):latest $(CONTROLPLANE_IMAGE):dev 2>/dev/null || true
	docker rmi $(WORKER_IMAGE):latest       $(WORKER_IMAGE):dev       2>/dev/null || true

login:
	@echo "Run: echo \$$GITHUB_TOKEN | docker login ghcr.io -u <your-github-user> --password-stdin"

help:
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
