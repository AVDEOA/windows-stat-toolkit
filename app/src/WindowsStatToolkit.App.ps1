Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

. "$PSScriptRoot\WindowsStatToolkit.AppModel.ps1"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Stat Toolkit"
        Width="1240"
        Height="860"
        MinWidth="1080"
        MinHeight="760"
        WindowStartupLocation="CenterScreen"
        Background="#F4F1E8">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto" />
      <RowDefinition Height="*" />
      <RowDefinition Height="210" />
    </Grid.RowDefinitions>

    <Border Background="#193549" CornerRadius="16" Padding="22" Margin="0,0,0,16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="250" />
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="Windows Stat Toolkit" FontSize="28" FontWeight="Bold" Foreground="#FFF8EC" />
          <TextBlock Text="GUI for local collection, analysis, and remote PC diagnostics" Margin="0,8,0,0" FontSize="15" Foreground="#DCE7EE" />
        </StackPanel>
        <Border Grid.Column="1" Background="#254F6A" CornerRadius="12" Padding="14">
          <StackPanel>
            <TextBlock Text="Current status" FontWeight="Bold" Foreground="#FFF8EC" />
            <TextBlock x:Name="StatusText" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#DCE7EE" />
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Background="#FFFDF8" BorderBrush="#C6B89E">
      <TabItem Header="Overview">
        <Grid Margin="16">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.1*" />
            <ColumnDefinition Width="1.2*" />
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
          </Grid.RowDefinitions>

          <WrapPanel Margin="0,0,0,12">
            <Button x:Name="RefreshOverviewButton" Content="Refresh overview" Margin="0,0,10,10" Padding="14,8" Background="#B64D32" Foreground="White" BorderThickness="0" />
            <Button x:Name="OpenOutputRootButton" Content="Open C:\Stat" Margin="0,0,10,10" Padding="14,8" Background="#3B6B53" Foreground="White" BorderThickness="0" />
            <Button x:Name="RefreshReportsButton" Content="Refresh reports" Margin="0,0,10,10" Padding="14,8" Background="#7E5C35" Foreground="White" BorderThickness="0" />
          </WrapPanel>

          <Border Grid.Row="1" Grid.Column="0" Background="#F7F2E6" CornerRadius="12" Padding="16" Margin="0,0,10,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Text="Local machine" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <TextBlock Grid.Row="1" x:Name="OverviewComputer" Margin="0,12,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="2" x:Name="OverviewOs" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="3" x:Name="OverviewBoot" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="4" x:Name="OverviewCpu" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="5" x:Name="OverviewGpu" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="6" x:Name="OverviewMemory" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="7" x:Name="OverviewDisks" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="8" x:Name="OverviewOutput" Margin="0,8,0,0" TextWrapping="Wrap" />
              <TextBlock Grid.Row="9" x:Name="OverviewReports" Margin="0,8,0,0" TextWrapping="Wrap" />
            </Grid>
          </Border>

          <Border Grid.Row="1" Grid.Column="1" Background="#FDF9F0" CornerRadius="12" Padding="16" Margin="10,0,0,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
              </Grid.RowDefinitions>
              <TextBlock Text="Recent reports" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <DataGrid x:Name="ReportsGrid"
                        Grid.Row="1"
                        Margin="0,12,0,0"
                        AutoGenerateColumns="False"
                        IsReadOnly="True"
                        HeadersVisibility="Column"
                        SelectionMode="Single"
                        GridLinesVisibility="Horizontal">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*" />
                  <DataGridTextColumn Header="Updated" Binding="{Binding LastWriteTime}" Width="170" />
                  <DataGridTextColumn Header="KB" Binding="{Binding SizeKb}" Width="80" />
                  <DataGridTextColumn Header="Path" Binding="{Binding Path}" Width="260" />
                </DataGrid.Columns>
              </DataGrid>
            </Grid>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="Local diagnostics">
        <Grid Margin="16">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.2*" />
            <ColumnDefinition Width="1*" />
          </Grid.ColumnDefinitions>
          <Border Background="#F7F2E6" CornerRadius="12" Padding="16" Margin="0,0,10,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <TextBlock Text="Diagnostic actions" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <DataGrid x:Name="ActionsGrid"
                        Grid.Row="1"
                        Margin="0,12,0,12"
                        AutoGenerateColumns="False"
                        IsReadOnly="True"
                        SelectionMode="Single">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="Action" Binding="{Binding Title}" Width="160" />
                  <DataGridTextColumn Header="Description" Binding="{Binding Description}" Width="*" />
                </DataGrid.Columns>
              </DataGrid>
              <Button x:Name="RunActionButton" Grid.Row="2" Content="Run selected action" Padding="14,8" Background="#B64D32" Foreground="White" BorderThickness="0" HorizontalAlignment="Left" />
            </Grid>
          </Border>
          <Border Grid.Column="1" Background="#FDF9F0" CornerRadius="12" Padding="16" Margin="10,0,0,0">
            <StackPanel>
              <TextBlock Text="Analyzer and shortcuts" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <TextBlock Text="AnalizeV9" Margin="0,18,0,6" FontWeight="Bold" />
              <ComboBox x:Name="AnalysisRangeCombo" SelectedIndex="1">
                <ComboBoxItem Content="2 days" />
                <ComboBoxItem Content="7 days" />
                <ComboBoxItem Content="14 days" />
                <ComboBoxItem Content="30 days" />
                <ComboBoxItem Content="All time" />
              </ComboBox>
              <Button x:Name="RunAnalysisButton" Content="Run analyzer" Margin="0,12,0,0" Padding="14,8" Background="#3B6B53" Foreground="White" BorderThickness="0" />
              <TextBlock Margin="0,22,0,6" Text="Helpful notes" FontWeight="Bold" />
              <TextBlock Text="- Full collection writes a master summary and block reports into C:\Stat" TextWrapping="Wrap" />
              <TextBlock Margin="0,6,0,0" Text="- Blocks 1-7 can be launched separately for focused diagnostics" TextWrapping="Wrap" />
              <TextBlock Margin="0,6,0,0" Text="- Refresh the Overview tab after execution to see new outputs" TextWrapping="Wrap" />
            </StackPanel>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="Remote hosts">
        <Grid Margin="16">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.2*" />
            <ColumnDefinition Width="1*" />
          </Grid.ColumnDefinitions>
          <Border Background="#F7F2E6" CornerRadius="12" Padding="16" Margin="0,0,10,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <TextBlock Text="SSH hosts" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <DataGrid x:Name="HostsGrid"
                        Grid.Row="1"
                        Margin="0,12,0,12"
                        AutoGenerateColumns="False"
                        IsReadOnly="True"
                        SelectionMode="Single">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="120" />
                  <DataGridTextColumn Header="Address" Binding="{Binding Address}" Width="140" />
                  <DataGridTextColumn Header="User" Binding="{Binding UserName}" Width="120" />
                  <DataGridTextColumn Header="Port" Binding="{Binding Port}" Width="70" />
                  <DataGridTextColumn Header="Tags" Binding="{Binding Tags}" Width="120" />
                  <DataGridTextColumn Header="Notes" Binding="{Binding Notes}" Width="*" />
                </DataGrid.Columns>
              </DataGrid>
              <WrapPanel Grid.Row="2">
                <Button x:Name="RefreshHostsButton" Content="Refresh list" Margin="0,0,10,0" Padding="14,8" Background="#7E5C35" Foreground="White" BorderThickness="0" />
                <Button x:Name="DeleteHostButton" Content="Delete host" Margin="0,0,10,0" Padding="14,8" Background="#A23C2B" Foreground="White" BorderThickness="0" />
                <ComboBox x:Name="RemoteDaysCombo" Width="110" SelectedIndex="1" Margin="0,0,10,0">
                  <ComboBoxItem Content="3" />
                  <ComboBoxItem Content="7" />
                  <ComboBoxItem Content="14" />
                  <ComboBoxItem Content="30" />
                </ComboBox>
                <Button x:Name="CollectHostButton" Content="Collect over SSH" Margin="0,0,10,0" Padding="14,8" Background="#B64D32" Foreground="White" BorderThickness="0" />
                <Button x:Name="PrepareBundleButton" Content="Prepare bundle" Padding="14,8" Background="#3B6B53" Foreground="White" BorderThickness="0" />
              </WrapPanel>
            </Grid>
          </Border>
          <Border Grid.Column="1" Background="#FDF9F0" CornerRadius="12" Padding="16" Margin="10,0,0,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Text="Host card" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <TextBlock Grid.Row="1" Margin="0,12,0,0" Text="Host name" FontWeight="Bold" />
              <TextBox Grid.Row="2" x:Name="HostNameText" Margin="0,4,0,0" />
              <TextBlock Grid.Row="3" Margin="0,8,0,0" Text="Address or IP" FontWeight="Bold" />
              <TextBox Grid.Row="4" x:Name="HostAddressText" Margin="0,4,0,0" />
              <TextBlock Grid.Row="5" Margin="0,8,0,0" Text="SSH user" FontWeight="Bold" />
              <TextBox Grid.Row="6" x:Name="HostUserText" Margin="0,4,0,0" />
              <TextBlock Grid.Row="7" Margin="0,8,0,0" Text="Port" FontWeight="Bold" />
              <TextBox Grid.Row="8" x:Name="HostPortText" Margin="0,4,0,0" Text="22" />
              <TextBlock Grid.Row="9" Margin="0,8,0,0" Text="SSH key path" FontWeight="Bold" />
              <TextBox Grid.Row="10" x:Name="HostKeyPathText" Margin="0,4,0,0" />
              <TextBlock Grid.Row="11" Margin="0,8,0,0" Text="Remote shell" FontWeight="Bold" />
              <TextBox Grid.Row="12" x:Name="HostShellText" Margin="0,4,0,0" Text="powershell.exe" />
              <TextBlock Grid.Row="13" Margin="0,8,0,0" Text="Comma-separated tags" FontWeight="Bold" />
              <TextBox Grid.Row="14" x:Name="HostTagsText" Margin="0,4,0,0" />
              <TextBlock Grid.Row="15" Margin="0,8,0,0" Text="Notes" FontWeight="Bold" />
              <TextBox Grid.Row="16" x:Name="HostNotesText" Margin="0,4,0,0" Height="70" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" />
              <WrapPanel Grid.Row="17" Margin="0,12,0,0">
                <Button x:Name="NewHostButton" Content="Clear form" Margin="0,0,10,0" Padding="14,8" Background="#7E5C35" Foreground="White" BorderThickness="0" />
                <Button x:Name="SaveHostButton" Content="Save host" Padding="14,8" Background="#3B6B53" Foreground="White" BorderThickness="0" />
              </WrapPanel>
            </Grid>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="Bundles">
        <Grid Margin="16">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.1*" />
            <ColumnDefinition Width="1.3*" />
          </Grid.ColumnDefinitions>
          <Border Background="#F7F2E6" CornerRadius="12" Padding="16" Margin="0,0,10,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
              </Grid.RowDefinitions>
              <TextBlock Text="Saved bundles" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <DataGrid x:Name="BundlesGrid"
                        Grid.Row="1"
                        Margin="0,12,0,12"
                        AutoGenerateColumns="False"
                        IsReadOnly="True"
                        SelectionMode="Single">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="Host" Binding="{Binding HostName}" Width="120" />
                  <DataGridTextColumn Header="Address" Binding="{Binding Address}" Width="130" />
                  <DataGridTextColumn Header="Days" Binding="{Binding Days}" Width="60" />
                  <DataGridTextColumn Header="Generated" Binding="{Binding GeneratedAt}" Width="150" />
                  <DataGridTextColumn Header="Folder" Binding="{Binding Directory}" Width="*" />
                </DataGrid.Columns>
              </DataGrid>
              <WrapPanel Grid.Row="2">
                <Button x:Name="RefreshBundlesButton" Content="Refresh bundles" Margin="0,0,10,0" Padding="14,8" Background="#7E5C35" Foreground="White" BorderThickness="0" />
                <Button x:Name="OpenBundleButton" Content="Open bundle folder" Padding="14,8" Background="#3B6B53" Foreground="White" BorderThickness="0" />
              </WrapPanel>
            </Grid>
          </Border>
          <Border Grid.Column="1" Background="#FDF9F0" CornerRadius="12" Padding="16" Margin="10,0,0,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
              </Grid.RowDefinitions>
              <TextBlock Text="Preview summary.md" FontSize="18" FontWeight="Bold" Foreground="#193549" />
              <TextBox x:Name="BundlePreviewText"
                       Grid.Row="1"
                       Margin="0,12,0,0"
                       IsReadOnly="True"
                       AcceptsReturn="True"
                       TextWrapping="Wrap"
                       VerticalScrollBarVisibility="Auto"
                       HorizontalScrollBarVisibility="Auto"
                       FontFamily="Consolas" />
            </Grid>
          </Border>
        </Grid>
      </TabItem>
    </TabControl>

    <Border Grid.Row="2" Margin="0,16,0,0" Background="#FFFDF8" BorderBrush="#C6B89E" BorderThickness="1" CornerRadius="12" Padding="12">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto" />
          <RowDefinition Height="*" />
        </Grid.RowDefinitions>
        <TextBlock Text="Activity log" FontWeight="Bold" Foreground="#193549" />
        <TextBox x:Name="LogText"
                 Grid.Row="1"
                 Margin="0,10,0,0"
                 IsReadOnly="True"
                 AcceptsReturn="True"
                 TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" />
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$controlNames = @(
    'StatusText', 'OverviewComputer', 'OverviewOs', 'OverviewBoot', 'OverviewCpu', 'OverviewGpu',
    'OverviewMemory', 'OverviewDisks', 'OverviewOutput', 'OverviewReports', 'ReportsGrid',
    'ActionsGrid', 'AnalysisRangeCombo', 'HostsGrid', 'HostNameText', 'HostAddressText',
    'HostUserText', 'HostPortText', 'HostKeyPathText', 'HostShellText', 'HostTagsText',
    'HostNotesText', 'BundlesGrid', 'BundlePreviewText', 'LogText', 'RefreshOverviewButton',
    'OpenOutputRootButton', 'RefreshReportsButton', 'RunActionButton', 'RunAnalysisButton',
    'RefreshHostsButton', 'DeleteHostButton', 'RemoteDaysCombo', 'CollectHostButton',
    'PrepareBundleButton', 'NewHostButton', 'SaveHostButton', 'RefreshBundlesButton',
    'OpenBundleButton'
)

