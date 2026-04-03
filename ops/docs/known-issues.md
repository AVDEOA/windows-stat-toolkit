# Known Issues

- Full collection runs write reports into `C:\Stat`, so they should be treated as host-level validation rather than sandbox-safe checks.
- The toolkit is designed for Windows PowerShell workflows; WSL is mainly used for packaging and repository work.
- The active validator checks syntax and blocked command patterns, but it does not yet unit-test every analysis heuristic.
