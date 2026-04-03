# REPRODUCE v0.6.0

## Environment
- OS: Windows desktop session preferred
- Product root: `projects/windows-stat-toolkit`
- Desktop project: `app/desktop/WindowsStatToolkit.Desktop`
- Published exe: `artifacts/desktop-publish/WindowsStatToolkit.Desktop.exe`

## Steps
1. Run `ops\tools\test.cmd`.
2. Run `ops\tools\build.cmd`.
3. Run `ops\tools\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh 0.6.0`.
5. Launch `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`.
6. Add a host in `Auto` mode and generate a report.

## Expected
- Desktop app builds and publishes successfully.
- The app prefers native SSH collection and falls back to PowerShell only when native collection cannot complete.
