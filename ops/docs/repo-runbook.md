# Product Runbook

- Lint: `./ops/tools/lint.sh`
- Smoke: `./ops/tools/test.sh --smoke`
- Full: `./ops/tools/test.sh`
- Build: `./ops/tools/build.sh`
- Rebuild runnable bundle: `./ops/tools/rebuild.sh`
- Snapshot runtime: `./ops/tools/snapshot-runtime.sh`

Notes:
- Windows wrappers are the source of truth for validation because the toolkit targets Windows PowerShell and Windows event sources.
- Smoke/full/build use `Validate-Toolkit.ps1` without host data collection by default.
- Rebuild prepares a runnable source bundle in `artifacts/runtime-src/` for release packaging.
- Release-ready work finishes with version bump, dossier, rebuild, runtime snapshot, and GitHub publication.
