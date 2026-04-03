# REPRODUCE v0.3.0

## Environment
- OS: Windows desktop session preferred for GUI launch
- Product root: `projects/windows-stat-toolkit`
- Main validator: `app/src/Validate-Toolkit.ps1`
- Main GUI entrypoint: `app/src/WindowsStatToolkit.App.ps1`
- Remote diagnostics CLI: `app/src/RemoteDiagnostics.App.ps1`

## Steps
1. Run `ops\tools\test.cmd`.
2. Run `ops\tools\build.cmd`.
3. Run `ops\tools\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh 0.3.0`.
5. On Windows, run `powershell.exe -ExecutionPolicy Bypass -File .\app\src\WindowsStatToolkit.App.ps1`.
6. Use the `Локальная диагностика` tab to start a full collection or targeted block.
7. Use the `Удалённые хосты` tab to save a host and trigger SSH collection or prompt generation.
8. Use the `Bundle и анализ` tab to preview `summary.md` and open the saved bundle folder.

## Expected
- The toolkit validates cleanly.
- The GUI opens with local overview data and action grids.
- Local reports continue to appear under `C:\Stat`.
- Remote bundle metadata remains under `app\src\state\remote-diagnostics\collections\...`.
