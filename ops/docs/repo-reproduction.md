# Repo Reproduction

## Environment

- Product root: `projects/windows-stat-toolkit`
- Runtime: Windows PowerShell scripts
- Main validator: `app/src/Validate-Toolkit.ps1`
- Main analyzer baseline: `app/src/AnalizeV9.ps1`
- Main desktop entrypoint: `artifacts/desktop-publish/WindowsStatToolkit.Desktop.exe`
- Remote diagnostics CLI: `app/src/RemoteDiagnostics.App.ps1`
- Default desktop host mode: `auto` = native SSH first, PowerShell fallback

## Verification Paths

1. Run `ops\\tools\\test.cmd`.
2. Run `ops\\tools\\build.cmd`.
3. Run `./ops/tools/rebuild.sh` or `ops\\tools\\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh`.
5. On a Windows desktop session, run `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`.
6. Add a host in `Auto` mode and verify that report generation succeeds for either the native collector or the PowerShell fallback path.

## Optional Host Run

If you want a real report collection on a Windows host, run:

- `powershell.exe -ExecutionPolicy Bypass -File app\src\Run-All-Stat-Collection.ps1`
- `powershell.exe -ExecutionPolicy Bypass -File app\src\AnalizeV9.ps1`
- `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`
- `powershell.exe -ExecutionPolicy Bypass -File app\src\RemoteDiagnostics.App.ps1 -Command Init`
