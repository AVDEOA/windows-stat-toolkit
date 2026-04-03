namespace WindowsStatToolkit.Desktop.Models;

public sealed class MonitoringSettings
{
    public bool Enabled { get; set; }
    public int IntervalSeconds { get; set; } = 180;
}
