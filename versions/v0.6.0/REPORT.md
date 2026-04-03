# REPORT v0.6.0

## Delivered
- Added `SshCommandRunner`, `SshNativeDiagnosticsTransport`, and `DiagnosticsTransportRouter`.
- Moved the desktop app to a native-first collection strategy while keeping PowerShell over SSH as fallback and explicit mode.
- Added host transport mode selection to the UI and surfaced collector metadata in saved reports.

## Validation
- `ops\tools\test.cmd`
- `ops\tools\build.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh 0.6.0`

## Notes
- `v0.5.0` remains preserved as the previous published backup line in `versions/v0.5.0/` and on GitHub.
