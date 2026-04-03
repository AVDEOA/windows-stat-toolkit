# REPRODUCE v0.4.0

## Environment
- OS: Windows desktop session preferred
- Product root: `projects/windows-stat-toolkit`
- Main validator: `app/src/Validate-Toolkit.ps1`
- Desktop project: `app/desktop/WindowsStatToolkit.Desktop`
- Published exe: `artifacts/desktop-publish/WindowsStatToolkit.Desktop.exe`

## Steps
1. Run `ops\tools\test.cmd`.
2. Run `ops\tools\build.cmd`.
3. Run `ops\tools\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh 0.4.0`.
5. Launch `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`.
6. Add a host with SSH address, user, port, and optional key path.
7. Choose `3/7/14/30 days` or `All time`.
8. Generate `AI bundle <= 30 MB`, `PC report`, and `Block 1..7`.
9. Configure Telegram token/chat id and start monitoring if you want concept alerts.

## Expected
- The desktop project builds and publishes successfully.
- A single-file exe is present under `artifacts\desktop-publish`.
- Generated reports are saved under `%LocalAppData%\WindowsStatToolkit\reports`.
- AI bundles stay within the target size limit by trimming noisy categories when needed.
