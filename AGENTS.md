PURPOSE: Product routing override for Windows Stat Toolkit.

HOT:
- `state/tasks/now.md`
- `state/memory-bank/activeContext.md`
- `active-version.txt`

WARM:
- `state/memory-bank/systemPatterns.md`
- `state/memory-bank/techContext.md`
- `state/tasks/decisions.md`
- `state/tasks/next.md`
- `ops/docs/repo-runbook.md`
- `ops/docs/known-issues.md`
- `ops/docs/product-scope.md`

RULES:
- Active codebase lives in `projects/windows-stat-toolkit/app/src/`.
- Product tools live in `projects/windows-stat-toolkit/ops/tools/`.
- Product process state lives in `projects/windows-stat-toolkit/state/`.
- Default mode is single-agent + skill-first package flow.
- Subagents are optional and only used for large, risky, parallelizable, security-sensitive, or incident-heavy work.
- Version bump, dossier, runnable rebuild, runtime snapshot, and GitHub publication remain mandatory for release-ready product packages.
