# Tech Context

- Language/runtime: Windows PowerShell scripts
- Main module: `StatToolkit.Common.ps1`
- Main analyzer baseline: `AnalizeV9.ps1`
- Main GUI entrypoint: `WindowsStatToolkit.App.ps1`
- GUI application layer: `WindowsStatToolkit.AppModel.ps1`
- Main compiled desktop app: `app/desktop/WindowsStatToolkit.Desktop`
- Desktop runtime: .NET 8 WPF, self-contained `win-x64` publish
- Native architecture: transport interface + SSH transport + diagnostics orchestrator + monitoring/report services
- Remote diagnostics entrypoint: `RemoteDiagnostics.App.ps1`
- Validation contract: syntax parse, safety audit, runnable bundle rebuild, runtime snapshot
- Continuation anchor: `state/memory-bank/continuation.md`
