# SPEC v0.5.0

## Goal
- Bring the diagnostics desktop app closer to the architectural quality bar of `S3Drive`.

## Requirements
- Separate UI, transport, orchestration, and report generation responsibilities.
- Keep compiled exe functionality intact.
- Preserve SSH + remote PowerShell collection while moving it behind an interface boundary.

## Non-goals
- No full replacement of remote PowerShell collection in this step.
- No Windows Service split in this step.
