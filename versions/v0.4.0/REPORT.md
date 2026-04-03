# REPORT v0.4.0

## Delivered
- Added a compiled .NET 8 WPF desktop application under `app/desktop/WindowsStatToolkit.Desktop`.
- Published a self-contained single-file `WindowsStatToolkit.Desktop.exe` into `artifacts/desktop-publish`.
- Added CRUD management for remote PCs, SSH + remote PowerShell snapshot collection, AI bundle generation capped at 30 MB, PC summary reports, and block-specific human-readable reports.
- Added concept monitoring with Telegram alerts for ping loss, low disk space, and newly observed critical event categories while the app is running.
- Updated build/rebuild/snapshot wrappers and product docs for the compiled desktop path.

## Validation
- `ops\tools\test.cmd`
- `ops\tools\build.cmd`
- `ops\tools\rebuild.cmd`
- `./ops/tools/snapshot-runtime.sh 0.4.0`
- `dotnet build app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj`
- `dotnet publish app\desktop\WindowsStatToolkit.Desktop\WindowsStatToolkit.Desktop.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true`

## Notes
- The compiled exe was successfully produced in this session, but interactive GUI execution was not exercised from WSL because it requires a Windows desktop session.
- Remote SSH collection assumes key or agent auth in concept v1.
- Monitoring currently works only while the desktop app remains open.