foreach ($name in $controlNames) {
    Set-Variable -Name $name -Value $window.FindName($name) -Scope Script
}

function Add-UiLog {
    param([string]$Message)

    $stamp = Get-Date -Format 'HH:mm:ss'
    $LogText.AppendText(("[{0}] {1}{2}" -f $stamp, $Message, [Environment]::NewLine))
    $LogText.ScrollToEnd()
}

function Set-UiStatus {
    param([string]$Message)

    $StatusText.Text = $Message
}

function Invoke-UiAction {
    param(
        [string]$StartMessage,
        [scriptblock]$Action,
        [string]$SuccessMessage = 'Done.'
    )

    try {
        if ($StartMessage) {
            Set-UiStatus $StartMessage
            Add-UiLog $StartMessage
        }

        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        & $Action
        Set-UiStatus $SuccessMessage
        Add-UiLog $SuccessMessage
    }
    catch {
        $message = $_.Exception.Message
        Set-UiStatus ("Error: {0}" -f $message)
        Add-UiLog ("Error: {0}" -f $message)
        [System.Windows.MessageBox]::Show($message, 'Windows Stat Toolkit', 'OK', 'Error') | Out-Null
    }
    finally {
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
    }
}

function Clear-HostForm {
    $HostNameText.Text = ''
    $HostAddressText.Text = ''
    $HostUserText.Text = ''
    $HostPortText.Text = '22'
    $HostKeyPathText.Text = ''
    $HostShellText.Text = 'powershell.exe'
    $HostTagsText.Text = ''
    $HostNotesText.Text = ''
}

