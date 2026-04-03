# Active Context

- `windows-stat-toolkit` was imported from the legacy `C:\CodexTest` script workspace.
- The active product is a Windows diagnostics and analysis toolkit centered on `AnalizeV9.ps1`, the collection blocks, and the shared helper module.
- Release discipline now follows the same package contract used by other `NewCodex` products.
- Current active package is `v0.6.0`: move the desktop product from an isolated PowerShell transport toward a native-first SSH collector pipeline with PowerShell retained only for fallback or explicit operator choice.
- The compiled desktop line is now being published through a separate analysis branch/tag trail so the AI/network diagnostics direction can evolve without losing product-scoped release discipline.
- Resume context for the next chat is captured in `state/memory-bank/continuation.md`.
- Published analysis trail:
- branch: `windows-stat-toolkit-analysis`
- tag: `windows-stat-toolkit-analysis-v0.5.0`
- release: `https://github.com/AVDEOA/windows-stat-toolkit/releases/tag/windows-stat-toolkit-analysis-v0.5.0`
