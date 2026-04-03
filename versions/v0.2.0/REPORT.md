# REPORT v0.2.0

## Delivered
- Added a remote diagnostics MVP with SSH host config, collection, local summary generation, and AI-ready prompt preparation.
- Updated toolkit validation to scan active PowerShell files dynamically.
- Updated docs, instructions, and state files for the new workflow.
- Rebuilt the runnable source bundle and captured a versioned runtime snapshot for `v0.2.0`.

## Validation
- `ops\tools\test.cmd`
- `ops\tools\build.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh 0.2.0`
- `RemoteDiagnostics.App.ps1 -Command Init`
- `RemoteDiagnostics.App.ps1 -Command AddHost`
- `RemoteDiagnostics.App.ps1 -Command ListHosts`

## Notes
- Direct ChatGPT/Codex submission from the app is intentionally not included in this release.
- Real `Collect` over SSH was not executed in validation because no reachable test host was provided in this session.
