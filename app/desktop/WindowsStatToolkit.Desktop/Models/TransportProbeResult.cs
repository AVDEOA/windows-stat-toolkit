namespace WindowsStatToolkit.Desktop.Models;

public sealed class TransportProbeResult
{
    public string TransportName { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    public string RemoteIdentity { get; set; } = string.Empty;
    public bool FallbackUsed { get; set; }
}
