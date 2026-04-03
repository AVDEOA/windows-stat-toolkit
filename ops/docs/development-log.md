# Development Log

## 2026-04-03

### v0.1.0

- Legacy diagnostics toolkit imported from `C:\CodexTest`.
- Product structure normalized into `app/`, `ops/`, `state/`, and `versions/`.
- Validation wrappers, runbooks, and first release dossier added.

### v0.2.0

- Remote diagnostics MVP introduced as a script-first workflow.
- Added SSH host inventory, remote collection bundle generation, and AI prompt packaging.

### v0.3.0

- Direction changed from script-first to GUI-first after user clarification.
- Added a PowerShell WPF desktop app for local diagnostics, host management, and bundle browsing.

### v0.4.0

- Product moved to a compiled `.NET 8 WPF` desktop `exe`.
- Added host CRUD, capped AI bundles, PC summary reports, named block reports, and Telegram monitoring.
- Host editor moved into a dedicated modal window.
- Telegram settings received explicit field labels and operator guidance.

### v0.5.0

- Product architecture moved closer to the layered style used by `S3Drive`.
- Added transport abstraction, diagnostics orchestrator, reusable block catalog, and generated report models.
- Main window stopped acting as the central logic container and now delegates work to focused services.
- Monitoring now runs through the orchestration layer instead of talking directly to the old collection service.

### v0.6.0

- Added a native-first SSH collector pipeline that gathers inventory and event evidence through standard Windows commands and parses them in C#.
- Added a transport router so `auto` mode can prefer native collection and only fall back to PowerShell when native collection fails.
- Added host-level transport mode selection to the desktop UI.
- Added collector metadata to reports so saved output now records whether native or fallback collection produced the evidence.

## Continuation Notes

- The compiled desktop app is now the canonical operator experience.
- `AnalizeV9.ps1` still matters as the content baseline for analysis coverage and block naming.
- The next major architectural step is replacing or minimizing the current remote PowerShell collector with a more native C# diagnostics pipeline.
- The next major product step is persistent monitoring outside the lifetime of the open desktop window.
