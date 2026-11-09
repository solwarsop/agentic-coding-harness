#!/usr/bin/env bash
set -euo pipefail
git apply "$CASE_DIR/json-feature.patch"
git add -A
git commit -qm "feat: add --json flag"
