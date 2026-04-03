# Product Scope

In scope for the current toolkit:
- read-only Windows diagnostics collection
- desktop GUI for operating the toolkit without manual command entry
- compiled desktop `exe` for managing network diagnostics sessions
- block-based text report generation under a predictable output root
- analyzer scripts that summarize signals for human and AI review
- safe validation to catch syntax and forbidden write operations
- packaging the runnable script bundle for release downloads
- SSH-based remote Windows diagnostics collection and AI-ready local bundle preparation
- native-first SSH collection through standard Windows commands with PowerShell fallback when needed
- Telegram alerting for selected monitoring events in concept form

Out of scope for the current toolkit:
- automatic repair actions on the machine
- agent-driven remediation
- cloud telemetry backend
- non-Windows execution support
- direct programmatic submission to ChatGPT/Codex through subscription accounts
