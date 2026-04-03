# SPEC v0.3.0

## Goal
- Deliver a desktop-style operator experience for Windows Stat Toolkit so the primary workflow does not depend on memorizing or typing PowerShell commands.

## Requirements
- Expose local system overview and recent report files in a GUI.
- Allow launching the existing local diagnostics blocks and `AnalizeV9.ps1` from the GUI.
- Allow managing SSH hosts and triggering remote collection / AI bundle preparation from the GUI.
- Allow browsing saved bundle metadata and previewing `summary.md`.
- Preserve the read-only diagnostics posture and existing validation / packaging contract.

## Non-goals
- No direct ChatGPT/Codex API submission from the app.
- No migration to a compiled .NET codebase in this release.
- No automatic remediation or repair actions on the target machine.
