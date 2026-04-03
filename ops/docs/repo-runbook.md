# Product Runbook

- Lint: `./ops/tools/lint.sh`
- Smoke: `./ops/tools/test.sh --smoke`
- Full: `./ops/tools/test.sh`
- Build: `./ops/tools/build.sh`
- Rebuild runnable bundle: `./ops/tools/rebuild.sh`
- Snapshot runtime: `./ops/tools/snapshot-runtime.sh`
- Launch compiled app on Windows: `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`

Notes:
- Windows wrappers are the source of truth because the toolkit now includes both Windows PowerShell diagnostics and a Windows desktop application.
- Smoke/full/build use `Validate-Toolkit.ps1` without host data collection by default.
- `test.cmd` validates PowerShell and builds the desktop project.
- `build.cmd` validates PowerShell and publishes the self-contained desktop `exe`.
- Rebuild prepares runnable source bundles in `artifacts/runtime-src/` and `artifacts/runtime-desktop-src/`.
- Release-ready work finishes with version bump, dossier, rebuild, runtime snapshot, and GitHub publication.
- Main desktop entrypoint: `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe`
- Legacy PowerShell GUI and remote CLI remain available under `app\src\`.
