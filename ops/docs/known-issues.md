# Known Issues

- Full collection runs write reports into `C:\Stat`, so they should be treated as host-level validation rather than sandbox-safe checks.
- The toolkit is designed for Windows PowerShell workflows; WSL is mainly used for packaging and repository work.
- The GUI depends on WPF and is expected to run on a Windows desktop session rather than inside WSL.
- Concept monitoring runs only while the desktop app is open; a Windows Service/agent mode is still future work.
- Remote collection currently assumes SSH key or agent auth; password-based SSH UX is not yet included.
- The active validator checks syntax and blocked command patterns, but it does not yet unit-test every analysis heuristic.
- The remote diagnostics MVP requires `ssh.exe` locally and a reachable Windows host with SSH access and PowerShell available remotely.
- The toolkit can prepare AI-ready bundles, but it does not directly submit data to ChatGPT/Codex because subscription accounts do not expose a supported app-integration path.
