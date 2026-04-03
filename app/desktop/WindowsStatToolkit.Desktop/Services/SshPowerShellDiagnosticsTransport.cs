using System.Diagnostics;
using System.IO;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using WindowsStatToolkit.Desktop.Interfaces;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class SshPowerShellDiagnosticsTransport : IRemoteDiagnosticsTransport
{
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<bool> PingHostAsync(HostDefinition host)
    {
        using var ping = new Ping();
        var reply = await ping.SendPingAsync(host.Address, 3000);
        return reply.Status == IPStatus.Success;
    }

    public async Task<DiagnosticSnapshot> CollectSnapshotAsync(HostDefinition host, DiagnosticQuery query, CancellationToken cancellationToken)
    {
        var script = BuildSnapshotScript(query.Days, query.MaxEventsPerCategory);
        var output = await InvokePowerShellOverSshAsync(host, script, cancellationToken);
        var json = ExtractJsonPayload(output);
        return JsonSerializer.Deserialize<DiagnosticSnapshot>(json, _jsonOptions)
            ?? throw new InvalidOperationException("Failed to deserialize diagnostic snapshot.");
    }

    private async Task<string> InvokePowerShellOverSshAsync(HostDefinition host, string script, CancellationToken cancellationToken)
    {
        var sshPath = ResolveSshPath();
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));

        var psi = new ProcessStartInfo
        {
            FileName = sshPath,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("BatchMode=yes");
        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("ConnectTimeout=10");
        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("StrictHostKeyChecking=accept-new");
        psi.ArgumentList.Add("-p");
        psi.ArgumentList.Add(host.Port.ToString());

        if (!string.IsNullOrWhiteSpace(host.KeyPath))
        {
            psi.ArgumentList.Add("-i");
            psi.ArgumentList.Add(host.KeyPath);
        }

        psi.ArgumentList.Add($"{host.UserName}@{host.Address}");
        psi.ArgumentList.Add(string.IsNullOrWhiteSpace(host.Shell) ? "powershell.exe" : host.Shell);
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-NonInteractive");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-EncodedCommand");
        psi.ArgumentList.Add(encoded);

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"SSH command failed for {host.Name}: {stderr}{Environment.NewLine}{stdout}".Trim());
        }

        return stdout;
    }

    private static string ExtractJsonPayload(string output)
    {
        var candidate = output
            .Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries)
            .LastOrDefault(line => line.TrimStart().StartsWith("{") && line.TrimEnd().EndsWith("}"));

        if (string.IsNullOrWhiteSpace(candidate))
        {
            throw new InvalidOperationException("Remote host did not return a JSON payload.");
        }

        return candidate;
    }

    private static string ResolveSshPath()
    {
        var windowsPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "OpenSSH",
            "ssh.exe");

        if (File.Exists(windowsPath))
        {
            return windowsPath;
        }

        return "ssh.exe";
    }

    private static string BuildSnapshotScript(int? days, int maxEventsPerCategory)
    {
        var startTime = days.HasValue
            ? $"(Get-Date).AddDays(-{days.Value})"
            : "[datetime]'2000-01-01T00:00:00'";
        var periodLabel = days.HasValue ? $"{days.Value}_days" : "all_time";
        var periodDaysLiteral = days.HasValue ? days.Value.ToString() : "$null";

        return $$"""
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Invoke-Safely {
    param([scriptblock]$ScriptBlock, $Fallback = $null)
    try { & $ScriptBlock } catch { $Fallback }
}

function Get-CimSafe {
    param([string]$ClassName, [string]$Namespace = 'root/cimv2', [string]$Filter)
    Invoke-Safely -Fallback $null -ScriptBlock {
        if ($Filter) { Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop }
        else { Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop }
    }
}

function Get-ShortMessage {
    param($EventRecord)
    $message = Invoke-Safely -Fallback 'Message unavailable.' -ScriptBlock { [string]$EventRecord.Message }
    $message = ($message -replace '\s+', ' ').Trim()
    if ($message.Length -gt 400) { return $message.Substring(0, 400) + '...' }
    $message
}

function Get-FilteredEvents {
    param(
        [string[]]$LogNames = @('System', 'Application'),
        [datetime]$StartTime,
        [int[]]$Levels = @(1,2,3),
        [string[]]$ProviderPatterns = @(),
        [string[]]$MessagePatterns = @(),
        [int[]]$Ids = @(),
        [int]$MaxPerLog = 1000
    )

    $allEvents = New-Object System.Collections.Generic.List[object]
    foreach ($logName in $LogNames) {
        $filter = @{ LogName = $logName; StartTime = $StartTime }
        if ($Levels.Count -gt 0) { $filter.Level = $Levels }
        $events = Invoke-Safely -Fallback @() -ScriptBlock { Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxPerLog -ErrorAction Stop }

        foreach ($event in $events) {
            $providerOk = $ProviderPatterns.Count -eq 0
            foreach ($pattern in $ProviderPatterns) {
                if ($event.ProviderName -like $pattern) { $providerOk = $true; break }
            }

            $messageOk = $MessagePatterns.Count -eq 0
            if ($MessagePatterns.Count -gt 0) {
                $messageText = Invoke-Safely -Fallback '' -ScriptBlock { [string]$event.Message }
                foreach ($pattern in $MessagePatterns) {
                    if ($messageText -match $pattern) { $messageOk = $true; break }
                }
            }

            $idOk = $Ids.Count -eq 0 -or ($Ids -contains [int]$event.Id)

            if ($providerOk -and $messageOk -and $idOk) { [void]$allEvents.Add($event) }
        }
    }

    $allEvents | Sort-Object TimeCreated -Descending | Select-Object -First {{maxEventsPerCategory}}
}

function Convert-EventSet {
    param([string]$Title, [object[]]$Events)
    [ordered]@{
        title = $Title
        count = @($Events).Count
        events = @(
            @($Events) | ForEach-Object {
                [ordered]@{
                    time_created = Invoke-Safely -Fallback $null -ScriptBlock { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') }
                    provider = $_.ProviderName
                    id = [int]$_.Id
                    level = $_.LevelDisplayName
                    log_name = $_.LogName
                    message = Get-ShortMessage -EventRecord $_
                }
            }
        )
    }
}

$startTime = {{startTime}}
$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
$bios = Get-CimSafe -ClassName 'Win32_BIOS'
$cpu = @(Get-CimSafe -ClassName 'Win32_Processor')
$gpus = @(Get-CimSafe -ClassName 'Win32_VideoController')
$memoryModules = @(Get-CimSafe -ClassName 'Win32_PhysicalMemory')
$disks = @(Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter "DriveType=3")

$restartEvents = @(Get-FilteredEvents -LogNames @('System') -StartTime $startTime -Levels @(1,2,3,4) -Ids @(41,1074,6005,6006,6008,1076,109) -MaxPerLog 500)
$driverEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2,3) -ProviderPatterns @('*Kernel-PnP*','*UserPnp*','*DeviceSetupManager*') -MessagePatterns @('(?i)(driver|device).*(failed|failure|not started|problem|unable|could not|did not load)') -MaxPerLog 500)
$gpuEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2,3) -ProviderPatterns @('Display','*Display*','nvlddmkm','*NVIDIA*','amdkmdag','amdwddmg','*AMD*','*DxgKrnl*') -MessagePatterns @('(?i)(TDR|timeout|display driver|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)') -MaxPerLog 500)
$hardwareEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2,3) -ProviderPatterns @('*WHEA*') -MessagePatterns @('(?i)(PCI Express|PCIe|corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)') -MaxPerLog 500)
$bsodEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2,3) -ProviderPatterns @('*BugCheck*','*WER-SystemErrorReporting*','*Windows Error Reporting*','*Kernel-Power*') -MessagePatterns @('(?i)(bugcheck|blue screen|stop code|LiveKernelEvent|dump)') -MaxPerLog 500)
$storageEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2,3) -ProviderPatterns @('disk','storahci','stornvme','iaStorA','iaStorV','volmgr','partmgr','Ntfs','ReFS','Chkdsk') -MessagePatterns @('(?i)(bad block|file system|corrupt|corruption|volume|storage|disk)') -MaxPerLog 500)
$criticalEvents = @(Get-FilteredEvents -StartTime $startTime -Levels @(1,2) -LogNames @('System','Application') -MaxPerLog 500)

$result = [ordered]@{
    generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    period_label = '{{periodLabel}}'
    period_days = {{periodDaysLiteral}}
    start_time = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    host = [ordered]@{
        computer_name = $env:COMPUTERNAME
        os_caption = Invoke-Safely -Fallback $null -ScriptBlock { $os.Caption }
        os_version = Invoke-Safely -Fallback $null -ScriptBlock { $os.Version }
        last_boot = Invoke-Safely -Fallback $null -ScriptBlock { ([datetime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm:ss') }
        uptime_days = Invoke-Safely -Fallback $null -ScriptBlock { [math]::Round(((Get-Date) - [datetime]$os.LastBootUpTime).TotalDays, 2) }
        bios_version = Invoke-Safely -Fallback $null -ScriptBlock { ($bios.SMBIOSBIOSVersion -join ', ') }
        cpu = @($cpu | ForEach-Object { $_.Name })
        gpus = @($gpus | ForEach-Object { $_.Name })
        memory_gb = Invoke-Safely -Fallback $null -ScriptBlock { [math]::Round(((@($memoryModules | Measure-Object -Property Capacity -Sum).Sum) / 1GB), 2) }
        disks = @($disks | ForEach-Object {
            [ordered]@{
                device_id = $_.DeviceID
                size_gb = [math]::Round(($_.Size / 1GB), 2)
                free_gb = [math]::Round(($_.FreeSpace / 1GB), 2)
                file_system = $_.FileSystem
            }
        })
    }
    categories = [ordered]@{
        restart_shutdown = Convert-EventSet -Title 'Restart and shutdown history' -Events $restartEvents
        driver = Convert-EventSet -Title 'Driver and device failures' -Events $driverEvents
        gpu = Convert-EventSet -Title 'GPU and display failures' -Events $gpuEvents
        hardware = Convert-EventSet -Title 'WHEA and hardware failures' -Events $hardwareEvents
        bsod = Convert-EventSet -Title 'BSOD and crash failures' -Events $bsodEvents
        storage = Convert-EventSet -Title 'Storage and file system failures' -Events $storageEvents
        critical = Convert-EventSet -Title 'Critical system and application events' -Events $criticalEvents
    }
}

$result | ConvertTo-Json -Depth 8 -Compress
""";
    }
}
