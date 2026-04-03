# REPORT v0.1.0

## Delivered
- Imported the legacy Windows Stat Toolkit scripts and historical notes into `NewCodex`.
- Added product docs, state files, validation wrappers, rebuild flow, and release scaffolding.
- Rebuilt the runnable source bundle and captured a versioned runtime snapshot for `v0.1.0`.

## Validation
- `ops\tools\test.cmd`
- `ops\tools\build.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh`

## Notes
- Validation was executed through the Windows wrapper path because the product targets Windows PowerShell.
- GitHub publication remains the last open release step.
