# REPRODUCE v0.2.0

## Environment
- OS: Windows host preferred
- Product root: `projects/windows-stat-toolkit`
- Main validator: `app/src/Validate-Toolkit.ps1`
- Remote diagnostics entrypoint: `app/src/RemoteDiagnostics.App.ps1`

## Steps
1. Run `ops\tools\test.cmd`.
2. Run `powershell.exe -ExecutionPolicy Bypass -File .\app\src\RemoteDiagnostics.App.ps1 -Command Init`.
3. Add a host with `-Command AddHost`.
4. Run `-Command Collect -HostName <name> -Days 7`.
5. Run `-Command PrepareAnalysis -HostName <name> -Days 7`.

## Expected
- The toolkit validates cleanly.
- A collection bundle is created under `app\src\state\remote-diagnostics\collections\...`.
- The bundle contains `collection.json`, `summary.md`, and `analysis_prompt.md`.
