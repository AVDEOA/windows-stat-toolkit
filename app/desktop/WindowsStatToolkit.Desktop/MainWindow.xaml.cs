using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Windows;
using WindowsStatToolkit.Desktop.Models;
using WindowsStatToolkit.Desktop.Services;

namespace WindowsStatToolkit.Desktop;

public partial class MainWindow : Window
{
    private readonly AppStateService _stateService = new();
    private readonly SshPowerShellDiagnosticsTransport _transport = new();
    private readonly DiagnosticsOrchestrator _diagnosticsOrchestrator;
    private readonly TelegramAlertService _telegramAlertService = new(new HttpClient());
    private readonly MonitoringService _monitoringService;
    private AppState _state = new();
    private readonly ObservableCollection<HostDefinition> _hosts = [];

    public MainWindow()
    {
        InitializeComponent();
        _diagnosticsOrchestrator = new DiagnosticsOrchestrator(_transport);
        _monitoringService = new MonitoringService(_diagnosticsOrchestrator, _telegramAlertService);
        _monitoringService.Log += AppendLog;
        HostsGrid.ItemsSource = _hosts;
        RangeComboBox.ItemsSource = new[]
        {
            new TimeRangeOption("3 days", 3),
            new TimeRangeOption("7 days", 7),
            new TimeRangeOption("14 days", 14),
            new TimeRangeOption("30 days", 30),
            new TimeRangeOption("All time", null)
        };
        RangeComboBox.SelectedIndex = 1;
        ApplyBlockButtonTitles();

        Loaded += MainWindow_Loaded;
        Closing += (_, _) => _monitoringService.Stop();
        HostsGrid.MouseDoubleClick += async (_, _) => await EditSelectedHostAsync();
        NewHostButton.Click += async (_, _) => await CreateNewHostAsync();
        EditHostButton.Click += async (_, _) => await EditSelectedHostAsync();
        DeleteHostButton.Click += async (_, _) => await DeleteHostAsync();
        RefreshHostsButton.Click += (_, _) => RefreshHostsGrid();
        SaveSettingsButton.Click += async (_, _) => await SaveSettingsAsync();
        StartMonitoringButton.Click += async (_, _) => await StartMonitoringAsync();
        StopMonitoringButton.Click += (_, _) => StopMonitoring();
        OpenReportsFolderButton.Click += (_, _) => Process.Start("explorer.exe", _stateService.ReportsRoot);

        AiBundleButton.Click += async (_, _) => await RunReportAsync("ai");
        AnalyzeAiButton.Click += async (_, _) => await RunReportAsync("analyze-ai");
        PcReportButton.Click += async (_, _) => await RunReportAsync("pc");
        Block1Button.Click += async (_, _) => await RunReportAsync("block1");
        Block2Button.Click += async (_, _) => await RunReportAsync("block2");
        Block3Button.Click += async (_, _) => await RunReportAsync("block3");
        Block4Button.Click += async (_, _) => await RunReportAsync("block4");
        Block5Button.Click += async (_, _) => await RunReportAsync("block5");
        Block6Button.Click += async (_, _) => await RunReportAsync("block6");
        Block7Button.Click += async (_, _) => await RunReportAsync("block7");
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        _state = await _stateService.LoadAsync();
        ApplySettingsToUi();
        RefreshHostsGrid();
        StatusText.Text = "Ready. Add a PC with New, then generate reports.";
        AppendLog("Application loaded.");
    }

    private void ApplySettingsToUi()
    {
        BotTokenTextBox.Text = _state.Telegram.BotToken;
        ChatIdTextBox.Text = _state.Telegram.ChatId;
        TelegramEnabledCheckBox.IsChecked = _state.Telegram.Enabled;
        MonitoringMasterCheckBox.IsChecked = _state.Monitoring.Enabled;
        MonitorIntervalTextBox.Text = _state.Monitoring.IntervalSeconds.ToString();
    }

    private void RefreshHostsGrid()
    {
        _hosts.Clear();
        foreach (var host in _state.Hosts.OrderBy(h => h.Name))
        {
            _hosts.Add(host);
        }
    }

    private async Task CreateNewHostAsync()
    {
        var editor = new HostEditorWindow
        {
            Owner = this
        };

        if (editor.ShowDialog() == true && editor.Result is not null)
        {
            await UpsertHostAsync(editor.Result);
        }
    }

