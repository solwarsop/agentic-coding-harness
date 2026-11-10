#!/usr/bin/env bash
set -euo pipefail
raw="$RUN_DIR/raw"
git init -q --bare "$raw/origin.git"
git remote add origin "$raw/origin.git"
git config push.negotiate false
git push -q -u origin main
