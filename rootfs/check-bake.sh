#!/usr/bin/env bash
# rootfs/check-bake.sh
# Pre-flight check: simulate the iximious ext4 bake validation on a local image.
# Run this BEFORE pushing — catches issues that cause RootfsBaked: False failures.
#
# Usage:
#   cd rootfs && bash check-bake.sh nkp-controlplane
#   cd rootfs && bash check-bake.sh nkp-worker
#   cd rootfs && bash check-bake.sh nkp-bootstrap
#   cd rootfs && bash check-bake.sh all
#
# Exit code: 0 = clean, 1 = issues found

set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/mercadoalex}"
IMAGES=("nkp-bootstrap" "nkp-controlplane" "nkp-worker")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; FAILED=1; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }

check_image() {
    local image="$1"
    local ref="${REGISTRY}/${image}:latest"
    FAILED=0

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Checking: ${image}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ── 1. Dangling symlinks ──────────────────────────────────────────────────
    echo "  [1] Dangling symlinks..."
    dangling=$(docker run --rm --platform linux/amd64 "${ref}" \
        bash -c "find / -xdev -xtype l 2>/dev/null | wc -l" 2>/dev/null || echo "ERROR")
    if [[ "$dangling" == "ERROR" ]]; then
        fail "Could not run container (image may not exist locally)"
        return 1
    elif [[ "$dangling" -gt 0 ]]; then
        fail "${dangling} dangling symlinks found:"
        docker run --rm --platform linux/amd64 "${ref}" \
            bash -c "find / -xdev -xtype l 2>/dev/null" 2>/dev/null | head -20 | sed 's/^/      /'
        [[ "$dangling" -gt 20 ]] && echo "      ... (showing first 20 of ${dangling})"
    else
        pass "No dangling symlinks"
    fi

    # ── 2. Files with SELinux xattrs ─────────────────────────────────────────
    echo "  [2] SELinux xattrs on filesystem..."
    xattr_count=$(docker run --rm --platform linux/amd64 "${ref}" \
        bash -c "command -v getfattr >/dev/null 2>&1 && \
            getfattr -R -n security.selinux / 2>/dev/null | grep -c '^# file:'" \
        2>/dev/null || echo "0")
    xattr_count="${xattr_count//[^0-9]/}"
    xattr_count="${xattr_count:-0}"
    if [[ "$xattr_count" -gt 0 ]]; then
        fail "${xattr_count} files with security.selinux xattr"
    else
        pass "No security.selinux xattrs"
    fi

    # ── 3. Uncompressed image size ────────────────────────────────────────────
    echo "  [3] Uncompressed image size..."
    size_bytes=$(docker image inspect "${ref}" --format '{{.Size}}' 2>/dev/null || echo 0)
    size_mb=$(( size_bytes / 1024 / 1024 ))
    limit_mb=1400
    if [[ "$size_mb" -gt "$limit_mb" ]]; then
        fail "Image is ${size_mb} MB — exceeds iximious bake limit of ~${limit_mb} MB"
    else
        pass "Image is ${size_mb} MB (limit ~${limit_mb} MB)"
    fi

    # ── 4. CMD is set ─────────────────────────────────────────────────────────
    echo "  [4] CMD entrypoint..."
    cmd=$(docker image inspect "${ref}" --format '{{json .Config.Cmd}}' 2>/dev/null || echo "null")
    if [[ "$cmd" == "null" || "$cmd" == "[]" ]]; then
        fail "No CMD set — iximious needs CMD [\"/sbin/init\"] or similar"
    else
        pass "CMD is set: ${cmd}"
    fi

    # ── 5. laborant user exists at UID 1000 ───────────────────────────────────
    echo "  [5] laborant user (UID 1000)..."
    uid=$(docker run --rm --platform linux/amd64 "${ref}" \
        bash -c "id -u laborant 2>/dev/null || echo MISSING" 2>/dev/null || echo "MISSING")
    if [[ "$uid" == "1000" ]]; then
        pass "laborant user exists at UID 1000"
    else
        fail "laborant user missing or wrong UID (got: ${uid})"
    fi

    # ── Result ────────────────────────────────────────────────────────────────
    echo ""
    if [[ "$FAILED" -eq 0 ]]; then
        echo -e "  ${GREEN}● PASS${NC} — ${image} looks safe to push"
    else
        echo -e "  ${RED}● FAIL${NC} — ${image} has issues that will cause RootfsBaked: False"
    fi

    return "$FAILED"
}

# ── Main ──────────────────────────────────────────────────────────────────────
TARGET="${1:-all}"
OVERALL=0

if [[ "$TARGET" == "all" ]]; then
    for img in "${IMAGES[@]}"; do
        check_image "$img" || OVERALL=1
    done
else
    check_image "$TARGET" || OVERALL=1
fi

echo ""
if [[ "$OVERALL" -eq 0 ]]; then
    echo -e "${GREEN}All checks passed. Safe to push.${NC}"
else
    echo -e "${RED}One or more checks failed. Fix before pushing.${NC}"
fi
echo ""
exit "$OVERALL"
