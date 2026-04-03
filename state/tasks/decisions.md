# Decisions

- `2026-04-03`: treat the legacy `C:\CodexTest` diagnostics workspace as a standalone product and import it into `NewCodex` under `windows-stat-toolkit`.
- `2026-04-03`: keep the current script set, including older analyzer generations, because the shipped validator still checks them.
- `2026-04-03`: implement the first remote diagnostics MVP as a script-first app inside the toolkit instead of jumping directly to a GUI.
- `2026-04-03`: support only local AI bundle preparation for ChatGPT/Codex, not direct app submission through subscription accounts.
- `2026-04-03`: after user clarification, promote the main operator experience to a GUI-first desktop workflow while preserving the CLI scripts as backend-compatible tools rather than the primary interface.
- `2026-04-03`: for the first compiled concept, build a .NET 8 WPF desktop app that uses SSH + remote PowerShell as the network execution layer and keeps AI bundles capped at 30 MB.
- `2026-04-03`: publish the compiled diagnostics desktop direction through a separate GitHub analysis trail using branch `windows-stat-toolkit-analysis` and product-scoped tag `windows-stat-toolkit-analysis-v0.5.0`.
- `2026-04-03`: evolve the analysis branch to a native-first SSH collector pipeline that uses standard Windows commands over SSH and leaves PowerShell as fallback or explicit operator choice.
- `2026-04-04`: move the desktop SSH execution layer from shelling out to `ssh.exe` toward an embedded SSH client with password auth and automatic fingerprint registration, because the process-based path produced broken collection runs and poor operator UX.
