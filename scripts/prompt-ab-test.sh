#!/usr/bin/env bash
# Behavioural before/after regression test for the agent and skill prompts.
#
# Runs each case in tests/prompt-ab/cases/ against two prompt sets (variants) on the same
# fixture project, several times each, scores the sessions with fixed checks (each case's
# check.sh) and reports pass-rates per check. Results are resumable: a run with a score.json
# is never repeated, so rerunning the same command after a usage-limit pause tops up.
#
# Usage:
#   scripts/prompt-ab-test.sh list
#   scripts/prompt-ab-test.sh run [--before <ref>] [--after <ref>] [--runs N] [--cases a,b]
#                                 [--out DIR] [--dry-run]
#   scripts/prompt-ab-test.sh report [--before <ref>] [--after <ref>] [--cases a,b] [--out DIR]
#   scripts/prompt-ab-test.sh --help
#   (use `--before origin/main` when local main may lag or differ from the remote)
#
# Defaults: --before main, --after HEAD, --runs 3, --out tests/prompt-ab/results.
# Results are written to --out (default tests/prompt-ab/results/, gitignored; do not commit
# them). Rerunning with the same --out resumes; to resume in a later session point --out at a
# directory that persists.
# <ref> is a git ref, or the literal WORKTREE for the current working-tree files.
# A variant is the content of agents/, skills/, scripts/, hooks/ and settings.json at <ref>;
# its identity (hash) covers agents/*.md and skills/** only.
#
# Work is interleaved (run index outermost, then case, then before/after) so a pause leaves
# both variants with similar counts. Layout: <out>/<case>/<hash>/run-<k>/{score.json,meta.json,
# status,raw/}; <out>/variants/<hash>.json. Exit codes: 0 ok, 2 usage, 3 paused (usage/rate
# limit, or claude died without a result and not by timeout) - rerun later to resume. Timeouts
# and non-limit error results are scored (checks as reported, "error" set; report counts them).
# A run's score carries a case_hash (case files, fixture, lib.sh, gh-stub); a score with a
# different hash is moved aside to run-<k>/stale-<ts>/ and ignored by the report.
#
# Env: PROMPT_AB_TIMEOUT (seconds per session, default 1200), PROMPT_AB_KEEP=1 keeps the
# scratch directories. Sessions use `claude -p` with a per-case --allowedTools list, an empty
# GH_CONFIG_DIR, no GitHub tokens and the offline gh stub first on PATH; real model usage is billed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ab="$root/tests/prompt-ab"
variant_paths=(agents skills scripts hooks settings.json)

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { printf 'error: %s\n' "$*" >&2; exit 2; }

tmp=""
cleanup() { [[ -z "$tmp" || "${PROMPT_AB_KEEP:-}" == 1 ]] || rm -rf "$tmp"; }
trap cleanup EXIT

# --- cases ---------------------------------------------------------------------------------

all_cases() { find "$ab/cases" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort; }

select_cases() {
  local want="$1" c
  if [[ -z "$want" ]]; then all_cases; return; fi
  for c in ${want//,/ }; do
    [[ -f "$ab/cases/$c/case.conf" ]] || die "unknown case: $c"
    echo "$c"
  done
}

# case_hash <case>: 12 hex of sha256 over the case dir, the fixture, lib.sh and the gh stub.
declare -A case_hash_cache=()
case_hash() {
  local c="$1"
  if [[ -z "${case_hash_cache[$c]:-}" ]]; then
    case_hash_cache[$c]="$(
      cd "$ab"
      { find "cases/$c" fixture gh-stub -type f; echo lib.sh; } | LC_ALL=C sort | while IFS= read -r p; do
        printf '%s\0' "$p"
        cat "$p"
      done | sha256sum | cut -c1-12
    )"
  fi
  printf '%s' "${case_hash_cache[$c]}"
}

cmd_list() {
  local c
  for c in $(all_cases); do
    # shellcheck disable=SC1090
    (AGENT=""; source "$ab/cases/$c/case.conf"; printf '%-22s %s\n' "$c" "$AGENT")
  done
}

# --- variants ------------------------------------------------------------------------------

