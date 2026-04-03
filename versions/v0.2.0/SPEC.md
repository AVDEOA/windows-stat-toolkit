# SPEC v0.2.0

## Summary
- Add an SSH-based remote diagnostics MVP inside `windows-stat-toolkit`.
- Prepare AI-ready local bundles for manual ChatGPT/Codex upload without direct app-side submission.

## Scope
- remote host config and state flow
- SSH-based Windows diagnostics collection
- structured collection bundle, local summary, and analysis prompt generation
- validator and documentation updates for the new workflow

## Acceptance
- A user can initialize remote diagnostics state, add a host, run collection, and prepare an AI-ready bundle for 3, 7, 14, or 30 days.
- New scripts are covered by the toolkit validator.
- Docs explain the supported workflow and the current non-API AI limitation.
