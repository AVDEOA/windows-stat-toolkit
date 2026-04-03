# REPORT v0.5.0

## Delivered
- Added a transport/orchestrator architecture layer inside the desktop product.
- Moved remote collection behind `IRemoteDiagnosticsTransport` and `SshPowerShellDiagnosticsTransport`.
- Added `DiagnosticsOrchestrator` and native block/report metadata models so UI code is no longer the central coordination layer.
- Wired monitoring and report generation through the new orchestration path.

## Validation
- `dotnet build app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj`
- `dotnet publish app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true`
- `ops\tools\test.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh 0.5.0`

## Notes
- The transport is still SSH + remote PowerShell today, but the desktop app now depends on an interface boundary rather than embedding transport details into the window layer.
- GitHub publication trail for this release uses branch `windows-stat-toolkit-analysis`, tag `windows-stat-toolkit-analysis-v0.5.0`, and the runnable asset `WindowsStatToolkit-v0.5.0-win-x64.zip`.
