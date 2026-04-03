using System.Windows;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop;

public partial class HostEditorWindow : Window
{
    private readonly Guid? _existingId;

    public HostDefinition? Result { get; private set; }

    public HostEditorWindow(HostDefinition? existing = null)
    {
        InitializeComponent();
        _existingId = existing?.Id;

        if (existing is not null)
        {
            Title = $"Edit PC: {existing.Name}";
            NameTextBox.Text = existing.Name;
            AddressTextBox.Text = existing.Address;
            UserTextBox.Text = existing.UserName;
            PortTextBox.Text = existing.Port.ToString();
            KeyPathTextBox.Text = existing.KeyPath;
            ShellTextBox.Text = existing.Shell;
            TagsTextBox.Text = existing.Tags;
            NotesTextBox.Text = existing.Notes;
            DiskThresholdTextBox.Text = existing.DiskFreeThresholdGb.ToString();
            PingFailuresTextBox.Text = existing.PingFailuresBeforeAlert.ToString();
            MonitoringEnabledCheckBox.IsChecked = existing.MonitoringEnabled;
        }

        SaveButton.Click += (_, _) => SaveAndClose();
        CancelButton.Click += (_, _) => Close();
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
            UserName = UserTextBox.Text.Trim(),
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

    private static int ParsePositiveInt(string text, int fallback)
    {
        return int.TryParse(text, out var value) && value > 0 ? value : fallback;
    }
}
