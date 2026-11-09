#!/usr/bin/env bash
set -euo pipefail
git init -q --bare "$RUN_DIR/origin.git"
git remote add origin "$RUN_DIR/origin.git"
git config push.negotiate false
git push -q -u origin main
stub="$(cd "$CASE_DIR/../../gh-stub" && pwd)"
cat >"$RUN_DIR/env.sh" <<ENV
export RUN_DIR="$RUN_DIR"
export PATH="$stub:\$PATH"
ENV
