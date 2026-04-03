# REPORT v0.6.1

## Delivered
- Replaced the old process-based SSH command path with an SSH.NET-backed command runner.
- Added password auth, saved fingerprint handling, and explicit SSH test flows in the desktop UI.
- Added a visible portable publish folder path so operators know what to copy to another PC.

## Validation
- `ops\tools\test.cmd`
- `ops\tools\build.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh 0.6.1`

## Notes
- `v0.6.0` remains preserved as the previous published backup line in `versions/v0.6.0/` and on GitHub.
