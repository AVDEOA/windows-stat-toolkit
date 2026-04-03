# Progress

- Imported the legacy diagnostics workspace into the `NewCodex` product layout.
- Added validation wrappers, rebuild flow, and release dossier scaffolding for `v0.1.0`.
- Started `v0.2.0` work for SSH-based remote diagnostics and AI-ready bundle preparation.
- Promoted the toolkit toward `v0.3.0` with a desktop WPF GUI for local diagnostics, SSH host management, and bundle browsing.
- Delivered a first compiled `exe` concept for `v0.4.0` with host management, remote snapshots, capped AI bundles, block reports, and Telegram monitoring.
- Refactored the desktop app toward `v0.5.0` with separated transport/orchestrator/domain layers closer to the structure used by `S3Drive`.
- Prepared a separate GitHub publication trail for the desktop analysis line so future work can continue from the compiled app architecture instead of falling back to the old script-first flow.
- Published the `v0.5.0` analysis line on GitHub with branch `windows-stat-toolkit-analysis`, tag `windows-stat-toolkit-analysis-v0.5.0`, a release page, and a runnable `WindowsStatToolkit-v0.5.0-win-x64.zip` asset.
- Promoted the collector design again for `v0.6.0`: the desktop app now prefers native Windows command collection over SSH and only falls back to PowerShell when native collection fails or the host is configured for explicit PowerShell mode.
- Published the `v0.6.0` analysis line on GitHub with branch `windows-stat-toolkit-analysis`, tag `windows-stat-toolkit-analysis-v0.6.0`, a release page, and a runnable `WindowsStatToolkit-v0.6.0-win-x64.zip` asset.
