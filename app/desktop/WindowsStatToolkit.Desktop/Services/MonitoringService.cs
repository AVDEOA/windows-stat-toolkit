using System.Collections.Concurrent;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class MonitoringService(
    DiagnosticsOrchestrator diagnosticsOrchestrator,
    TelegramAlertService telegramAlertService)
{
    private readonly ConcurrentDictionary<Guid, int> _pingFailures = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastCategoryAlert = new();
    private readonly ConcurrentDictionary<string, bool> _diskAlertState = new();
    private CancellationTokenSource? _cts;
    private Task? _loopTask;

    public event Action<string>? Log;

    public bool IsRunning => _loopTask is { IsCompleted: false };

    public void Start(AppState state)
    {
        Stop();
        _cts = new CancellationTokenSource();
        _loopTask = RunLoopAsync(state, _cts.Token);
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;
    }

    private async Task RunLoopAsync(AppState state, CancellationToken cancellationToken)
    {
        Log?.Invoke("Monitoring loop started.");
        var interval = TimeSpan.FromSeconds(Math.Max(30, state.Monitoring.IntervalSeconds));
        using var timer = new PeriodicTimer(interval);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await MonitorAllHostsAsync(state, cancellationToken);
            }
            catch (Exception ex)
            {
                Log?.Invoke($"Monitoring error: {ex.Message}");
            }

            if (!await timer.WaitForNextTickAsync(cancellationToken))
            {
                break;
            }
        }

        Log?.Invoke("Monitoring loop stopped.");
    }

    private async Task MonitorAllHostsAsync(AppState state, CancellationToken cancellationToken)
    {
        if (!state.Monitoring.Enabled || !state.Telegram.Enabled)
        {
            return;
        }

        foreach (var host in state.Hosts.Where(h => h.MonitoringEnabled))
        {
            await MonitorHostAsync(state.Telegram, host, cancellationToken);
        }
    }

    private async Task MonitorHostAsync(TelegramSettings telegram, HostDefinition host, CancellationToken cancellationToken)
    {
        var pingOk = await diagnosticsOrchestrator.PingHostAsync(host);
        if (!pingOk)
        {
            var failures = _pingFailures.AddOrUpdate(host.Id, 1, (_, current) => current + 1);
            Log?.Invoke($"Ping failed for {host.Name}. Failure count: {failures}");

            if (failures >= host.PingFailuresBeforeAlert)
            {
                await telegramAlertService.SendAsync(
                    telegram,
                    $"[Windows Stat Toolkit] Host {host.Name} ({host.Address}) looks offline. Ping failures: {failures}.",
                    cancellationToken);
            }

            return;
        }

        _pingFailures[host.Id] = 0;
        var snapshot = await diagnosticsOrchestrator.CollectSnapshotAsync(host, 3, 25, cancellationToken);
        await CheckDiskAlertsAsync(telegram, host, snapshot, cancellationToken);
        await CheckCriticalAlertsAsync(telegram, host, snapshot, cancellationToken);
    }

    private async Task CheckDiskAlertsAsync(TelegramSettings telegram, HostDefinition host, DiagnosticSnapshot snapshot, CancellationToken cancellationToken)
    {
        foreach (var disk in snapshot.Host.Disks)
        {
            if (!disk.FreeGb.HasValue)
            {
                continue;
            }

            var key = $"{host.Id}:disk:{disk.DeviceId}";
            var isLow = disk.FreeGb.Value <= host.DiskFreeThresholdGb;
            _diskAlertState.TryGetValue(key, out var wasLow);

            if (isLow && !wasLow)
            {
                _diskAlertState[key] = true;
                await telegramAlertService.SendAsync(
                    telegram,
                    $"[Windows Stat Toolkit] Low disk space on {host.Name} {disk.DeviceId}: {disk.FreeGb:0.##} GB free.",
                    cancellationToken);
            }
            else if (!isLow)
            {
                _diskAlertState[key] = false;
            }
        }
    }

    private async Task CheckCriticalAlertsAsync(TelegramSettings telegram, HostDefinition host, DiagnosticSnapshot snapshot, CancellationToken cancellationToken)
    {
        foreach (var key in new[] { "critical", "hardware", "bsod", "storage", "gpu" })
        {
            if (!snapshot.Categories.TryGetValue(key, out var category) || category.Events.Count == 0)
            {
                continue;
            }

            var latest = category.Events
                .Select(e => DateTime.TryParse(e.TimeCreated, out var parsed) ? parsed : DateTime.MinValue)
                .Max();

            if (latest == DateTime.MinValue)
            {
                continue;
            }

            var stateKey = $"{host.Id}:{key}";
            if (_lastCategoryAlert.TryGetValue(stateKey, out var previous) && latest <= previous)
            {
                continue;
            }

            _lastCategoryAlert[stateKey] = latest;
            var topEvent = category.Events.First();
            await telegramAlertService.SendAsync(
                telegram,
                $"[Windows Stat Toolkit] {host.Name}: new {category.Title}. {topEvent.Provider} / ID {topEvent.Id} / {topEvent.Message}",
                cancellationToken);
        }
    }
}
