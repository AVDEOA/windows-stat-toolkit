# Continuation

## Current Line

- Product: `windows-stat-toolkit`
- Active release: `v0.6.0`
- Separate publication trail for the desktop analysis line:
- branch: `windows-stat-toolkit-analysis`
- tag: `windows-stat-toolkit-analysis-v0.6.0`
- asset target: `WindowsStatToolkit-v0.6.0-win-x64.zip`
- release URL: `https://github.com/AVDEOA/windows-stat-toolkit/releases/tag/windows-stat-toolkit-analysis-v0.6.0`
- asset URL: `https://github.com/AVDEOA/windows-stat-toolkit/releases/download/windows-stat-toolkit-analysis-v0.6.0/WindowsStatToolkit-v0.6.0-win-x64.zip`

## What Was Built

- The toolkit now has a compiled `.NET 8 WPF` desktop app in `app/desktop/WindowsStatToolkit.Desktop`.
- The desktop app is no longer just a thin UX wrapper over the old scripts.
- The app is split into UI, models, transport, orchestration, monitoring, and report composition layers.
- Remote execution now prefers a native SSH collector pipeline built on `hostname`, `wmic`, and `wevtutil`, with PowerShell retained as a fallback or explicit transport mode.

## Main Files To Reopen First

- `app/desktop/WindowsStatToolkit.Desktop/MainWindow.xaml`
- `app/desktop/WindowsStatToolkit.Desktop/MainWindow.xaml.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/DiagnosticsOrchestrator.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/DiagnosticsTransportRouter.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/SshCommandRunner.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/SshNativeDiagnosticsTransport.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/SshPowerShellDiagnosticsTransport.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/ReportComposer.cs`
- `app/desktop/WindowsStatToolkit.Desktop/Services/MonitoringService.cs`
- `app/src/AnalizeV9.ps1`
- `state/tasks/next.md`

## Current Product Logic

- Host management, report actions, transport routing, and monitoring live in the compiled desktop app.
- Legacy PowerShell analyzers and block scripts remain part of the product because `AnalizeV9.ps1` is still the content baseline.
- `Analyze AI` should stay machine-first, compact, and optimized for neural-network ingestion rather than human readability.
- Human-readable per-block reports should continue to map to the block definitions from the analyzer family.

## Continuation Priority

1. Move long-running collection and monitor work off the UI thread into background jobs/services.
2. Promote monitoring from "works while app is open" to a persistent Windows service or agent.
3. Improve AI analysis output so it mirrors `AnalizeV9.ps1` coverage while staying compact and under the size cap.
4. Add stronger tests around parsing, categorization, bundle trimming, and report composition.
5. Reduce remaining WMIC dependence by moving more native collection work to newer Windows management APIs where practical.

## Resume Checklist

1. Open `state/memory-bank/activeContext.md`, this file, and `state/tasks/next.md`.
2. Check out `windows-stat-toolkit-analysis`.
3. Run `ops\tools\test.cmd`.
4. Run `ops\tools\build.cmd`.
5. Launch `artifacts\desktop-publish\WindowsStatToolkit.Desktop.exe` on Windows.
6. Continue from the top item in `state/tasks/next.md`.
