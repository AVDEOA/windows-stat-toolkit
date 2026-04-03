using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Interfaces;

public interface IRemoteDiagnosticsTransport
{
    Task<bool> PingHostAsync(HostDefinition host);
    Task<TransportProbeResult> TestConnectivityAsync(HostDefinition host, CancellationToken cancellationToken);
    Task<DiagnosticSnapshot> CollectSnapshotAsync(HostDefinition host, DiagnosticQuery query, CancellationToken cancellationToken);
}
