# Windows Stat Toolkit

Structured Windows diagnostics toolkit with a compiled desktop `exe`, local evidence collection, AI-friendly analysis prep, native-first remote SSH collection with password/key auth and PowerShell fallback, and concept monitoring with Telegram alerts.

## Product Layout

- `app/src/`: active toolkit scripts and analyzers
- `app/desktop/WindowsStatToolkit.Desktop/`: .NET 8 WPF desktop application source
- `artifacts/desktop-publish/WindowsStatToolkit.Desktop.exe`: published concept `exe`
- `artifacts/desktop-publish/`: portable folder that can be copied to another Windows PC for standalone launch
- `app/src/WindowsStatToolkit.App.ps1`: older PowerShell GUI prototype kept for reference
- `app/src/RemoteDiagnostics.App.ps1`: remote diagnostics MVP entrypoint
- desktop hosts can now run in `auto`, `ssh_native`, or `ssh_powershell` collection mode
- `app/tests/`: validation notes or future tests
- `ops/tools/`: validation, rebuild, and snapshot wrappers
- `ops/docs/`: runbooks, scope docs, and preserved legacy notes
- `state/memory-bank/`: current product context
- `state/tasks/`: active tasks, backlog, and decisions
- `versions/`: release dossiers and runtime snapshots
