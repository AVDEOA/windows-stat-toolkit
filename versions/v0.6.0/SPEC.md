# SPEC v0.6.0

## Goal
- Move the analysis desktop app from a PowerShell-isolated transport to a native-first remote diagnostics engine.

## Requirements
- Keep the compiled exe workflow intact.
- Add a native SSH collector path that gathers inventory and event evidence through standard Windows commands.
- Preserve PowerShell as fallback and explicit operator mode.
- Surface transport mode and collector outcome in the UX and generated reports.

## Non-goals
- No persistent Windows Service split in this step.
- No password-based SSH flow in this step.
- No full analyzer replacement for `AnalizeV9.ps1` in this step.
