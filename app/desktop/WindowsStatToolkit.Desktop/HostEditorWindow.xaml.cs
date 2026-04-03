using System.Windows;
using WindowsStatToolkit.Desktop.Models;
using WindowsStatToolkit.Desktop.Services;

namespace WindowsStatToolkit.Desktop;

public partial class HostEditorWindow : Window
{
    private readonly Guid? _existingId;
    private readonly Func<HostDefinition, CancellationToken, Task<TransportProbeResult>>? _testConnectionAsync;

    public HostDefinition? Result { get; private set; }

    public HostEditorWindow(
        HostDefinition? existing = null,
        Func<HostDefinition, CancellationToken, Task<TransportProbeResult>>? testConnectionAsync = null)
    {
        InitializeComponent();
        _existingId = existing?.Id;
        _testConnectionAsync = testConnectionAsync;

        if (existing is not null)
        {
            Title = $"Edit PC: {existing.Name}";
            NameTextBox.Text = existing.Name;
            AddressTextBox.Text = existing.Address;
            UserTextBox.Text = existing.UserName;
            PasswordTextBox.Password = SecretProtector.Unprotect(existing.PasswordProtected);
            SelectTransportMode(existing.TransportMode);
            PortTextBox.Text = existing.Port.ToString();
            KeyPathTextBox.Text = existing.KeyPath;
            KnownFingerprintTextBox.Text = existing.KnownHostFingerprint;
            ShellTextBox.Text = existing.Shell;
            TagsTextBox.Text = existing.Tags;
            NotesTextBox.Text = existing.Notes;
            DiskThresholdTextBox.Text = existing.DiskFreeThresholdGb.ToString();
            PingFailuresTextBox.Text = existing.PingFailuresBeforeAlert.ToString();
            MonitoringEnabledCheckBox.IsChecked = existing.MonitoringEnabled;
        }
        else
        {
            SelectTransportMode("auto");
        }

        SaveButton.Click += (_, _) => SaveAndClose();
        TestButton.Click += async (_, _) => await TestConnectionAsync();
        CancelButton.Click += (_, _) => Close();

        if (_testConnectionAsync is null)
        {
            TestButton.IsEnabled = false;
        }
    }

    private void SaveAndClose()
    {
        if (string.IsNullOrWhiteSpace(NameTextBox.Text) ||
            string.IsNullOrWhiteSpace(AddressTextBox.Text) ||
            string.IsNullOrWhiteSpace(UserTextBox.Text))
        {
            MessageBox.Show("Name, address, and SSH user are required.", "Windows Stat Toolkit", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Result = new HostDefinition
        {
            Id = _existingId ?? Guid.NewGuid(),
            Name = NameTextBox.Text.Trim(),
            Address = AddressTextBox.Text.Trim(),
            TransportMode = ((TransportModeComboBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Tag as string) ?? "auto",
            UserName = UserTextBox.Text.Trim(),
            PasswordProtected = SecretProtector.Protect(PasswordTextBox.Password),
            KnownHostFingerprint = KnownFingerprintTextBox.Text.Trim(),
            Port = ParsePositiveInt(PortTextBox.Text, 22),
            KeyPath = KeyPathTextBox.Text.Trim(),
            Shell = string.IsNullOrWhiteSpace(ShellTextBox.Text) ? "powershell.exe" : ShellTextBox.Text.Trim(),
            Tags = TagsTextBox.Text.Trim(),
            Notes = NotesTextBox.Text.Trim(),
            MonitoringEnabled = MonitoringEnabledCheckBox.IsChecked == true,
            DiskFreeThresholdGb = ParsePositiveInt(DiskThresholdTextBox.Text, 10),
            PingFailuresBeforeAlert = ParsePositiveInt(PingFailuresTextBox.Text, 3)
        };

        DialogResult = true;
        Close();
    }

    private async Task TestConnectionAsync()
    {
        if (_testConnectionAsync is null)
        {
            return;
        }

        try
        {
            var model = BuildDraftModel();
            TestButton.IsEnabled = false;
            var result = await _testConnectionAsync(model, CancellationToken.None);
            KnownFingerprintTextBox.Text = model.KnownHostFingerprint;
            MessageBox.Show(
                $"{result.Summary}{Environment.NewLine}Remote host: {result.RemoteIdentity}{Environment.NewLine}Transport: {result.TransportName}",
                "Windows Stat Toolkit",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Windows Stat Toolkit", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            TestButton.IsEnabled = true;
        }
    }

    private HostDefinition BuildDraftModel()
    {
        return new HostDefinition
        {
            Id = _existingId ?? Guid.NewGuid(),
            Name = NameTextBox.Text.Trim(),
            Address = AddressTextBox.Text.Trim(),
            TransportMode = ((TransportModeComboBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Tag as string) ?? "auto",
            UserName = UserTextBox.Text.Trim(),
            PasswordProtected = SecretProtector.Protect(PasswordTextBox.Password),
            KnownHostFingerprint = KnownFingerprintTextBox.Text.Trim(),
            Port = ParsePositiveInt(PortTextBox.Text, 22),
            KeyPath = KeyPathTextBox.Text.Trim(),
            Shell = string.IsNullOrWhiteSpace(ShellTextBox.Text) ? "powershell.exe" : ShellTextBox.Text.Trim(),
            Tags = TagsTextBox.Text.Trim(),
            Notes = NotesTextBox.Text.Trim(),
            MonitoringEnabled = MonitoringEnabledCheckBox.IsChecked == true,
            DiskFreeThresholdGb = ParsePositiveInt(DiskThresholdTextBox.Text, 10),
            PingFailuresBeforeAlert = ParsePositiveInt(PingFailuresTextBox.Text, 3)
        };
    }

    private void SelectTransportMode(string? mode)
    {
        var normalized = string.IsNullOrWhiteSpace(mode) ? "auto" : mode.Trim().ToLowerInvariant();
        foreach (var item in TransportModeComboBox.Items.OfType<System.Windows.Controls.ComboBoxItem>())
        {
            if (string.Equals(item.Tag as string, normalized, StringComparison.OrdinalIgnoreCase))
            {
                TransportModeComboBox.SelectedItem = item;
                return;
            }
        }

        TransportModeComboBox.SelectedIndex = 0;
    }

    private static int ParsePositiveInt(string text, int fallback)
    {
        return int.TryParse(text, out var value) && value > 0 ? value : fallback;
    }
}