function Refresh-Overview {
    $snapshot = Get-ToolkitLocalOverview
    $OverviewComputer.Text = "Computer: $($snapshot.ComputerName)"
    $OverviewOs.Text = "OS: $($snapshot.OsCaption) ($($snapshot.OsVersion))"
    $OverviewBoot.Text = "Last boot: $($snapshot.LastBoot) | Uptime days: $($snapshot.UptimeDays) | BIOS: $($snapshot.BiosVersion)"
    $OverviewCpu.Text = "CPU: $($snapshot.Cpu)"
    $OverviewGpu.Text = "GPU: $($snapshot.Gpu)"
    $OverviewMemory.Text = "Memory: $($snapshot.Memory)"
    $OverviewDisks.Text = "Disks: $($snapshot.DiskSummary)"
    $OverviewOutput.Text = "Report directory: $($snapshot.OutputRoot)"
    $OverviewReports.Text = "Report files: $($snapshot.ReportCount) | Newest: $($snapshot.NewestReport)"
}

function Refresh-Reports {
    $ReportsGrid.ItemsSource = @(Get-ToolkitRecentReports)
}

function Refresh-Actions {
    $ActionsGrid.ItemsSource = @(Get-ToolkitLocalActions)
    if ($ActionsGrid.Items.Count -gt 0) {
        $ActionsGrid.SelectedIndex = 0
    }
}

