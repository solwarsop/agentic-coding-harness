#!/usr/bin/env bash
# shellcheck source=../../lib.sh
source "$(dirname "$0")/../../lib.sh"

check cites-url "no http(s) URL in result" result_has 'https?://[^ )>]+'
check has-version "no semver-like string" result_has '[0-9]+\.[0-9]+\.[0-9]+'
if [[ -z "$(tool_uses_all Read)$(tool_uses_all Bash)$(tool_uses_all Edit)$(tool_uses_all Write)" ]]; then pass no-repo-access
else fail no-repo-access "Read/Bash/Edit/Write tool_use attempted"; fi
if [[ -s "$RESULT_TEXT" ]] && [[ "$(jq -rs '[.[] | select(.type=="result")] | last | .is_error' "$TRANSCRIPT")" == "false" ]]; then pass answered
else fail answered "empty result or is_error"; fi
