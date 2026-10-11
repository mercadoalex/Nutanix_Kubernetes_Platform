#!/usr/bin/env bash
# scripts/publish.sh
# Publish the NKP course and playground to iximious Labs.
#
# Usage:
#   bash scripts/publish.sh
#
# Prerequisites:
#   - labctl installed and authenticated (labctl auth login)
#   - Run from the repo root (nkp_demo/)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SLUG="nkp-nutanix-kubernetes-platform-475898d2"
COURSE_DIR="course-1"
PLAYGROUND_FILE="playground/nkp-flexbox.yaml"

echo "── Push course content ──────────────────────────────────────────────────────"
labctl content push -f course "${SLUG}" -d "${COURSE_DIR}"
echo "✓ Course content pushed"

echo ""
echo "── Update playground ────────────────────────────────────────────────────────"
labctl playground update -f "${PLAYGROUND_FILE}" "${SLUG}"
echo "✓ Playground updated"

echo ""
echo "✓ Done — https://labs.iximiuz.com/courses/${SLUG}"
