# rootfs/Makefile
# Top-level build orchestration for all NKP lab rootfs images
#
# Usage:
#   make all          — build all three images (bootstrap, controlplane, worker)
#   make bootstrap    — build only nkp-bootstrap.ext4 (vm1)
#   make controlplane — build only nkp-controlplane.ext4 (vm2)
#   make worker       — build only nkp-worker.ext4 (vm3–5)
#   make clean        — remove dist/ directory
#
# Prerequisites:
#   - Docker running on the build host
#   - nkp binary placed at bootstrap/nkp (see bootstrap/Dockerfile comments)
#   - sudo available (needed for loop-mount during ext4 creation)

DIST_DIR := ../dist
SHELL    := /bin/bash

.PHONY: all bootstrap controlplane worker clean

all: bootstrap controlplane worker
	@echo ""
	@echo "All images built:"
	@ls -lh $(DIST_DIR)/*.ext4 2>/dev/null || echo "  (none found in $(DIST_DIR))"

bootstrap: $(DIST_DIR)/nkp-bootstrap.ext4

controlplane: $(DIST_DIR)/nkp-controlplane.ext4

worker: $(DIST_DIR)/nkp-worker.ext4

$(DIST_DIR)/nkp-bootstrap.ext4:
	@echo "==> Building bootstrap image (vm1)..."
	cd bootstrap && bash build.sh

$(DIST_DIR)/nkp-controlplane.ext4:
	@echo "==> Building controlplane image (vm2)..."
	cd controlplane && bash build.sh

$(DIST_DIR)/nkp-worker.ext4:
	@echo "==> Building worker image (vm3–5)..."
	cd worker && bash build.sh

clean:
	rm -rf $(DIST_DIR)
	@echo "dist/ removed."
