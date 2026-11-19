# Running the harness under the Claude GitHub Action

The `custom-agent-plan` skill has a CI mode (see "CI mode" in `skills/custom-agent-plan/SKILL.md`). Each `@claude` mention is one ephemeral job; state lives in the PR thread, so the skill re-derives its phase on every run.

## Starting sessions

- Open an issue containing `@claude` and the task (the `issues: opened` trigger).
- Comment `@claude ...` on an issue or PR.
- Run the workflow manually (`workflow_dispatch`) with a prompt; no issue is needed.

Every approval or decision gate ends the job; reply with an `@claude` comment **on the PR** to continue.

## Workflow changes (apply manually; Claude cannot edit `.github/workflows`)

```yaml
on:
  workflow_dispatch:
    inputs:
      prompt:
        description: Task for Claude
        required: true
  # ...existing triggers...

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
  actions: read

# in the claude-code-action step:
        with:
          prompt: ${{ github.event.inputs.prompt }}   # only set for workflow_dispatch
          settings: ./settings.json                   # permissions + hooks for the skill
          claude_args: |
            --append-system-prompt "Use the 'custom-agent-plan' skill (skills/custom-agent-plan/SKILL.md) for requests that change code. Answer questions and reviews directly."
            --allowedTools "Bash(gh pr *),Bash(gh issue *),Bash(gh label create*),Bash(.claude/scripts/*),Bash(git *)"
```

This repo checks the harness out at the root with `.claude -> .`, so `.claude/scripts/...` resolves. In a consuming repo, check the harness out as the `.claude` directory (submodule with `submodules: true`).
