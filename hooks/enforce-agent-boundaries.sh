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
rel_path="$file_path"
if [[ -n "$file_path" && -n "$cwd" && "$file_path" == "$cwd"/* ]]; then
  rel_path="${file_path#"$cwd"/}"
fi

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

# Documentation: docs/ at any depth, plus any README.md — technical-writer's
# territory, off-limits to software-engineer.
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

case "$agent_type" in
project-orchestrator)
  case "$tool_name" in
  Read)
    orchestrator_readable || deny "project-orchestrator must not read source directly (agents/project-orchestrator.md) — it reads Markdown, docs/, and plans/ only. Dispatch software-engineer and work from its summary."
    ;;
  Edit | Write | NotebookEdit)
    is_plan_path || deny "project-orchestrator must not modify source directly — only plans/ and CLAUDE.md are writable here. Dispatch software-engineer for code changes."
    ;;
  esac
  ;;
software-engineer)
  case "$tool_name" in
  Edit | Write)
    if is_doc_path || is_plan_path; then
      deny "software-engineer must not touch README.md, docs/, or plans/ (at any depth) — that's project-orchestrator/technical-writer's job."
    fi
    ;;
  esac
  ;;
technical-writer)
  case "$tool_name" in
  Edit | Write)
    if is_plan_path || ! is_doc_path; then
      deny "technical-writer only touches documentation files (README.md at any depth, docs/) — not source, tests, or plans."
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
  # software-engineer instead. A root session working in the normal repo
  # path (the documented small-task exception) is left untouched.
  if [[ -z "$agent_id" && "$cwd" == *"/.claude/worktrees/"* ]]; then
    case "$tool_name" in
    Edit | Write | NotebookEdit)
      if ! is_doc_path && ! is_plan_path; then
        deny "This session is coordinating a worktree-based task (e.g. custom-agent-plan) — dispatch project-orchestrator/software-engineer to edit source instead of editing directly from the root session."
      fi
      ;;
    esac
  fi
  ;;
esac

exit 0
