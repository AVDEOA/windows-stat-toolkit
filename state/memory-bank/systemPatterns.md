# System Patterns

- Active scripts live only in `app/src/`.
- Validation uses Windows PowerShell syntax parsing and a forbidden-command audit to keep the toolkit read-only by default.
- The main operator UX is now a WPF desktop app backed by shared PowerShell service functions in `WindowsStatToolkit.AppModel.ps1`.
- The main operator UX is now a compiled .NET 8 WPF app in `app/desktop/WindowsStatToolkit.Desktop`.
- The desktop app now prefers a native SSH collector path that gathers `hostname`, `wmic`, and `wevtutil` output and classifies it in C#, with PowerShell retained as a fallback collector.
- The native app is now split into transport (`IRemoteDiagnosticsTransport`), orchestration (`DiagnosticsOrchestrator`), monitoring, report composition, and UI layers.
- Host definitions include a transport mode so operators can choose `auto`, `ssh_native`, or `ssh_powershell`.
- SSH command execution now runs through an embedded SSH client with saved host fingerprints and protected local password storage instead of shelling out to `ssh.exe`.
- AI bundle generation is JSON-first and must stay within a 30 MB ceiling by trimming noisy categories when needed.
- Rebuild prepares both script and desktop source bundles, while build publishes a self-contained desktop binary.
- Remote diagnostics writes mutable runtime state under `app/src/state/remote-diagnostics/`, which stays outside versioned source control.
- The desktop analysis line now has its own publication trail on GitHub so branch/tag history can track the compiled network-diagnostics product separately from the base product branch.
