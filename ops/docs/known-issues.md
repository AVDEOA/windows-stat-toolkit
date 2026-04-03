# Known Issues

- Full collection runs write reports into `C:\Stat`, so they should be treated as host-level validation rather than sandbox-safe checks.
- The toolkit is designed for Windows PowerShell workflows; WSL is mainly used for packaging and repository work.
- The GUI depends on WPF and is expected to run on a Windows desktop session rather than inside WSL.
- Concept monitoring runs only while the desktop app is open; a Windows Service/agent mode is still future work.
- Remote collection now supports SSH password or key authentication, but it does not yet support a full credential vault UX or SSH agent-specific workflows.
- The active validator checks syntax and blocked command patterns, but it does not yet unit-test every analysis heuristic.
- Native SSH collection currently depends on classic Windows command-line tooling such as `hostname`, `wmic`, and `wevtutil`; if one of those tools is missing or blocked, Auto mode falls back to PowerShell over SSH.
- The desktop app now uses an embedded SSH client library rather than shelling out to `ssh.exe`, but the target Windows host still needs reachable SSH service and PowerShell remains required for fallback and explicit PowerShell mode.
- The toolkit can prepare AI-ready bundles, but it does not directly submit data to ChatGPT/Codex because subscription accounts do not expose a supported app-integration path.
