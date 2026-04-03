namespace WindowsStatToolkit.Desktop.Models;

public sealed class AppState
{
    public List<HostDefinition> Hosts { get; set; } = [];
    public TelegramSettings Telegram { get; set; } = new();
    public MonitoringSettings Monitoring { get; set; } = new();
}
