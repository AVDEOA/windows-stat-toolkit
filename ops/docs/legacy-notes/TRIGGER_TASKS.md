# TRIGGER_TASKS

This file records trigger-based tasks that should be followed for this workspace.

## Task 1

Name: `Auto-manage new projects in GitHub`

Trigger:

- A new project folder is created in the workspace.

Required actions:

1. Create the standard markdown set:
   - `README.md`
   - `FIXES_APPLIED.md`
   - `KNOWN_ISSUES.md`
   - `NEXT_STEPS.md`
   - `SESSION_LOG.md`
   - `TASK_CONTEXT.md`
   - `TASK_PROGRESS.md`
2. Initialize a git repository if needed.
3. Add or verify the GitHub remote.
4. Create the initial commit.
5. Push the project to GitHub.

## Task 2

Name: `Push project updates after code changes`

Trigger:

- A project receives meaningful source, UI, config, or documentation changes.

Required actions:

1. Review the current git status.
2. Stage the updated files.
3. Create a descriptive commit message.
4. Push the current branch to GitHub.

## Agent preference

- If a helper agent is available in the current session, it may be used for git automation support.
- If not, use the scripts in `C:\CodexTest\GitTools`.
