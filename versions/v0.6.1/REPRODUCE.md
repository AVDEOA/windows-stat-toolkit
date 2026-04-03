# REPRODUCE v0.6.1

## Environment
- OS: Windows desktop session preferred
- Product root: `projects/windows-stat-toolkit`
- Desktop project: `app/desktop/WindowsStatToolkit.Desktop`
- Portable publish folder: `artifacts/desktop-publish/`

## Steps
1. Run `ops\tools\test.cmd`.
2. Run `ops\tools\build.cmd`.
3. Run `ops\tools\rebuild.cmd`.
4. Run `./ops/tools/snapshot-runtime.sh 0.6.1`.
5. Launch `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`.
6. Create or edit a host, fill in password or key path, run `Test SSH`, then generate a report.

## Expected
- Desktop app builds and publishes successfully.
- SSH connectivity tests succeed with password or key auth.
- First successful SSH connection stores the host fingerprint and later mismatches are blocked.
