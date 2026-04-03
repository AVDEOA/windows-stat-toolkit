# Release Notes v0.6.0

## Added
- Native-first SSH collection through `hostname`, `wmic`, `wevtutil`, and C# parsing/classification.
- Transport routing with `auto`, `ssh_native`, and `ssh_powershell` host modes.
- Collector metadata in generated snapshots and reports.

## Changed
- PowerShell over SSH is no longer the only diagnostics engine path.
- Desktop host editing now exposes transport mode and PowerShell fallback configuration directly.
