namespace WindowsStatToolkit.Desktop.Models;

public sealed class HostDefinition
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string TransportMode { get; set; } = "auto";
    public string UserName { get; set; } = string.Empty;
    public int Port { get; set; } = 22;
    public string KeyPath { get; set; } = string.Empty;
    public string Shell { get; set; } = "powershell.exe";
    public string Tags { get; set; } = string.Empty;
    public string Notes { get; set; } = string.Empty;
    public bool MonitoringEnabled { get; set; } = true;
    public int DiskFreeThresholdGb { get; set; } = 10;
    public int PingFailuresBeforeAlert { get; set; } = 3;
}
