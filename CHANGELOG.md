# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [0.6.0] - 2026-04-03

### Added
- Added a native-first SSH diagnostics pipeline with `SshCommandRunner`, `SshNativeDiagnosticsTransport`, and `DiagnosticsTransportRouter`.
- Added per-host connection modes so operators can choose `auto`, `ssh_native`, or `ssh_powershell`.
- Added collector metadata into snapshots and reports so saved evidence shows which transport actually produced the data and whether fallback was used.

### Changed
- The desktop app now prefers native Windows commands over SSH such as `hostname`, `wmic`, and `wevtutil`, with PowerShell retained as an explicit mode and fallback path instead of the only collector.
- Host editing and managed-host views now expose the active transport mode and explain the PowerShell fallback shell more clearly.

## [0.5.0] - 2026-04-03

### Added
- Added a native diagnostics architecture layer with `IRemoteDiagnosticsTransport`, `SshPowerShellDiagnosticsTransport`, `DiagnosticsOrchestrator`, and a reusable block catalog.
- Added dedicated models for diagnostic queries, generated reports, and block definitions so the desktop app now has a clearer domain layer instead of pushing orchestration into the window code.

### Changed
- Refactored the desktop app closer to the `S3Drive` structure: UI, transport, orchestration, monitoring, and report composition are now separated into purpose-specific components.
- Main window report generation and monitoring now run through the orchestrator instead of calling transport/report logic directly.

## [0.4.0] - 2026-04-03

### Added
- Added `app/desktop/WindowsStatToolkit.Desktop`, a .NET 8 WPF desktop application that builds and publishes a real `WindowsStatToolkit.Desktop.exe`.
- Added host CRUD, range-based remote collection, AI bundle generation with a 30 MB cap, PC summary reports, and human-readable block report buttons inside the desktop app.
- Added concept monitoring with Telegram alerts for ping loss, low disk space, and newly observed critical event categories while the app is running.

### Changed
- Shifted the main product direction from prototype GUI wrappers to a compiled network diagnostics desktop product.
- Updated product build and rebuild wrappers to include the desktop project and self-contained publish output.

## [0.3.0] - 2026-04-03

### Added
- Added `WindowsStatToolkit.App.ps1` as a desktop WPF GUI for local diagnostics, analyzer запусков, SSH host management, and bundle browsing.
- Added `WindowsStatToolkit.AppModel.ps1` as a shared application layer that aggregates local system overview, report catalog, remote hosts, and saved bundle metadata.

### Changed
- Shifted the active product direction from script-first remote MVP to a GUI-first workstation tool built on top of the existing diagnostics scripts.
- Updated docs, runbooks, and product memory to treat the GUI as the main user-facing entrypoint for day-to-day work.

## [0.2.0] - 2026-04-03

### Added
- Added `RemoteDiagnostics.App.ps1` and `RemoteDiagnostics.Common.ps1` as an MVP remote diagnostics application inside the toolkit.
- Added SSH host configuration flow, remote Windows diagnostics collection, local structured bundle output, and AI-ready prompt generation for manual ChatGPT/Codex use.
- Added `remote_hosts.example.json` as a starting template for SSH host inventory.

### Changed
- Updated validation to discover all active PowerShell scripts automatically instead of maintaining a fixed manual file list.
- Updated product docs and instructions to cover the new remote diagnostics workflow.

## [0.1.0] - 2026-04-03

### Added
- Imported the legacy Windows diagnostics and analysis toolkit from `C:\CodexTest` into the `NewCodex` package layout.
- Added product docs, state files, validation wrappers, rebuild flow, and the initial release dossier.
- Preserved the old root continuity notes under `ops/docs/legacy-notes/`.