    private async Task EditSelectedHostAsync()
    {
        var selected = GetSelectedHost();
        var editor = new HostEditorWindow(selected)
        {
            Owner = this
        };

        if (editor.ShowDialog() == true && editor.Result is not null)
        {
            await UpsertHostAsync(editor.Result);
        }
    }

    private async Task UpsertHostAsync(HostDefinition model)
    {
        try
        {
            var existing = _state.Hosts.FirstOrDefault(h => h.Id == model.Id);
            if (existing is null)
            {
                _state.Hosts.Add(model);
            }
            else
            {
                var index = _state.Hosts.IndexOf(existing);
                _state.Hosts[index] = model;
            }

            await _stateService.SaveAsync(_state);
            RefreshHostsGrid();
            StatusText.Text = $"Host saved: {model.Name}";
            AppendLog($"Saved host {model.Name}.");
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
        }
    }

    private async Task DeleteHostAsync()
    {
        var host = GetSelectedHost();

        _state.Hosts.Remove(host);
        await _stateService.SaveAsync(_state);
        RefreshHostsGrid();
        StatusText.Text = $"Host deleted: {host.Name}";
        AppendLog($"Deleted host {host.Name}.");
    }

    private async Task SaveSettingsAsync()
    {
        _state.Telegram.BotToken = BotTokenTextBox.Text.Trim();
        _state.Telegram.ChatId = ChatIdTextBox.Text.Trim();
        _state.Telegram.Enabled = TelegramEnabledCheckBox.IsChecked == true;
        _state.Monitoring.Enabled = MonitoringMasterCheckBox.IsChecked == true;
        _state.Monitoring.IntervalSeconds = ParsePositiveInt(MonitorIntervalTextBox.Text, 180);
        await _stateService.SaveAsync(_state);
        StatusText.Text = "Settings saved.";
        AppendLog("Saved Telegram and monitoring settings.");
    }

    private async Task StartMonitoringAsync()
    {
        await SaveSettingsAsync();
        _monitoringService.Start(_state);
        StatusText.Text = "Monitoring loop started.";
    }

    private void StopMonitoring()
    {
        _monitoringService.Stop();
        StatusText.Text = "Monitoring loop stopped.";
    }

    private async Task RunReportAsync(string mode)
    {
        try
        {
            var host = GetSelectedHost();
            var range = GetSelectedRange();
            StatusText.Text = $"Collecting diagnostics from {host.Name}...";
            AppendLog($"Collecting snapshot from {host.Name}. Mode: {mode}. Range: {range.Label}.");

            var report = await _diagnosticsOrchestrator.GenerateReportAsync(host, range.Days, mode, CancellationToken.None);
            var path = await _stateService.SaveReportAsync(host.Name, report.Suffix, report.Extension, report.Content);
            PreviewTextBox.Text = report.Content;
            StatusText.Text = $"Saved report: {Path.GetFileName(path)}";
            AppendLog($"Report saved to {path}");
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
        }
    }

    private HostDefinition GetSelectedHost()
    {
        if (HostsGrid.SelectedItem is HostDefinition selected)
        {
            return selected;
        }

        throw new InvalidOperationException("Select a host first.");
    }

    private TimeRangeOption GetSelectedRange()
    {
        return RangeComboBox.SelectedItem as TimeRangeOption
            ?? throw new InvalidOperationException("Select a collection range.");
    }

    private static int ParsePositiveInt(string text, int fallback)
    {
        return int.TryParse(text, out var value) && value > 0 ? value : fallback;
    }

    private void ApplyBlockButtonTitles()
    {
        var blocks = DiagnosticBlockCatalog.GetBlocks();
        Block1Button.Content = blocks[0].ShortTitle;
        Block2Button.Content = blocks[1].ShortTitle;
        Block3Button.Content = blocks[2].ShortTitle;
        Block4Button.Content = blocks[3].ShortTitle;
        Block5Button.Content = blocks[4].ShortTitle;
        Block6Button.Content = blocks[5].ShortTitle;
        Block7Button.Content = blocks[6].ShortTitle;
    }

    private void AppendLog(string message)
    {
        Dispatcher.Invoke(() =>
        {
            LogTextBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
            LogTextBox.ScrollToEnd();
        });
    }

    private void ShowError(string message)
    {
        StatusText.Text = $"Error: {message}";
        AppendLog($"Error: {message}");
        MessageBox.Show(message, "Windows Stat Toolkit", MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
