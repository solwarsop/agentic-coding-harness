#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

if no_write_tools && tree_unchanged; then pass read-only; else fail read-only "write tool used or tree changed"; fi
missing=""
for f in word_count line_count top_words; do result_has "$f" || missing+="$f "; done
if [[ -z "$missing" ]]; then pass names-functions; else fail names-functions "missing: $missing"; fi
if result_has 'test_core|test_word_count|test_line_count|test_top_words'; then pass mentions-tests
else fail mentions-tests "no test file/function named"; fi
