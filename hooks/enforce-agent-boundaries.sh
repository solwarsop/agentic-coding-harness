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

is_under() { [[ "$1" == "$2"/* ]]; }

in_plans_docs_claude_readme() {
  [[ -n "$rel_path" ]] || return 1
  is_under "$rel_path" "plans" && return 0
  is_under "$rel_path" "docs" && return 0
  [[ "$rel_path" == "CLAUDE.md" || "$rel_path" == "README.md" ]]
}

in_plans_or_claude() {
  [[ -n "$rel_path" ]] || return 1
  is_under "$rel_path" "plans" && return 0
  [[ "$rel_path" == "CLAUDE.md" ]]
}

in_docs_or_readme() {
  [[ -n "$rel_path" ]] || return 1
  is_under "$rel_path" "docs" && return 0
  [[ "$rel_path" == "README.md" ]]
}

in_readme_docs_or_plans() {
  [[ -n "$rel_path" ]] || return 1
  is_under "$rel_path" "plans" && return 0
  is_under "$rel_path" "docs" && return 0
  [[ "$rel_path" == "README.md" ]]
}

case "$agent_type" in
project-orchestrator)
  case "$tool_name" in
  Read)
    in_plans_docs_claude_readme || deny "project-orchestrator must not read source directly (agents/project-orchestrator.md) — dispatch software-engineer and work from its summary."
    ;;
  Edit | Write | NotebookEdit)
    in_plans_or_claude || deny "project-orchestrator must not modify source directly — only plans/ and CLAUDE.md are writable here. Dispatch software-engineer for code changes."
    ;;
  esac
  ;;
software-engineer)
  case "$tool_name" in
  Edit | Write)
    in_readme_docs_or_plans && deny "software-engineer must not touch README.md, docs/, or plans/ — that's project-orchestrator/technical-writer's job."
    ;;
  esac
  ;;
technical-writer)
  case "$tool_name" in
  Edit | Write)
    in_docs_or_readme || deny "technical-writer only touches documentation files (README.md, docs/) — not source, tests, or plans."
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
      in_plans_docs_claude_readme || deny "This session is coordinating a worktree-based task (e.g. custom-agent-plan) — dispatch project-orchestrator/software-engineer to edit source instead of editing directly from the root session."
      ;;
    esac
  fi
  ;;
esac

exit 0