function Refresh-Hosts {
    $HostsGrid.ItemsSource = @(Get-ToolkitRemoteHostsView)
}

function Refresh-Bundles {
    $BundlesGrid.ItemsSource = @(Get-ToolkitCollectionRows)
    if ($BundlesGrid.Items.Count -eq 0) {
        $BundlePreviewText.Text = 'No bundles yet.'
    }
}

function Sync-HostFormFromSelection {
    $selected = $HostsGrid.SelectedItem
    if ($null -eq $selected) {
        return
    }

    $host = Get-RemoteHost -Name ([string]$selected.Name)
    if ($null -eq $host) {
        return
    }

    $HostNameText.Text = [string]$host.name
    $HostAddressText.Text = [string]$host.address
    $HostUserText.Text = [string]$host.user_name
    $HostPortText.Text = [string]$host.port
    $HostKeyPathText.Text = [string]$host.key_path
    $HostShellText.Text = if ([string]::IsNullOrWhiteSpace([string]$host.shell)) { 'powershell.exe' } else { [string]$host.shell }
    $HostTagsText.Text = @($host.tags) -join ', '
    $HostNotesText.Text = [string]$host.notes
}

function Get-SelectedRemoteDays {
    [int]([string]$RemoteDaysCombo.Text)
}

function Get-SelectedAnalysisChoice {
    ConvertTo-AnalysisChoice -Label ([string]$AnalysisRangeCombo.Text)
}

