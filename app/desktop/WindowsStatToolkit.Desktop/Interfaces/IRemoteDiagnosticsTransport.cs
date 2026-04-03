using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Interfaces;

public interface IRemoteDiagnosticsTransport
{
    Task<bool> PingHostAsync(HostDefinition host);
    Task<DiagnosticSnapshot> CollectSnapshotAsync(HostDefinition host, DiagnosticQuery query, CancellationToken cancellationToken);
}