# materialise <ref> <dest>: write the variant files of <ref> into <dest>.
materialise() {
  local ref="$1" dest="$2" mode path
  mkdir -p "$dest"
  if [[ "$ref" == WORKTREE ]]; then
    while IFS= read -r path; do
      mkdir -p "$dest/$(dirname "$path")"
      cp -p "$root/$path" "$dest/$path"
    done < <(cd "$root" && git ls-files -co --exclude-standard -- "${variant_paths[@]}")
  else
    while IFS=$'\t' read -r mode path; do
      mkdir -p "$dest/$(dirname "$path")"
      git -C "$root" show "$ref:$path" >"$dest/$path"
      if [[ "$mode" == 100755 ]]; then chmod +x "$dest/$path"; fi
    done < <(git -C "$root" ls-tree -r "$ref" -- "${variant_paths[@]}" | awk '{m=$1; sub(/^[^\t]*\t/, ""); print m "\t" $0}')
  fi
}

# variant_hash <dir>: 12 hex of sha256 over sorted path\0content of agents/*.md and skills/**.
variant_hash() {
  (
    cd "$1"
    {
      find agents -maxdepth 1 -type f -name '*.md' 2>/dev/null
      find skills -type f 2>/dev/null
    } | LC_ALL=C sort | while IFS= read -r p; do
      printf '%s\0' "$p"
      cat "$p"
    done | sha256sum | cut -c1-12
  )
}

# ref_commit <ref>: commit sha for the ref (WORKTREE: HEAD sha plus a marker).
ref_commit() {
  if [[ "$1" == WORKTREE ]]; then echo "$(git -C "$root" rev-parse HEAD)+worktree"
  else git -C "$root" rev-parse --verify --quiet "$1^{commit}" || die "unknown ref: $1"; fi
}

# prepare_variant <label> <ref> <out>: materialise, hash, record. Sets v_dir v_hash v_commit.
prepare_variant() {
  local label="$1" ref="$2" out="$3" file hashed
  v_commit="$(ref_commit "$ref")"
  v_dir="$tmp/variant-$label"
  materialise "$ref" "$v_dir"
  v_hash="$(variant_hash "$v_dir")"
  mkdir -p "$out/variants"
  file="$out/variants/$v_hash.json"
  hashed="$(cd "$v_dir" && { find agents -maxdepth 1 -type f -name '*.md'; find skills -type f; } 2>/dev/null | LC_ALL=C sort | jq -R . | jq -s .)"
  [[ -f "$file" ]] || echo '{"hash":"","refs":[],"files":[]}' >"$file"
  jq --arg h "$v_hash" --arg r "$ref" --arg c "$v_commit" --arg l "$label" --argjson f "$hashed" \
    '.hash = $h | .files = $f
     | .refs = ((.refs + [{ref: $r, commit: $c, label: $l}]) | unique)' "$file" >"$file.new"
  mv "$file.new" "$file"
}

# --- single run ----------------------------------------------------------------------------

# Reasons that mean "stop and resume later" rather than "this run failed".
pause_re='usage limit|rate limit|rate_limit|overloaded|quota exceeded|\b429\b|status[ :]+429'

pause() {
  local rundir="$1" msg="$2" reason="$3"
  printf 'paused: %s\n' "$reason" >"$rundir/status"
  printf 'PAUSED: %s: %s - rerun the same command later to resume\n' "$msg" "$reason"
  exit 3
}

