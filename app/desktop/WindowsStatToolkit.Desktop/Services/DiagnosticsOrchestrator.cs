using WindowsStatToolkit.Desktop.Interfaces;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class DiagnosticsOrchestrator(IRemoteDiagnosticsTransport transport)
{
    public async Task<bool> PingHostAsync(HostDefinition host)
    {
        return await transport.PingHostAsync(host);
    }

    public async Task<DiagnosticSnapshot> CollectSnapshotAsync(HostDefinition host, int? days, int maxEventsPerCategory, CancellationToken cancellationToken)
    {
        var query = new DiagnosticQuery(days, maxEventsPerCategory);
        return await transport.CollectSnapshotAsync(host, query, cancellationToken);
    }

    public async Task<GeneratedReport> GenerateReportAsync(HostDefinition host, int? days, string mode, CancellationToken cancellationToken)
    {
        var snapshot = await CollectSnapshotAsync(
            host,
            days,
            mode is "ai" or "analyze-ai" ? 1000 : 200,
            cancellationToken);

        return mode switch
        {
            "ai" => new GeneratedReport
            {
                Kind = "AI bundle",
                Extension = "json",
                Suffix = $"ai_bundle_{FormatRange(days)}",
                Content = ReportComposer.CreateAiBundleJson(host, snapshot)
            },
            "analyze-ai" => new GeneratedReport
            {
                Kind = "Analyze AI",
                Extension = "json",
                Suffix = $"analyze_ai_{FormatRange(days)}",
                Content = ReportComposer.CreateAnalyzeAiJson(host, snapshot)
            },
            "pc" => new GeneratedReport
            {
                Kind = "PC report",
                Extension = "md",
                Suffix = $"pc_report_{FormatRange(days)}",
                Content = ReportComposer.CreatePcSummaryMarkdown(host, snapshot)
            },
            _ => new GeneratedReport
            {
                Kind = DiagnosticBlockCatalog.Get(mode).Title,
                Extension = "md",
                Suffix = $"{mode}_{FormatRange(days)}",
                Content = ReportComposer.CreateBlockReportMarkdown(host, snapshot, mode)
            }
        };
    }

    private static string FormatRange(int? days)
    {
        return days.HasValue ? $"{days.Value}_days" : "all_time";
    }
}