$RefreshOverviewButton.Add_Click({
    Invoke-UiAction -StartMessage 'Refreshing local overview.' -Action {
        Refresh-Overview
    } -SuccessMessage 'Local overview refreshed.'
})

$OpenOutputRootButton.Add_Click({
    Invoke-UiAction -StartMessage 'Opening C:\Stat.' -Action {
        Start-Process -FilePath (Ensure-StatOutputRoot)
    } -SuccessMessage 'Report directory opened.'
})

$RefreshReportsButton.Add_Click({
    Invoke-UiAction -StartMessage 'Refreshing reports list.' -Action {
        Refresh-Reports
        Refresh-Overview
    } -SuccessMessage 'Reports list refreshed.'
})

$RunActionButton.Add_Click({
    $selected = $ActionsGrid.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show('Select a local action first.', 'Windows Stat Toolkit', 'OK', 'Information') | Out-Null
        return
    }

    Invoke-UiAction -StartMessage ("Running: {0}" -f $selected.Title) -Action {
        Invoke-ToolkitLocalAction -ActionId $selected.Id
        Refresh-Reports
        Refresh-Overview
    } -SuccessMessage ("Completed: {0}" -f $selected.Title)
})

$RunAnalysisButton.Add_Click({
    $choice = Get-SelectedAnalysisChoice
    Invoke-UiAction -StartMessage 'Running AnalizeV9.' -Action {
        Invoke-ToolkitLocalAction -ActionId 'analyze' -AnalysisChoice $choice
        Refresh-Reports
        Refresh-Overview
    } -SuccessMessage 'AnalizeV9 completed.'
})

$RefreshHostsButton.Add_Click({
    Invoke-UiAction -StartMessage 'Refreshing SSH hosts.' -Action {
        Refresh-Hosts
    } -SuccessMessage 'SSH hosts refreshed.'
})

$NewHostButton.Add_Click({
    Clear-HostForm
    Set-UiStatus 'Host form cleared.'
})

