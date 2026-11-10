#!/usr/bin/env bash
set -euo pipefail
git apply "$CASE_DIR/change.patch"
