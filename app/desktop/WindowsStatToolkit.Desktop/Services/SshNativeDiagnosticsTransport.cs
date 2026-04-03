using System.Globalization;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using WindowsStatToolkit.Desktop.Interfaces;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed partial class SshNativeDiagnosticsTransport(SshCommandRunner commandRunner) : IRemoteDiagnosticsTransport
{
    private static readonly string[] RestartProviders =
    [
        "kernel-power", "eventlog", "user32"
    ];

    private static readonly string[] DriverProviders =
    [
        "kernel-pnp", "userpnp", "devicesetupmanager"
    ];

    private static readonly string[] GpuProviders =
    [
        "display", "nvlddmkm", "nvidia", "amdkmdag", "amdwddmg", "amd", "dxgkrnl"
    ];

    private static readonly string[] HardwareProviders =
    [
        "whea"
    ];

    private static readonly string[] BsodProviders =
    [
        "bugcheck", "wer-systemerrorreporting", "windows error reporting", "kernel-power"
    ];

    private static readonly string[] StorageProviders =
    [
        "disk", "storahci", "stornvme", "iastora", "iastorv", "volmgr", "partmgr", "ntfs", "refs", "chkdsk"
    ];

    private static readonly int[] RestartIds = [41, 1074, 1076, 6005, 6006, 6008, 109];

    public async Task<bool> PingHostAsync(HostDefinition host)
    {
        using var ping = new Ping();
        var reply = await ping.SendPingAsync(host.Address, 3000);
        return reply.Status == IPStatus.Success;
    }

    public async Task<DiagnosticSnapshot> CollectSnapshotAsync(
        HostDefinition host,
        DiagnosticQuery query,
        CancellationToken cancellationToken)
    {
        var inventoryTask = CollectInventoryAsync(host, cancellationToken);
        var systemEventsTask = CollectLogEventsAsync(host, "System", query, cancellationToken);
        var appEventsTask = CollectLogEventsAsync(host, "Application", query, cancellationToken);

        await Task.WhenAll(inventoryTask, systemEventsTask, appEventsTask);

        var allEvents = systemEventsTask.Result
            .Concat(appEventsTask.Result)
            .OrderByDescending(evt => evt.Timestamp)
            .ToList();

        var start = query.Days.HasValue
            ? DateTime.UtcNow.AddDays(-query.Days.Value)
            : DateTime.UtcNow.AddYears(-20);

        var snapshot = new DiagnosticSnapshot
        {
            GeneratedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            PeriodLabel = query.Days.HasValue ? $"{query.Days.Value}_days" : "all_time",
            PeriodDays = query.Days,
            StartTime = start.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            Collector = new CollectorMetadata
            {
                RequestedMode = "ssh_native",
                TransportName = "ssh_native",
                FallbackUsed = false
            },
            Host = inventoryTask.Result,
            Categories = BuildCategories(allEvents, query.MaxEventsPerCategory)
        };

        return snapshot;
    }

    private async Task<HostInventory> CollectInventoryAsync(HostDefinition host, CancellationToken cancellationToken)
    {
        var hostnameTask = RunSimpleCommandAsync(host, "hostname", cancellationToken);
        var osTask = RunSimpleCommandAsync(host, "wmic", ["os", "get", "Caption,Version,LastBootUpTime", "/value"], cancellationToken);
        var biosTask = RunSimpleCommandAsync(host, "wmic", ["bios", "get", "SMBIOSBIOSVersion", "/value"], cancellationToken);
        var cpuTask = RunSimpleCommandAsync(host, "wmic", ["cpu", "get", "Name", "/value"], cancellationToken);
        var gpuTask = RunSimpleCommandAsync(host, "wmic", ["path", "win32_VideoController", "get", "Name", "/value"], cancellationToken);
        var memoryTask = RunSimpleCommandAsync(host, "wmic", ["memorychip", "get", "Capacity", "/value"], cancellationToken);
        var diskTask = RunSimpleCommandAsync(host, "wmic", ["logicaldisk", "where", "DriveType=3", "get", "DeviceID,FreeSpace,FileSystem,Size", "/format:csv"], cancellationToken);

        await Task.WhenAll(hostnameTask, osTask, biosTask, cpuTask, gpuTask, memoryTask, diskTask);

        var osValues = ParseKeyValueLines(osTask.Result);
        var biosValues = ParseKeyValueLines(biosTask.Result);
        var cpuValues = ParseMultiValueLines(cpuTask.Result, "Name");
        var gpuValues = ParseMultiValueLines(gpuTask.Result, "Name");
        var memoryValues = ParseMultiValueLines(memoryTask.Result, "Capacity");

        return new HostInventory
        {
            ComputerName = hostnameTask.Result.Trim(),
            OsCaption = osValues.GetValueOrDefault("Caption", string.Empty),
            OsVersion = osValues.GetValueOrDefault("Version", string.Empty),
            LastBoot = FormatWmiDateTime(osValues.GetValueOrDefault("LastBootUpTime", string.Empty)),
            UptimeDays = ParseUptimeDays(osValues.GetValueOrDefault("LastBootUpTime", string.Empty)),
            BiosVersion = biosValues.GetValueOrDefault("SMBIOSBIOSVersion", string.Empty),
            Cpu = cpuValues,
            Gpus = gpuValues,
            MemoryGb = ParseMemoryGb(memoryValues),
            Disks = ParseDiskCsv(diskTask.Result)
        };
    }

    private async Task<List<NativeEventRecord>> CollectLogEventsAsync(
        HostDefinition host,
        string logName,
        DiagnosticQuery query,
        CancellationToken cancellationToken)
    {
        var args = new List<string>
        {
            "qe",
            logName,
            "/rd:true",
            "/f:xml",
            $"/c:{Math.Max(query.MaxEventsPerCategory * 8, 240)}"
        };

        var queryArg = BuildWevtutilQuery(query.Days);
        if (!string.IsNullOrWhiteSpace(queryArg))
        {
            args.Add($"/q:{queryArg}");
        }

        var xml = await RunSimpleCommandAsync(host, "wevtutil", args, cancellationToken);
        return ParseWevtutilXml(xml, logName);
    }

    private async Task<string> RunSimpleCommandAsync(
        HostDefinition host,
        string executable,
        CancellationToken cancellationToken)
    {
        return await RunSimpleCommandAsync(host, executable, [], cancellationToken);
    }

    private async Task<string> RunSimpleCommandAsync(
        HostDefinition host,
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        return (await commandRunner.RunCommandAsync(host, executable, arguments, cancellationToken)).Trim();
    }

    private static string BuildWevtutilQuery(int? days)
    {
        const string levelFilter = "(Level=1 or Level=2 or Level=3 or Level=4)";
        if (!days.HasValue)
        {
            return $"*[System[{levelFilter}]]";
        }

        var milliseconds = (long)TimeSpan.FromDays(days.Value).TotalMilliseconds;
        return $"*[System[TimeCreated[timediff(@SystemTime)<={milliseconds}] and {levelFilter}]]";
    }

    private static Dictionary<string, DiagnosticCategory> BuildCategories(
        IReadOnlyList<NativeEventRecord> allEvents,
        int maxEventsPerCategory)
    {
        return new Dictionary<string, DiagnosticCategory>
        {
            ["restart_shutdown"] = BuildCategory(
                "Restart and shutdown history",
                allEvents.Where(IsRestartEvent).ToList(),
                maxEventsPerCategory),
            ["driver"] = BuildCategory(
                "Driver and device failures",
                allEvents.Where(IsDriverEvent).ToList(),
                maxEventsPerCategory),
            ["gpu"] = BuildCategory(
                "GPU and display failures",
                allEvents.Where(IsGpuEvent).ToList(),
                maxEventsPerCategory),
            ["hardware"] = BuildCategory(
                "WHEA and hardware failures",
                allEvents.Where(IsHardwareEvent).ToList(),
                maxEventsPerCategory),
            ["bsod"] = BuildCategory(
                "BSOD and crash failures",
                allEvents.Where(IsBsodEvent).ToList(),
                maxEventsPerCategory),
            ["storage"] = BuildCategory(
                "Storage and file system failures",
                allEvents.Where(IsStorageEvent).ToList(),
                maxEventsPerCategory),
            ["critical"] = BuildCategory(
                "Critical system and application events",
                allEvents.Where(IsCriticalEvent).ToList(),
                maxEventsPerCategory)
        };
    }

    private static DiagnosticCategory BuildCategory(string title, List<NativeEventRecord> matches, int maxEventsPerCategory)
    {
        return new DiagnosticCategory
        {
            Title = title,
            Count = matches.Count,
            Events = matches
                .OrderByDescending(evt => evt.Timestamp)
                .Take(maxEventsPerCategory)
                .Select(ToDiagnosticEvent)
                .ToList()
        };
    }

    private static DiagnosticEvent ToDiagnosticEvent(NativeEventRecord record)
    {
        return new DiagnosticEvent
        {
            TimeCreated = record.Timestamp == DateTime.MinValue
                ? string.Empty
                : record.Timestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture),
            Provider = record.Provider,
            Id = record.Id,
            Level = record.LevelDisplay,
            LogName = record.LogName,
            Message = record.Message
        };
    }

    private static bool IsRestartEvent(NativeEventRecord record)
    {
        return RestartIds.Contains(record.Id) ||
               ProviderContains(record, RestartProviders);
    }

    private static bool IsDriverEvent(NativeEventRecord record)
    {
        return ProviderContains(record, DriverProviders) ||
               DriverMessageRegex().IsMatch(record.Message);
    }

    private static bool IsGpuEvent(NativeEventRecord record)
    {
        return ProviderContains(record, GpuProviders) ||
               GpuMessageRegex().IsMatch(record.Message);
    }

    private static bool IsHardwareEvent(NativeEventRecord record)
    {
        return ProviderContains(record, HardwareProviders) ||
               HardwareMessageRegex().IsMatch(record.Message);
    }

    private static bool IsBsodEvent(NativeEventRecord record)
    {
        return ProviderContains(record, BsodProviders) ||
               BsodMessageRegex().IsMatch(record.Message);
    }

    private static bool IsStorageEvent(NativeEventRecord record)
    {
        return ProviderContains(record, StorageProviders) ||
               StorageMessageRegex().IsMatch(record.Message);
    }

    private static bool IsCriticalEvent(NativeEventRecord record)
    {
        return record.LevelValue is 1 or 2;
    }

    private static bool ProviderContains(NativeEventRecord record, IEnumerable<string> fragments)
    {
        return fragments.Any(fragment =>
            record.Provider.Contains(fragment, StringComparison.OrdinalIgnoreCase));
    }

    private static Dictionary<string, string> ParseKeyValueLines(string content)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in content.Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries))
        {
            var idx = line.IndexOf('=');
            if (idx <= 0)
            {
                continue;
            }

            var key = line[..idx].Trim();
            var value = line[(idx + 1)..].Trim();
            if (!string.IsNullOrWhiteSpace(key))
            {
                result[key] = value;
            }
        }

        return result;
    }

    private static List<string> ParseMultiValueLines(string content, string key)
    {
        return content
            .Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries)
            .Select(line =>
            {
                var idx = line.IndexOf('=');
                return idx <= 0
                    ? (Key: string.Empty, Value: string.Empty)
                    : (Key: line[..idx].Trim(), Value: line[(idx + 1)..].Trim());
            })
            .Where(pair => pair.Key.Equals(key, StringComparison.OrdinalIgnoreCase))
            .Select(pair => pair.Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string FormatWmiDateTime(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return string.Empty;
        }

        var trimmed = raw.Trim();
        if (trimmed.Length < 14)
        {
            return trimmed;
        }

        if (!DateTime.TryParseExact(
                trimmed[..14],
                "yyyyMMddHHmmss",
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeLocal,
                out var parsed))
        {
            return trimmed;
        }

        return parsed.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
    }

    private static double? ParseUptimeDays(string raw)
    {
        var formatted = FormatWmiDateTime(raw);
        if (!DateTime.TryParse(formatted, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal, out var lastBoot))
        {
            return null;
        }

        return Math.Round((DateTime.Now - lastBoot).TotalDays, 2);
    }

    private static double? ParseMemoryGb(List<string> capacities)
    {
        var values = capacities
            .Select(value => long.TryParse(value, out var parsed) ? parsed : 0L)
            .Where(value => value > 0)
            .ToArray();

        if (values.Length == 0)
        {
            return null;
        }

        return Math.Round(values.Sum() / 1024d / 1024d / 1024d, 2);
    }

    private static List<DiskInfo> ParseDiskCsv(string csv)
    {
        var lines = csv.Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length <= 1)
        {
            return [];
        }

        var disks = new List<DiskInfo>();
        foreach (var line in lines.Skip(1))
        {
            var parts = line.Split(',');
            if (parts.Length < 5)
            {
                continue;
            }

            disks.Add(new DiskInfo
            {
                DeviceId = parts[1].Trim(),
                FreeGb = ParseBytesToGb(parts[2]),
                FileSystem = parts[3].Trim(),
                SizeGb = ParseBytesToGb(parts[4])
            });
        }

        return disks;
    }

    private static double? ParseBytesToGb(string raw)
    {
        return long.TryParse(raw.Trim(), out var bytes)
            ? Math.Round(bytes / 1024d / 1024d / 1024d, 2)
            : null;
    }

    private static List<NativeEventRecord> ParseWevtutilXml(string xml, string fallbackLogName)
    {
        if (string.IsNullOrWhiteSpace(xml))
        {
            return [];
        }

        var document = XDocument.Parse(xml);
        XNamespace eventNs = "http://schemas.microsoft.com/win/2004/08/events/event";

        return document
            .Descendants(eventNs + "Event")
            .Select(evt => ParseEvent(evt, eventNs, fallbackLogName))
            .Where(evt => evt is not null)
            .Cast<NativeEventRecord>()
            .ToList();
    }

    private static NativeEventRecord? ParseEvent(XElement element, XNamespace eventNs, string fallbackLogName)
    {
        var system = element.Element(eventNs + "System");
        if (system is null)
        {
            return null;
        }

        var provider = system.Element(eventNs + "Provider")?.Attribute("Name")?.Value ?? string.Empty;
        var eventIdText = system.Element(eventNs + "EventID")?.Value ?? "0";
        var levelValueText = system.Element(eventNs + "Level")?.Value ?? "0";
        var logName = system.Element(eventNs + "Channel")?.Value ?? fallbackLogName;
        var timeCreated = system.Element(eventNs + "TimeCreated")?.Attribute("SystemTime")?.Value ?? string.Empty;

        var renderingInfo = element.Element(eventNs + "RenderingInfo");
        var message = renderingInfo?.Element(eventNs + "Message")?.Value ?? string.Empty;
        var levelDisplay = renderingInfo?.Element(eventNs + "Level")?.Value ?? levelValueText;

        return new NativeEventRecord
        {
            Provider = provider,
            Id = int.TryParse(eventIdText, out var id) ? id : 0,
            LevelValue = int.TryParse(levelValueText, out var levelValue) ? levelValue : 0,
            LevelDisplay = string.IsNullOrWhiteSpace(levelDisplay) ? levelValueText : levelDisplay,
            LogName = logName,
            Message = NormalizeMessage(message),
            Timestamp = DateTime.TryParse(
                timeCreated,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed)
                ? parsed
                : DateTime.MinValue
        };
    }

    private static string NormalizeMessage(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return "Message unavailable.";
        }

        var compact = WhitespaceRegex().Replace(message, " ").Trim();
        return compact.Length > 400 ? $"{compact[..400]}..." : compact;
    }

    [GeneratedRegex(@"(?i)(driver|device).*(failed|failure|not started|problem|unable|could not|did not load)")]
    private static partial Regex DriverMessageRegex();

    [GeneratedRegex(@"(?i)(TDR|timeout|display driver|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)")]
    private static partial Regex GpuMessageRegex();

    [GeneratedRegex(@"(?i)(PCI Express|PCIe|corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)")]
    private static partial Regex HardwareMessageRegex();

    [GeneratedRegex(@"(?i)(bugcheck|blue screen|stop code|LiveKernelEvent|dump)")]
    private static partial Regex BsodMessageRegex();

    [GeneratedRegex(@"(?i)(bad block|file system|corrupt|corruption|volume|storage|disk)")]
    private static partial Regex StorageMessageRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    private sealed class NativeEventRecord
    {
        public DateTime Timestamp { get; init; }
        public string Provider { get; init; } = string.Empty;
        public int Id { get; init; }
        public int LevelValue { get; init; }
        public string LevelDisplay { get; init; } = string.Empty;
        public string LogName { get; init; } = string.Empty;
        public string Message { get; init; } = string.Empty;
    }
}