$SaveHostButton.Add_Click({
    Invoke-UiAction -StartMessage 'Saving host card.' -Action {
        if ([string]::IsNullOrWhiteSpace($HostNameText.Text) -or [string]::IsNullOrWhiteSpace($HostAddressText.Text) -or [string]::IsNullOrWhiteSpace($HostUserText.Text)) {
            throw 'Fill in host name, address, and user before saving.'
        }

        $tags = @($HostTagsText.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Save-RemoteHost -Name $HostNameText.Text -Address $HostAddressText.Text -UserName $HostUserText.Text -Port ([int]$HostPortText.Text) -KeyPath $HostKeyPathText.Text -Shell $HostShellText.Text -Tags $tags -Notes $HostNotesText.Text
        Refresh-Hosts
    } -SuccessMessage ("Host saved: {0}" -f $HostNameText.Text)
})

$DeleteHostButton.Add_Click({
    $selected = $HostsGrid.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show('Select a host to delete first.', 'Windows Stat Toolkit', 'OK', 'Information') | Out-Null
        return
    }

    Invoke-UiAction -StartMessage ("Deleting host: {0}" -f $selected.Name) -Action {
        Remove-RemoteHost -Name $selected.Name
        Refresh-Hosts
        Clear-HostForm
    } -SuccessMessage ("Host deleted: {0}" -f $selected.Name)
})

$CollectHostButton.Add_Click({
    $selected = $HostsGrid.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show('Select an SSH host first.', 'Windows Stat Toolkit', 'OK', 'Information') | Out-Null
        return
    }

    $days = Get-SelectedRemoteDays
    Invoke-UiAction -StartMessage ("Collecting over SSH: {0} / {1} days" -f $selected.Name, $days) -Action {
        $host = Get-RemoteHost -Name $selected.Name
        $collection = Invoke-RemoteCollection -Host $host -Days $days
        [void](Save-RemoteCollectionBundle -Host $host -Days $days -Collection $collection)
        Refresh-Bundles
    } -SuccessMessage ("SSH collection completed for {0}" -f $selected.Name)
})

$PrepareBundleButton.Add_Click({
    $selected = $HostsGrid.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show('Select an SSH host first.', 'Windows Stat Toolkit', 'OK', 'Information') | Out-Null
        return
    }

    $days = Get-SelectedRemoteDays
    Invoke-UiAction -StartMessage ("Preparing AI bundle: {0} / {1} days" -f $selected.Name, $days) -Action {
        $host = Get-RemoteHost -Name $selected.Name
        $latestDir = Get-LatestCollectionDirectory -HostName $host.name -Days $days
        if ($null -eq $latestDir) {
            throw "No collection bundle found for '$($host.name)' and period $days."
        }

        $collectionPath = Join-Path -Path $latestDir.FullName -ChildPath 'collection.json'
        $collection = Read-JsonFile -Path $collectionPath
        if ($null -eq $collection) {
            throw "Failed to read $collectionPath"
        }

        [void](Save-RemoteCollectionBundle -Host $host -Days $days -Collection $collection -IncludePrompt)
        Refresh-Bundles
    } -SuccessMessage ("AI bundle prepared for {0}" -f $selected.Name)
})

$RefreshBundlesButton.Add_Click({
    Invoke-UiAction -StartMessage 'Refreshing bundles list.' -Action {
        Refresh-Bundles
    } -SuccessMessage 'Bundles list refreshed.'
})

$OpenBundleButton.Add_Click({
    $selected = $BundlesGrid.SelectedItem
    if ($null -eq $selected) {
        [System.Windows.MessageBox]::Show('Select a bundle first.', 'Windows Stat Toolkit', 'OK', 'Information') | Out-Null
        return
    }

    Invoke-UiAction -StartMessage ("Opening bundle: {0}" -f $selected.Directory) -Action {
        Start-Process -FilePath $selected.Directory
    } -SuccessMessage 'Bundle folder opened.'
})

$HostsGrid.Add_SelectionChanged({
    Sync-HostFormFromSelection
})

$BundlesGrid.Add_SelectionChanged({
    $selected = $BundlesGrid.SelectedItem
    if ($null -eq $selected) {
        $BundlePreviewText.Text = 'Select a bundle to preview its summary.'
        return
    }

    $BundlePreviewText.Text = Get-ToolkitCollectionPreview -SummaryPath $selected.SummaryPath
})

Refresh-Overview
Refresh-Reports
Refresh-Actions
Refresh-Hosts
Refresh-Bundles
Set-UiStatus 'GUI is ready. You can run local or remote diagnostics.'
Add-UiLog 'Application started.'

$window.ShowDialog() | Out-Null
