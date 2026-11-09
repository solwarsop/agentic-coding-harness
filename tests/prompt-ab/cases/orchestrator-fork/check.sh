#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check decision-needed "no Decision Needed heading" result_has '^### (⚖️ )?Decision Needed'
check no-full-plan "Implementation Plan heading present" bash -c "! grep -qF '### Implementation Plan' '$RESULT_TEXT'"
if result_has_i 'lru|in-memory' && result_has_i 'disk|persistent'; then pass options-listed
else fail options-listed "in-memory/LRU and disk options not both mentioned"; fi
