using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public static class ReportComposer
{
    private const int MaxAiBundleBytes = 30 * 1024 * 1024;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public static string CreateAiBundleJson(HostDefinition host, DiagnosticSnapshot snapshot)
    {
        var dto = new
        {
            bundle_type = "ai_diagnostics",
            generated_at = DateTimeOffset.Now,
            host = new
            {
                host.Name,
                host.Address,
                host.UserName,
                host.Tags,
                host.TransportMode
            },
            collection = snapshot,
            findings = BuildFindingLines(snapshot),
            guidance = new
            {
                target = "neural-analysis",
                requirements = new[]
                {
                    "Separate confirmed evidence from hypotheses.",
                    "Rank likely root causes by severity.",
                    "Highlight driver, gpu, hardware, storage, shutdown and critical patterns.",
                    "Recommend the next diagnostic or remediation steps."
                }
            }
        };

        return SerializeWithLimit(dto, snapshot);
    }

    public static string CreateAnalyzeAiJson(HostDefinition host, DiagnosticSnapshot snapshot)
    {
        var severityRank = new Dictionary<string, int>
        {
            ["critical"] = 100,
            ["hardware"] = 90,
            ["bsod"] = 85,
            ["gpu"] = 80,
            ["storage"] = 78,
            ["driver"] = 72,
            ["restart_shutdown"] = 60
        };

        var issueClusters = snapshot.Categories
            .Select(pair => new
            {
                key = pair.Key,
                title = pair.Value.Title,
                count = pair.Value.Count,
                severity_rank = severityRank.TryGetValue(pair.Key, out var rank) ? rank : 40,
                top_events = pair.Value.Events
                    .Take(80)
                    .Select(evt => new
                    {
                        ts = evt.TimeCreated,
                        provider = evt.Provider,
                        id = evt.Id,
                        level = evt.Level,
                        log = evt.LogName,
                        msg = evt.Message
                    })
                    .ToArray()
            })
            .Where(x => x.count > 0)
            .OrderByDescending(x => x.severity_rank)
            .ThenByDescending(x => x.count)
            .ToArray();

        var dto = new
        {
            report_type = "analyze_ai",
            generated_at = DateTimeOffset.Now,
            host = new
            {
                host.Name,
                host.Address,
                host.UserName,
                host.Tags,
                host.TransportMode,
                snapshot.Host.ComputerName,
                snapshot.Host.OsCaption,
                snapshot.Host.OsVersion,
                snapshot.Host.LastBoot,
                snapshot.Host.UptimeDays,
                snapshot.Host.BiosVersion,
                cpu = snapshot.Host.Cpu,
                gpus = snapshot.Host.Gpus,
                memory_gb = snapshot.Host.MemoryGb,
                disks = snapshot.Host.Disks
            },
            range = new
            {
                snapshot.PeriodLabel,
                snapshot.PeriodDays,
                snapshot.StartTime
            },
            issue_clusters = issueClusters,
            compact_findings = BuildFindingLines(snapshot),
            recommended_next_steps = BuildRecommendedSteps(snapshot),
            machine_notes = new[]
            {
                "This file is optimized for AI ingestion rather than human readability.",
                "Treat compact_findings as summaries and issue_clusters as supporting evidence.",
                "Use severity_rank plus event counts to prioritize root cause analysis."
            }
        };

        return SerializeCompactWithLimit(dto, snapshot);
    }

    public static string CreatePcSummaryMarkdown(HostDefinition host, DiagnosticSnapshot snapshot)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"# PC Report - {host.Name}");
        sb.AppendLine();
        sb.AppendLine($"- Address: {host.Address}");
        sb.AppendLine($"- Connection mode: {host.TransportMode}");
        sb.AppendLine($"- Computer: {snapshot.Host.ComputerName}");
        sb.AppendLine($"- OS: {snapshot.Host.OsCaption} {snapshot.Host.OsVersion}");
        sb.AppendLine($"- Last boot: {snapshot.Host.LastBoot}");
        sb.AppendLine($"- Uptime days: {snapshot.Host.UptimeDays}");
        sb.AppendLine($"- BIOS: {snapshot.Host.BiosVersion}");
        sb.AppendLine($"- Collector: {snapshot.Collector.TransportName}");
        if (snapshot.Collector.FallbackUsed)
        {
            sb.AppendLine("- Fallback: native collector failed and the PowerShell collector completed the snapshot");
        }
        sb.AppendLine($"- CPU: {string.Join(", ", snapshot.Host.Cpu)}");
        sb.AppendLine($"- GPU: {string.Join(", ", snapshot.Host.Gpus)}");
        sb.AppendLine($"- Memory GB: {snapshot.Host.MemoryGb}");
        sb.AppendLine();
        sb.AppendLine("## Disk overview");
        foreach (var disk in snapshot.Host.Disks)
        {
            sb.AppendLine($"- {disk.DeviceId}: free {disk.FreeGb} GB of {disk.SizeGb} GB ({disk.FileSystem})");
        }

        sb.AppendLine();
        sb.AppendLine("## Brief issue summary");
        foreach (var finding in BuildFindingLines(snapshot))
        {
            sb.AppendLine($"- {finding}");
        }

        sb.AppendLine();
        sb.AppendLine("## Category counts");
        foreach (var category in snapshot.Categories)
        {
            sb.AppendLine($"- {category.Value.Title}: {category.Value.Count}");
        }

        return sb.ToString();
    }

    public static string CreateBlockReportMarkdown(HostDefinition host, DiagnosticSnapshot snapshot, string blockId)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"# {DiagnosticBlockCatalog.Get(blockId).Title} - {host.Name}");
        sb.AppendLine();
        sb.AppendLine($"- Address: {host.Address}");
        sb.AppendLine($"- Connection mode: {host.TransportMode}");
        sb.AppendLine($"- Generated at: {snapshot.GeneratedAt}");
        sb.AppendLine($"- Range: {snapshot.PeriodLabel}");
        sb.AppendLine($"- Collector: {snapshot.Collector.TransportName}");
        sb.AppendLine();

        switch (blockId)
        {
            case "block1":
                sb.AppendLine("## Configuration");
                sb.AppendLine($"- Computer: {snapshot.Host.ComputerName}");
                sb.AppendLine($"- OS: {snapshot.Host.OsCaption} {snapshot.Host.OsVersion}");
                sb.AppendLine($"- BIOS: {snapshot.Host.BiosVersion}");
                sb.AppendLine($"- CPU: {string.Join(", ", snapshot.Host.Cpu)}");
                sb.AppendLine($"- GPU: {string.Join(", ", snapshot.Host.Gpus)}");
                sb.AppendLine($"- Memory GB: {snapshot.Host.MemoryGb}");
                foreach (var disk in snapshot.Host.Disks)
                {
                    sb.AppendLine($"- Disk {disk.DeviceId}: free {disk.FreeGb} GB of {disk.SizeGb} GB");
                }
                break;
            case "block2":
                sb.AppendLine("## Stability");
                AppendCategory(sb, snapshot, "restart_shutdown");
                AppendCategory(sb, snapshot, "critical");
                break;
            case "block3":
                AppendCategory(sb, snapshot, "driver");
                break;
            case "block4":
                AppendCategory(sb, snapshot, "gpu");
                break;
            case "block5":
                AppendCategory(sb, snapshot, "hardware");
                break;
            case "block6":
                AppendCategory(sb, snapshot, "bsod");
                break;
            case "block7":
                AppendCategory(sb, snapshot, "critical");
                AppendCategory(sb, snapshot, "storage");
                break;
        }

        return sb.ToString();
    }

    private static void AppendCategory(StringBuilder sb, DiagnosticSnapshot snapshot, string key)
    {
        if (!snapshot.Categories.TryGetValue(key, out var category))
        {
            sb.AppendLine($"## {key}");
            sb.AppendLine("No data.");
            return;
        }

        sb.AppendLine($"## {category.Title}");
        sb.AppendLine($"- Count: {category.Count}");
        sb.AppendLine();

        foreach (var evt in category.Events)
        {
            sb.AppendLine($"- [{evt.TimeCreated}] {evt.Provider} | ID {evt.Id} | {evt.Level} | {evt.LogName}");
            sb.AppendLine($"  {evt.Message}");
        }
    }

    private static List<string> BuildFindingLines(DiagnosticSnapshot snapshot)
    {
        var findings = new List<string>();

        foreach (var disk in snapshot.Host.Disks.Where(d => d.FreeGb.HasValue && d.FreeGb.Value < 10))
        {
            findings.Add($"Low disk space on {disk.DeviceId}: {disk.FreeGb:0.##} GB free.");
        }

        foreach (var pair in snapshot.Categories.OrderByDescending(p => p.Value.Count))
        {
            if (pair.Value.Count <= 0)
            {
                continue;
            }

            findings.Add($"{pair.Value.Title}: {pair.Value.Count} events in the selected range.");
        }

        if (findings.Count == 0)
        {
            findings.Add("No high-signal issues were detected in the selected range.");
        }

        return findings;
    }

    private static string SerializeWithLimit(object dto, DiagnosticSnapshot snapshot)
    {
        var json = JsonSerializer.Serialize(dto, JsonOptions);
        if (Encoding.UTF8.GetByteCount(json) <= MaxAiBundleBytes)
        {
            return json;
        }

        var mutable = snapshot.Categories.Values
            .OrderByDescending(c => c.Events.Count)
            .ToList();

        while (Encoding.UTF8.GetByteCount(json) > MaxAiBundleBytes && mutable.Any(c => c.Events.Count > 10))
        {
            var largest = mutable.OrderByDescending(c => c.Events.Count).First();
            largest.Events = largest.Events.Take(Math.Max(10, largest.Events.Count / 2)).ToList();
            json = JsonSerializer.Serialize(dto, JsonOptions);
        }

        return json;
    }

    private static string SerializeCompactWithLimit(object dto, DiagnosticSnapshot snapshot)
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = false,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };

        var json = JsonSerializer.Serialize(dto, options);
        if (Encoding.UTF8.GetByteCount(json) <= MaxAiBundleBytes)
        {
            return json;
        }

        var mutable = snapshot.Categories.Values.OrderByDescending(c => c.Events.Count).ToList();
        while (Encoding.UTF8.GetByteCount(json) > MaxAiBundleBytes && mutable.Any(c => c.Events.Count > 8))
        {
            var largest = mutable.OrderByDescending(c => c.Events.Count).First();
            largest.Events = largest.Events.Take(Math.Max(8, largest.Events.Count / 2)).ToList();
            json = JsonSerializer.Serialize(dto, options);
        }

        return json;
    }

    private static IReadOnlyList<string> BuildRecommendedSteps(DiagnosticSnapshot snapshot)
    {
        var steps = new List<string>();

        if (snapshot.Categories.TryGetValue("gpu", out var gpu) && gpu.Count > 0)
        {
            steps.Add("Inspect GPU driver stability, TDR patterns, and recent graphics stack changes.");
        }

        if (snapshot.Categories.TryGetValue("storage", out var storage) && storage.Count > 0)
        {
            steps.Add("Validate disk health, SMART/NVMe counters, and free space on the affected volumes.");
        }

        if (snapshot.Categories.TryGetValue("bsod", out var bsod) && bsod.Count > 0)
        {
            steps.Add("Collect and correlate minidumps with stop codes and recently changed drivers.");
        }

        if (snapshot.Categories.TryGetValue("driver", out var driver) && driver.Count > 0)
        {
            steps.Add("Review failing devices, recent driver installs, and hidden/ghost device entries.");
        }

        if (snapshot.Categories.TryGetValue("hardware", out var hardware) && hardware.Count > 0)
        {
            steps.Add("Check WHEA/PCIe patterns against hardware stability, thermals, and firmware.");
        }

        if (steps.Count == 0)
        {
            steps.Add("No dominant error cluster was detected. Review the raw event mix and recent system changes.");
        }

        return steps;
    }
}
