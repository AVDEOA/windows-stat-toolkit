using System.Text.Json.Serialization;

namespace WindowsStatToolkit.Desktop.Models;

public sealed class DiagnosticSnapshot
{
    [JsonPropertyName("generated_at")]
    public string GeneratedAt { get; set; } = string.Empty;

    [JsonPropertyName("period_label")]
    public string PeriodLabel { get; set; } = string.Empty;

    [JsonPropertyName("period_days")]
    public int? PeriodDays { get; set; }

    [JsonPropertyName("start_time")]
    public string StartTime { get; set; } = string.Empty;

    [JsonPropertyName("collector")]
    public CollectorMetadata Collector { get; set; } = new();

    [JsonPropertyName("host")]
    public HostInventory Host { get; set; } = new();

    [JsonPropertyName("categories")]
    public Dictionary<string, DiagnosticCategory> Categories { get; set; } = [];
}

public sealed class CollectorMetadata
{
    [JsonPropertyName("requested_mode")]
    public string RequestedMode { get; set; } = string.Empty;

    [JsonPropertyName("transport_name")]
    public string TransportName { get; set; } = string.Empty;

    [JsonPropertyName("fallback_used")]
    public bool FallbackUsed { get; set; }

    [JsonPropertyName("warnings")]
    public List<string> Warnings { get; set; } = [];
}

public sealed class HostInventory
{
    [JsonPropertyName("computer_name")]
    public string ComputerName { get; set; } = string.Empty;

    [JsonPropertyName("os_caption")]
    public string OsCaption { get; set; } = string.Empty;

    [JsonPropertyName("os_version")]
    public string OsVersion { get; set; } = string.Empty;

    [JsonPropertyName("last_boot")]
    public string LastBoot { get; set; } = string.Empty;

    [JsonPropertyName("uptime_days")]
    public double? UptimeDays { get; set; }

    [JsonPropertyName("bios_version")]
    public string BiosVersion { get; set; } = string.Empty;

    [JsonPropertyName("cpu")]
    public List<string> Cpu { get; set; } = [];

    [JsonPropertyName("gpus")]
    public List<string> Gpus { get; set; } = [];

    [JsonPropertyName("memory_gb")]
    public double? MemoryGb { get; set; }

    [JsonPropertyName("disks")]
    public List<DiskInfo> Disks { get; set; } = [];
}

public sealed class DiskInfo
{
    [JsonPropertyName("device_id")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("size_gb")]
    public double? SizeGb { get; set; }

    [JsonPropertyName("free_gb")]
    public double? FreeGb { get; set; }

    [JsonPropertyName("file_system")]
    public string FileSystem { get; set; } = string.Empty;
}

public sealed class DiagnosticCategory
{
    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("count")]
    public int Count { get; set; }

    [JsonPropertyName("events")]
    public List<DiagnosticEvent> Events { get; set; } = [];
}

public sealed class DiagnosticEvent
{
    [JsonPropertyName("time_created")]
    public string TimeCreated { get; set; } = string.Empty;

    [JsonPropertyName("provider")]
    public string Provider { get; set; } = string.Empty;

    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("level")]
    public string Level { get; set; } = string.Empty;

    [JsonPropertyName("log_name")]
    public string LogName { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}
