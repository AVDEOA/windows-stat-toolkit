using WindowsStatToolkit.Desktop.Interfaces;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class DiagnosticsTransportRouter(
    SshNativeDiagnosticsTransport nativeTransport,
    SshPowerShellDiagnosticsTransport powerShellTransport) : IRemoteDiagnosticsTransport
{
    public async Task<bool> PingHostAsync(HostDefinition host)
    {
        return await nativeTransport.PingHostAsync(host);
    }

    public async Task<DiagnosticSnapshot> CollectSnapshotAsync(
        HostDefinition host,
        DiagnosticQuery query,
        CancellationToken cancellationToken)
    {
        var requestedMode = NormalizeMode(host.TransportMode);

        if (requestedMode == "ssh_native")
        {
            var nativeSnapshot = await nativeTransport.CollectSnapshotAsync(host, query, cancellationToken);
            nativeSnapshot.Collector.RequestedMode = requestedMode;
            return nativeSnapshot;
        }

        if (requestedMode == "ssh_powershell")
        {
            var psSnapshot = await powerShellTransport.CollectSnapshotAsync(host, query, cancellationToken);
            psSnapshot.Collector.RequestedMode = requestedMode;
            return psSnapshot;
        }

        try
        {
            var nativeSnapshot = await nativeTransport.CollectSnapshotAsync(host, query, cancellationToken);
            nativeSnapshot.Collector.RequestedMode = requestedMode;
            return nativeSnapshot;
        }
        catch (Exception ex)
        {
            var psSnapshot = await powerShellTransport.CollectSnapshotAsync(host, query, cancellationToken);
            psSnapshot.Collector.RequestedMode = requestedMode;
            psSnapshot.Collector.FallbackUsed = true;
            psSnapshot.Collector.Warnings.Add(
                $"Native SSH collector failed and PowerShell fallback was used: {ex.Message}");
            return psSnapshot;
        }
    }

    private static string NormalizeMode(string? mode)
    {
        return mode?.Trim().ToLowerInvariant() switch
        {
            "ssh_native" => "ssh_native",
            "ssh_powershell" => "ssh_powershell",
            _ => "auto"
        };
    }
}