# run_one <case> <label> <hash> <variant-dir> <ref> <commit> <k> <out>
run_one() {
  local case="$1" label="$2" hash="$3" vdir="$4" ref="$5" commit="$6" k="$7" out="$8"
  local casedir="$ab/cases/$case" rundir="$out/$case/$hash/run-$k"
  local msg="$case $label run $k" scratch rc=0 started chash
  chash="$(case_hash "$case")"

  if [[ -f "$rundir/score.json" ]]; then
    if [[ "$(jq -r '.case_hash // ""' "$rundir/score.json")" == "$chash" ]]; then
      printf 'skip (done): %s\n' "$msg"
      return 0
    fi
    local stale="$rundir/stale-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$stale"
    find "$rundir" -mindepth 1 -maxdepth 1 ! -name 'stale-*' -exec mv {} "$stale"/ \;
    printf 'warning: %s: score from a different test definition moved to %s\n' "$msg" "$stale"
  fi
  mkdir -p "$rundir"
  find "$rundir" -mindepth 1 -maxdepth 1 ! -name 'stale-*' -exec rm -rf {} +
  mkdir -p "$rundir/raw"
  rundir="$(cd "$rundir" && pwd)"

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/prompt-ab.XXXXXX")"
  export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
  export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
  export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
  (
    cd "$scratch"
    cp -a "$ab/fixture/." .
    mv README.md.in README.md
    git init -q -b main
    git config user.name fixture
    git config user.email fixture@example.invalid
    git add -A
    git commit -qm "base"
    mkdir -p .claude
    cp -a "$vdir/." .claude/
    git add -A
    git commit -qm "add .claude"
    if [[ -f "$casedir/setup.sh" ]]; then
      CASE_DIR="$casedir" RUN_DIR="$rundir" bash "$casedir/setup.sh"
    fi
    git status --porcelain >"$rundir/raw/status-before.txt"
  ) >"$rundir/raw/setup.log" 2>&1 || {
    printf 'setup failed: %s\n' "$(tail -3 "$rundir/raw/setup.log" | tr '\n' ' ')" >"$rundir/status"
    printf 'ERROR: %s: setup failed (see %s/raw/setup.log)\n' "$msg" "$rundir"
    errors=$((errors + 1))
    return 0
  }

  local AGENT="" MODEL="" MAX_BUDGET_USD="" ALLOWED_TOOLS=()
  # shellcheck disable=SC1090,SC1091
  source "$casedir/case.conf"
  local args=(-p --strict-mcp-config --no-session-persistence --output-format stream-json --verbose)
  [[ "$AGENT" == skill ]] || args+=(--agent "$AGENT")
  [[ -z "$MODEL" ]] || args+=(--model "$MODEL")
  [[ -z "$MAX_BUDGET_USD" ]] || args+=(--max-budget-usd "$MAX_BUDGET_USD")
  # --allowedTools is variadic, so it goes last and the prompt arrives on stdin.
  args+=(--allowedTools "${ALLOWED_TOOLS[@]}")

  printf 'running: %s\n' "$msg"
  started=$(date +%s)
  local ghcfg
  ghcfg="$(mktemp -d "$tmp/ghcfg.XXXXXX")"
  (
    cd "$scratch"
    env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
      GH_CONFIG_DIR="$ghcfg" RUN_DIR="$rundir" PATH="$ab/gh-stub:$PATH" \
      timeout "${PROMPT_AB_TIMEOUT:-1200}" claude "${args[@]}" <"$casedir/prompt.md"
  ) >"$rundir/raw/transcript.jsonl" 2>"$rundir/raw/stderr.txt" || rc=$?

  # Pause only for usage/rate-limit wording, or a dead claude (no result, not a timeout).
  # Timeouts and non-limit error results are scored with an "error" marker.
  local result is_error subtype="" err="" cost turns limit=0
  result="$(jq -cR 'fromjson? | select(.type == "result")' "$rundir/raw/transcript.jsonl" | tail -1)"
  if {
    cat "$rundir/raw/stderr.txt"
    [[ -z "$result" ]] || jq -r '.result // ""' <<<"$result"
  } | grep -Eiq "$pause_re"; then limit=1; fi
  if [[ -z "$result" ]]; then
    if ((limit)); then
      cleanup_scratch "$scratch"
      pause "$rundir" "$msg" "no result event (claude exit $rc); usage/rate limit wording"
    elif [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
      err=timeout
    else
      cleanup_scratch "$scratch"
      pause "$rundir" "$msg" "no result event (claude exit $rc)"
    fi
    result='{}'
  else
    is_error="$(jq -r '.is_error' <<<"$result")"
    subtype="$(jq -r '.subtype // ""' <<<"$result")"
    cost="$(jq -r '.total_cost_usd // 0' <<<"$result")"
    turns="$(jq -r '.num_turns // 0' <<<"$result")"
    if [[ "$is_error" == true && "$subtype" != error_max_* ]]; then
      if ((limit)); then
        cleanup_scratch "$scratch"
        pause "$rundir" "$msg" "result is_error ($subtype); usage/rate limit wording"
      fi
      err="${subtype:-error}"
    elif [[ "$is_error" != true ]] && ((limit)) &&
      { awk -v c="$cost" 'BEGIN{exit !(c+0 == 0)}' || ((turns <= 1)); }; then
      cleanup_scratch "$scratch"
      pause "$rundir" "$msg" "empty result with usage/rate limit wording"
    fi
  fi

  jq -r '.result // ""' <<<"$result" >"$rundir/raw/result.txt"
  local checks
  if ! checks="$(cd "$scratch" && TRANSCRIPT="$rundir/raw/transcript.jsonl" RESULT_TEXT="$rundir/raw/result.txt" \
    RUN_DIR="$rundir" CASE_DIR="$casedir" bash "$casedir/check.sh" 2>"$rundir/raw/check.stderr")"; then
    if [[ -z "$err" ]]; then
      printf 'checker failed (exit non-zero)\n' >"$rundir/status"
      printf 'ERROR: %s: check.sh failed (see %s/raw/check.stderr)\n' "$msg" "$rundir"
      errors=$((errors + 1))
      cleanup_scratch "$scratch"
      return 0
    fi
    # Errored session and the checker could not run: every check it defines counts as failed.
    checks="$(grep -ohE '\b(pass|fail|check) [a-z][a-z0-9-]+' "$casedir/check.sh" | awk '{print $2}' | LC_ALL=C sort -u |
      sed 's/$/ checker could not run/; s/^/FAIL /')"
  fi

  jq -Rn --arg case "$case" --arg hash "$hash" --argjson run "$k" --argjson res "$result" \
    --arg now "$(date -u +%FT%TZ)" --arg stop "$subtype" --arg err "$err" --arg chash "$chash" '
    [inputs | capture("^(?<s>PASS|FAIL) (?<id>[^ ]+) ?(?<d>.*)$")?] as $rows
    | {case: $case, variant_hash: $hash, case_hash: $chash, run: $run,
       error: (if $err == "" then null else $err end),
       checks: ($rows | map({(.id): (.s == "PASS")}) | add // {}),
       details: ($rows | map(select(.s == "FAIL" and .d != "") | {(.id): .d}) | add // {}),
       cost_usd: ($res.total_cost_usd // 0),
       models: (($res.modelUsage // {}) | keys),
       denials: (($res.permission_denials // []) | length),
       duration_ms: ($res.duration_ms // 0),
       stop: $stop,
       finished_at: $now}' <<<"$checks" >"$rundir/score.json"
  jq -n --arg ref "$ref" --arg commit "$commit" --arg label "$label" --arg chash "$chash" \
    '{ref: $ref, commit: $commit, label: $label, case_hash: $chash}' >"$rundir/meta.json"
  rm -f "$rundir/status"
  printf 'done: %s (%s passed, cost $%s, %ss%s)\n' "$msg" \
    "$(jq -r '.checks as $c | "\([$c[] | select(.)] | length)/\($c | length)"' "$rundir/score.json")" \
    "$(jq -r '.cost_usd' "$rundir/score.json")" "$(($(date +%s) - started))" "${err:+, error: $err}"
  cleanup_scratch "$scratch"
}

cleanup_scratch() { [[ "${PROMPT_AB_KEEP:-}" == 1 ]] || rm -rf "$1"; }

# --- commands ------------------------------------------------------------------------------

parse_opts() {
  before=main after=HEAD runs=3 out="$ab/results" cases="" dry=0
  while (($#)); do
    case "$1" in
      --before) before="${2:?--before needs a ref}"; shift 2 ;;
      --after) after="${2:?--after needs a ref}"; shift 2 ;;
      --runs) runs="${2:?--runs needs a number}"; shift 2 ;;
      --cases) cases="${2:?--cases needs a list}"; shift 2 ;;
      --out) out="${2:?--out needs a directory}"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive integer"
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  warn_main_drift
}

# warn_main_drift: --before main silently uses a stale local main when it differs from origin/main.
warn_main_drift() {
  local l r
  [[ "$before" == main ]] || return 0
  l="$(git -C "$root" rev-parse --verify --quiet refs/heads/main || true)"
  r="$(git -C "$root" rev-parse --verify --quiet refs/remotes/origin/main || true)"
  if [[ -n "$l" && -n "$r" && "$l" != "$r" ]]; then
    printf 'warning: local main (%s) differs from origin/main (%s); consider --before origin/main\n' "${l:0:12}" "${r:0:12}" >&2
  fi
}

cmd_run() {
  parse_opts "$@"
  command -v jq >/dev/null || die "jq is required"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/prompt-ab-variants.XXXXXX")"
  errors=0
  local -a case_list labels=(before after) refs=("$before" "$after") hashes=() dirs=() commits=()
  local list
  list="$(select_cases "$cases")"
  mapfile -t case_list <<<"$list"

  local i k c
  for i in 0 1; do
    prepare_variant "${labels[i]}" "${refs[i]}" "$out"
    hashes+=("$v_hash"); dirs+=("$v_dir"); commits+=("$v_commit")
    printf 'variant %s: %s (%s) hash %s\n' "${labels[i]}" "${refs[i]}" "${v_commit:0:12}" "$v_hash"
  done
  [[ "${hashes[0]}" != "${hashes[1]}" ]] || printf 'warning: before and after prompts are identical (same hash); runs are shared\n'

  for ((k = 1; k <= runs; k++)); do
    for c in "${case_list[@]}"; do
      for i in 0 1; do
        if ((i == 1)) && [[ "${hashes[0]}" == "${hashes[1]}" ]]; then continue; fi
        if ((dry)); then
          if [[ "$(jq -r '.case_hash // ""' "$out/$c/${hashes[i]}/run-$k/score.json" 2>/dev/null)" == "$(case_hash "$c")" ]]; then
            printf 'done: %s %s run %s\n' "$c" "${labels[i]}" "$k"
          else printf 'todo: %s %s run %s\n' "$c" "${labels[i]}" "$k"; fi
        else
          run_one "$c" "${labels[i]}" "${hashes[i]}" "${dirs[i]}" "${refs[i]}" "${commits[i]}" "$k" "$out"
        fi
      done
    done
  done
  if ((dry)); then return 0; fi
  ((errors == 0)) || printf 'warning: %s run(s) errored and were not scored\n' "$errors"
  echo
  report_for "${hashes[0]}" "${hashes[1]}" "$before" "$after" "$out" "$cases"
}

# current_scores <out> <case> <hash>: print paths of run score files whose case_hash is current.
current_scores() {
  local f ch
  ch="$(case_hash "$2")"
  for f in "$1/$2/$3"/run-*/score.json; do
    [[ -f "$f" ]] || continue
    [[ "$(jq -r '.case_hash // ""' "$f")" == "$ch" ]] && printf '%s\n' "$f"
  done
  return 0
}

# stale_count <out> <case> <hash>: number of score files with a different case_hash.
stale_count() {
  local f n=0 ch
  ch="$(case_hash "$2")"
  for f in "$1/$2/$3"/run-*/score.json; do
    [[ -f "$f" ]] || continue
    [[ "$(jq -r '.case_hash // ""' "$f")" == "$ch" ]] || n=$((n + 1))
  done
  echo "$n"
}

# pass_counts <out> <case> <hash>: lines "<check>\t<pass>\t<total>" (current-definition runs).
pass_counts() {
  local files
  mapfile -t files < <(current_scores "$@")
  ((${#files[@]})) || return 0
  jq -rs '[.[] | .checks | to_entries[]] | group_by(.key)[]
    | "\(.[0].key)\t\(map(select(.value)) | length)\t\(length)"' "${files[@]}"
}

# run_stats <out> <case> <hash>: "<runs> <cost> <errors>".
run_stats() {
  local files
  mapfile -t files < <(current_scores "$@")
  ((${#files[@]})) || { echo "0 0 0"; return 0; }
  jq -rs '"\(length) \(map(.cost_usd) | add) \(map(select(.error != null)) | length)"' "${files[@]}"
}

report_for() {
  local bh="$1" ah="$2" bref="$3" aref="$4" out="$5" cases="$6"
  local c line="" stale="" errl="" id bp bt ap at flag rb ra tb=0 ta=0 cb=0 ca=0 nb na eb ea sb sa
  local -a case_list
  local list
  list="$(select_cases "$cases")"
  mapfile -t case_list <<<"$list"

  printf '## Prompt A/B report\n\n- Before: `%s` (variant %s)\n- After: `%s` (variant %s)\n\n' "$bref" "$bh" "$aref" "$ah"
  printf '| Case | Check | Before (pass/runs) | After (pass/runs) | Flag |\n|---|---|---|---|---|\n'
  for c in "${case_list[@]}"; do
    declare -A bmap=() amap=()
    local ids=()
    while IFS=$'\t' read -r id bp bt; do [[ -n "$id" ]] && { bmap[$id]="$bp $bt"; ids+=("$id"); }; done < <(pass_counts "$out" "$c" "$bh")
    while IFS=$'\t' read -r id ap at; do [[ -n "$id" ]] && { amap[$id]="$ap $at"; ids+=("$id"); }; done < <(pass_counts "$out" "$c" "$ah")
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      read -r bp bt <<<"${bmap[$id]:-0 0}"
      read -r ap at <<<"${amap[$id]:-0 0}"
      flag=""
      if ((bt > 0 && at > 0)); then
        if ((bp * 3 >= 2 * bt && (at - ap) * 3 >= 2 * at)); then flag=REGRESSION
        elif (((bt - bp) * 3 >= 2 * bt && ap * 3 >= 2 * at)); then flag=IMPROVEMENT; fi
      fi
      printf '| %s | %s | %s/%s | %s/%s | %s |\n' "$c" "$id" "$bp" "$bt" "$ap" "$at" "$flag"
    done < <(printf '%s\n' "${ids[@]:-}" | LC_ALL=C sort -u)
    unset bmap amap
    read -r nb rb eb <<<"$(run_stats "$out" "$c" "$bh")"
    read -r na ra ea <<<"$(run_stats "$out" "$c" "$ah")"
    sb="$(stale_count "$out" "$c" "$bh")"
    sa="$(stale_count "$out" "$c" "$ah")"
    if ((sb + sa > 0)); then stale+="- $c: ignored stale run(s) (different test definition): before $sb, after $sa"$'\n'; fi
    if ((eb + ea > 0)); then errl+="- $c: before $eb, after $ea"$'\n'; fi
    tb=$((tb + nb)); ta=$((ta + na))
    cb="$(awk -v a="$cb" -v b="$rb" 'BEGIN{printf "%.4f", a+b}')"
    ca="$(awk -v a="$ca" -v b="$ra" 'BEGIN{printf "%.4f", a+b}')"
    if ((nb != na)); then line+="- $c: before $nb run(s), after $na run(s)"$'\n'; fi
  done
  printf '\n**Totals**: before %s run(s), $%s; after %s run(s), $%s\n' "$tb" "$cb" "$ta" "$ca"
  if [[ -n "${errl:-}" ]]; then printf '\nErrors (timeout/error result, scored with checks as reported):\n%s' "$errl"; fi
  if [[ -n "${stale:-}" ]]; then printf '\nwarning: stale runs ignored:\n%s' "$stale"; fi
  if [[ -n "${line:-}" ]]; then printf '\nIncomplete (run counts differ):\n%s' "$line"; fi
  return 0
}

cmd_report() {
  parse_opts "$@"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/prompt-ab-variants.XXXXXX")"
  prepare_variant before "$before" "$out"; local bh="$v_hash"
  prepare_variant after "$after" "$out"; local ah="$v_hash"
  report_for "$bh" "$ah" "$before" "$after" "$out" "$cases"
}

case "${1:-}" in
  list) cmd_list ;;
  run) shift; cmd_run "$@" ;;
  report) shift; cmd_report "$@" ;;
  -h | --help | help | "") usage; [[ -n "${1:-}" ]] || exit 2 ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
