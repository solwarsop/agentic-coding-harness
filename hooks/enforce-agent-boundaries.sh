#!/usr/bin/env bash
# PreToolUse hook: turns the file-scope rules already stated in agents/*.md
# from prompt text into real denials, using the agent_type/agent_id fields
# Claude Code includes in the hook payload.
set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
agent_type=$(jq -r '.agent_type // empty' <<<"$input")
agent_id=$(jq -r '.agent_id // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
command=$(jq -r '.tool_input.command // empty' <<<"$input")

deny() {
  echo "$1" >&2
  exit 2
}

# Path relative to the active repo/worktree root, so plans/, docs/, etc.
# match regardless of whether we're at the main checkout or a worktree.
# path_in_repo tracks whether $file_path actually resolved under $cwd — a
# scratch file elsewhere (e.g. /tmp) isn't part of the project tree at all,
# so it's not "source" and none of the per-agent-type rules below should
# apply to it.
set_path_context() {
  local path="$1"
  rel_path="$path"
  path_in_repo=0
  if [[ -n "$path" && -n "$cwd" && "$path" == "$cwd"/* ]]; then
    rel_path="${path#"$cwd"/}"
    path_in_repo=1
  fi
}

set_path_context "$file_path"

# Path-shape helpers. These match a named directory at any depth and a
# basename anywhere in the tree, so a nested `pipelines/README.md` or
# `services/api/docs/` is classified the same way as the top-level one. They
# also still work when $file_path could not be made relative to $cwd (e.g. a
# worktree path read from the main checkout), since every pattern is anchored
# on a path segment rather than on the string start alone.
under_dir() {
  [[ "$rel_path" == "$1"/* || "$rel_path" == */"$1"/* ]]
}

basename_is() {
  [[ "${rel_path##*/}" == "$1" ]]
}

is_markdown() {
  [[ "$rel_path" == *.md ]]
}

# See path_in_repo above: only a file that's actually inside the repo/
# worktree can be "source", a doc, or a plan — a path outside it (e.g. a
# /tmp scratch file staged as input to a gh command) is exempt from every
# per-agent-type rule below.
is_within_repo() {
  [[ "$path_in_repo" == 1 ]]
}

# An agent's own persistent memory store, e.g.
# .claude/agent-memory/project-orchestrator/MEMORY.md — this is harness
# infrastructure, not source, so it's always writable by the agent it
# belongs to regardless of the per-agent-type rules below.
is_own_memory_path() {
  [[ -n "$rel_path" && -n "$agent_type" ]] || return 1
  under_dir ".claude/agent-memory/$agent_type"
}

# Documentation: docs/ at any depth, plus any README.md — technical-writer's
# territory, off-limits to senior-engineer.
is_doc_path() {
  [[ -n "$rel_path" ]] || return 1
  under_dir "docs" && return 0
  basename_is "README.md"
}

# Planning: plans/ at any depth, plus any CLAUDE.md — the orchestrator's
# territory.
is_plan_path() {
  [[ -n "$rel_path" ]] || return 1
  under_dir "plans" && return 0
  basename_is "CLAUDE.md"
}

# What project-orchestrator may read: any Markdown file (documentation and
# plans are Markdown wherever they live — the rule it enforces is "don't read
# source"), plus non-Markdown assets that sit under docs/ or plans/.
orchestrator_readable() {
  [[ -n "$rel_path" ]] || return 1
  is_markdown && return 0
  is_doc_path && return 0
  is_plan_path
}

# Bash command-line helpers for the per-agent Bash guards below. These are a
# heuristic backstop over the tools: lists in agents/*.md, not a sandbox —
# same posture as code-reviewer's existing Bash guard.

# The documented workflow depends on these running unguarded for every agent
# that has Bash in its tools list (git diff, gh issue create, ruff, etc.).
is_exempt_bash_command() {
  local cmd="${1#"${1%%[![:space:]]*}"}"
  case "$cmd" in
  "git "* | "gh "* | "jq "* | "ruff "* | "pyright "* | "pytest "*) return 0 ;;
  esac
  return 1
}

# Splits a command string on whitespace and keeps tokens that look like
# paths — containing a `/` or ending in a recognizable file extension —
# skipping flags. Anything from a heredoc marker (`<<`) onward is dropped
# first, so heredoc body text (e.g. a plan comment that merely mentions a
# path) is never mistaken for a command argument. Each surviving token is
# meant to be resolved (resolve_bash_token below) and passed to
# set_path_context.
extract_path_tokens() {
  local cmd="${1%%<<*}" tok
  for tok in $cmd; do
    [[ "$tok" == -* ]] && continue
    case "$tok" in
    */* | *.md | *.py | *.sh | *.json | *.yml | *.yaml | *.txt) printf '%s\n' "$tok" ;;
    esac
  done
}

# Command tokens are almost always relative (`README.md`, `src/foo.py`), not
# the absolute paths set_path_context expects — resolve a relative token
# against $cwd (the same root file_path is already resolved against) before
# classifying it. Absolute paths (in or out of the repo) pass through as-is.
resolve_bash_token() {
  local tok="${1#./}"
  if [[ "$tok" == /* || -z "$cwd" ]]; then
    printf '%s\n' "$tok"
  else
    printf '%s\n' "$cwd/$tok"
  fi
}

# Only a handful of verbs actually mutate a file; plain inspection
# (cat/grep/head/less/ls/...) must stay allowed even for a restricted path,
# since the dedicated Read tool already allows it for these agents. Matched
# as a substring against the raw command, same heuristic posture as
# code-reviewer's existing guard below.
is_mutating_bash_command() {
  local cmd="$1"
  case "$cmd" in
  *"sed -i"* | *"mv "* | *" mv "* | *"rm "* | *" rm "* | *"cp "* | *" cp "* | *"tee "* | *" tee "* | *"truncate"*) return 0 ;;
  esac
  # A bare '>'/'>>' redirect is mutating; a fd-qualified redirect (2>, &>,
  # 1>, 2>&1, ...) merely retargets a stream (often to /dev/null) and isn't
  # by itself evidence of writing a tracked path. Strip longer patterns
  # before their prefixes so a leftover '>' from '&>>'/'[0-9]>>' isn't
  # mistaken for a fresh mutating redirect.
  local stripped="$cmd"
  stripped="${stripped//&>>/}"
  stripped="${stripped//&>/}"
  stripped="${stripped//[0-9]>>/}"
  stripped="${stripped//[0-9]>/}"
  case "$stripped" in
  *">"*) return 0 ;;
  esac
  return 1
}

# Own-memory writes are always allowed, ahead of every other rule below. A
# bare `exit 0` only means "this hook doesn't object" — it still leaves the
# call subject to Claude Code's normal permission system (settings.json
# rules or an interactive prompt), which auto-denies in non-interactive
# sessions (e.g. this repo's own `@claude` GitHub Actions runs) when nothing
# pre-approves Write/Edit. Emitting an explicit `permissionDecision: allow`
# is what actually force-approves the call.
allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

case "$tool_name" in
Edit | Write | NotebookEdit)
  is_own_memory_path && allow "Own agent-memory path is always writable (hooks/enforce-agent-boundaries.sh)."
  ;;
esac

case "$agent_type" in
project-orchestrator)
  case "$tool_name" in
  Read)
    if is_within_repo && ! orchestrator_readable; then
      deny "project-orchestrator must not read source directly (agents/project-orchestrator.md) — it reads Markdown, docs/, and plans/ only. Dispatch junior-engineer and work from its summary."
    fi
    ;;
  Edit | Write | NotebookEdit)
    if is_within_repo && ! is_plan_path; then
      deny "project-orchestrator must not modify source directly — only plans/ and CLAUDE.md are writable here. Dispatch senior-engineer for code changes."
    fi
    ;;
  Bash)
    # tools: includes Bash for project-orchestrator, but the tools list
    # doesn't scope which paths it may read via a shell command — heuristic
    # backstop over agents/project-orchestrator.md, not a sandbox. Unlike
    # senior-engineer/technical-writer below, this stays path-shape-based
    # (not mutating-verb-gated) on purpose: project-orchestrator has no
    # standing allowance to read source at all (its Read tool denies it
    # outright), so a read-only `cat`/`grep` on source must be denied here
    # too, not just a write.
    if ! is_exempt_bash_command "$command"; then
      for tok in $(extract_path_tokens "$command"); do
        set_path_context "$(resolve_bash_token "$tok")"
        if is_within_repo && ! { is_markdown || is_doc_path || is_plan_path; }; then
          deny "project-orchestrator must not read source directly (agents/project-orchestrator.md) via Bash — it reads Markdown, docs/, and plans/ only. Dispatch junior-engineer and work from its summary."
        fi
      done
      set_path_context "$file_path"
    fi
    ;;
  esac
  ;;
senior-engineer)
  case "$tool_name" in
  Edit | Write)
    if is_within_repo && { is_doc_path || is_plan_path; }; then
      deny "senior-engineer must not touch README.md, docs/, or plans/ (at any depth) — that's project-orchestrator/technical-writer's job."
    fi
    ;;
  Bash)
    # tools: includes Bash for senior-engineer, but the tools list doesn't
    # scope which paths it may touch via a shell command — heuristic backstop
    # over agents/senior-engineer.md, not a sandbox. Gated on a mutating verb
    # (not path shape alone): senior-engineer is required to read CLAUDE.md/
    # docs via Bash, same as the Read tool already allows.
    if ! is_exempt_bash_command "$command" && is_mutating_bash_command "$command"; then
      for tok in $(extract_path_tokens "$command"); do
        set_path_context "$(resolve_bash_token "$tok")"
        if is_within_repo && { is_doc_path || is_plan_path; }; then
          deny "senior-engineer must not touch README.md, docs/, or plans/ (at any depth) via Bash — that's project-orchestrator/technical-writer's job."
        fi
      done
      set_path_context "$file_path"
    fi
    ;;
  esac
  ;;
junior-engineer)
  case "$tool_name" in
  Edit | Write | NotebookEdit)
    deny "junior-engineer is read-only (agents/junior-engineer.md) — it must not modify any file. Dispatch senior-engineer for code changes."
    ;;
  esac
  ;;
technical-writer)
  case "$tool_name" in
  Edit | Write)
    if is_within_repo && { is_plan_path || ! is_doc_path; }; then
      deny "technical-writer only touches documentation files (README.md at any depth, docs/) — not source, tests, or plans."
    fi
    ;;
  Bash)
    # tools: includes Bash for technical-writer, but the tools list doesn't
    # scope which paths it may touch via a shell command — heuristic backstop
    # over agents/technical-writer.md, not a sandbox. Gated on a mutating verb
    # (not path shape alone): technical-writer is required to read source via
    # Bash to write accurate docs, same as the Read tool already allows.
    if ! is_exempt_bash_command "$command" && is_mutating_bash_command "$command"; then
      for tok in $(extract_path_tokens "$command"); do
        set_path_context "$(resolve_bash_token "$tok")"
        if is_within_repo && { is_plan_path || ! is_doc_path; }; then
          deny "technical-writer only touches documentation files (README.md at any depth, docs/) via Bash — not source, tests, or plans."
        fi
      done
      set_path_context "$file_path"
    fi
    ;;
  esac
  ;;
code-reviewer)
  # code-reviewer's tools already exclude Edit/Write/NotebookEdit; Bash is its
  # one tool that isn't scoped by the tools list, so guard it here. Heuristic,
  # not exhaustive — see agents/code-reviewer.md ("you are read-only").
  if [[ "$tool_name" == "Bash" ]]; then
    case "$command" in
    *"git commit"* | *"git add"* | *"git push"* | "rm "* | *" rm "* | *"mv "* | *" mv "* | *"sed -i"* | *"ruff"*"--fix"*)
      deny "code-reviewer is read-only — it must not run mutating commands (agents/code-reviewer.md)."
      ;;
    esac
  fi
  ;;
*)
  # No recognized custom agent_type. If this is the root session (no
  # agent_id) and cwd is inside a worktree owned by a coordinating skill
  # (e.g. custom-agent-plan enters .claude/worktrees/<name> for the whole
  # task), source edits should go through project-orchestrator/
  # senior-engineer instead. A root session working in the normal repo
  # path (the documented small-task exception) is left untouched.
  if [[ -z "$agent_id" && "$cwd" == *"/.claude/worktrees/"* ]]; then
    case "$tool_name" in
    Edit | Write | NotebookEdit)
      if is_within_repo && ! is_doc_path && ! is_plan_path; then
        deny "This session is coordinating a worktree-based task (e.g. custom-agent-plan) — dispatch project-orchestrator/senior-engineer to edit source instead of editing directly from the root session. A scratch file outside the worktree (e.g. under /tmp, for staging a gh --body-file) is unaffected by this rule."
      fi
      ;;
    esac
  fi
  ;;
esac

exit 0
