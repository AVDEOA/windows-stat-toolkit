Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\StatToolkit.Common.ps1"
. "$PSScriptRoot\RemoteDiagnostics.Common.ps1"

function Get-ToolkitLocalOverview {
    $os = Get-CimSafe -ClassName 'Win32_OperatingSystem' | Select-Object -First 1
    $bios = Get-CimSafe -ClassName 'Win32_BIOS' | Select-Object -First 1
    $cpu = @(Get-CimSafe -ClassName 'Win32_Processor')
    $gpus = @(Get-CimSafe -ClassName 'Win32_VideoController')
    $memoryModules = @(Get-CimSafe -ClassName 'Win32_PhysicalMemory')
    $logicalDisks = @(Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3')
    $outputRoot = Ensure-StatOutputRoot
    $recentReports = @(Get-ToolkitRecentReports | Select-Object -First 1)

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        OsCaption = ConvertTo-FlatText $os.Caption
        OsVersion = ConvertTo-FlatText $os.Version
        LastBoot = $(if ($os) { Invoke-Safely -Fallback 'Unavailable' -ScriptBlock { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss') } } else { 'Unavailable' })
        UptimeDays = $(if ($os) { Invoke-Safely -Fallback 'Unavailable' -ScriptBlock { [math]::Round(((Get-Date) - [datetime]$os.LastBootUpTime).TotalDays, 2) } } else { 'Unavailable' })
        BiosVersion = ConvertTo-FlatText $bios.SMBIOSBIOSVersion
        Cpu = $(if ($cpu.Count -gt 0) { ($cpu | ForEach-Object { $_.Name }) -join ', ' } else { 'Unavailable' })
        Gpu = $(if ($gpus.Count -gt 0) { ($gpus | ForEach-Object { $_.Name }) -join ', ' } else { 'Unavailable' })
        Memory = $(if ($memoryModules.Count -gt 0) { Format-Bytes ((($memoryModules | Measure-Object -Property Capacity -Sum).Sum)) } else { 'Unavailable' })
        DiskSummary = $(if ($logicalDisks.Count -gt 0) {
            ($logicalDisks | ForEach-Object { '{0}: {1} free of {2}' -f $_.DeviceID, (Format-Bytes $_.FreeSpace), (Format-Bytes $_.Size) }) -join '; '
        }
        else {
            'Unavailable'
        })
        OutputRoot = $outputRoot
        ReportCount = @((Get-ChildItem -LiteralPath $outputRoot -File -Filter '*.txt' -ErrorAction SilentlyContinue)).Count
        NewestReport = $(if ($recentReports.Count -gt 0) { $recentReports[0].Name } else { 'No reports yet' })
    }
}

function Get-ToolkitRecentReports {
    $root = Ensure-StatOutputRoot
    @(Get-ChildItem -LiteralPath $root -File -Filter '*.txt' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object @{
                Name = 'Name'
                Expression = { $_.Name }
            }, @{
                Name = 'LastWriteTime'
                Expression = { $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
            }, @{
                Name = 'SizeKb'
                Expression = { [math]::Round($_.Length / 1KB, 1) }
            }, @{
                Name = 'Path'
                Expression = { $_.FullName }
            })
}

function Get-ToolkitLocalActions {
    @(
        [pscustomobject]@{ Id = 'full'; Title = 'Full collection'; Description = 'Runs all 7 diagnostic blocks and writes a master summary.'; ScriptPath = "$PSScriptRoot\Run-All-Stat-Collection.ps1" }
        [pscustomobject]@{ Id = 'block1'; Title = 'Block 1'; Description = 'System overview, BIOS, CPU, and memory.'; ScriptPath = "$PSScriptRoot\Block1_SystemInfo.ps1" }
        [pscustomobject]@{ Id = 'block2'; Title = 'Block 2'; Description = 'Uptime, load, disks, and general statistics.'; ScriptPath = "$PSScriptRoot\Block2_SystemStats.ps1" }
        [pscustomobject]@{ Id = 'block3'; Title = 'Block 3'; Description = 'Driver and device initialization failures.'; ScriptPath = "$PSScriptRoot\Block3_DriverErrors.ps1" }
        [pscustomobject]@{ Id = 'block4'; Title = 'Block 4'; Description = 'GPU and display driver failures.'; ScriptPath = "$PSScriptRoot\Block4_GPUDriverErrors.ps1" }
        [pscustomobject]@{ Id = 'block5'; Title = 'Block 5'; Description = 'WHEA, PCIe, and hardware stability.'; ScriptPath = "$PSScriptRoot\Block5_WHEA_PCI_Errors.ps1" }
        [pscustomobject]@{ Id = 'block6'; Title = 'Block 6'; Description = 'BSOD, crash, and dump signals.'; ScriptPath = "$PSScriptRoot\Block6_BSOD_CrashErrors.ps1" }
        [pscustomobject]@{ Id = 'block7'; Title = 'Block 7'; Description = 'Additional critical error categories.'; ScriptPath = "$PSScriptRoot\Block7_AdditionalCriticalErrors.ps1" }
    )
}

function Invoke-ToolkitLocalAction {
    param(
        [Parameter(Mandatory = $true)][string]$ActionId,
        [string]$AnalysisChoice = '2'
    )

    if ($ActionId -eq 'analyze') {
        & "$PSScriptRoot\AnalizeV9.ps1" -PeriodChoice $AnalysisChoice
        return
    }

    $action = @(Get-ToolkitLocalActions | Where-Object { $_.Id -eq $ActionId } | Select-Object -First 1)
    if ($action.Count -eq 0) {
        throw "Unknown toolkit action id: $ActionId"
    }

    & $action[0].ScriptPath
}

function Get-ToolkitRemoteHostsView {
    $config = Get-RemoteHostsConfig
    @($config.hosts |
        Sort-Object name |
        Select-Object @{
                Name = 'Name'
                Expression = { $_.name }
            }, @{
                Name = 'Address'
                Expression = { $_.address }
            }, @{
                Name = 'UserName'
                Expression = { $_.user_name }
            }, @{
                Name = 'Port'
                Expression = { $_.port }
            }, @{
                Name = 'Shell'
                Expression = { $_.shell }
            }, @{
                Name = 'Tags'
                Expression = { @($_.tags) -join ', ' }
            }, @{
                Name = 'Notes'
                Expression = { $_.notes }
            })
}

function Get-ToolkitCollectionRows {
    $root = Get-RemoteDiagnosticsCollectionsRoot
    if (-not (Test-Path -LiteralPath $root)) {
        return @()
    }

    $rows = foreach ($hostDir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        foreach ($bundleDir in @(Get-ChildItem -LiteralPath $hostDir.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
            $metaPath = Join-Path -Path $bundleDir.FullName -ChildPath 'bundle.meta.json'
            $meta = Read-JsonFile -Path $metaPath
            [pscustomobject]@{
                HostName = $(if ($meta) { $meta.host_name } else { $hostDir.Name })
                Address = $(if ($meta) { $meta.host_address } else { '' })
                Days = $(if ($meta) { [string]$meta.period_days } else { '' })
                GeneratedAt = $(if ($meta) { $meta.generated_at } else { $bundleDir.LastWriteTime.ToString('s') })
                Directory = $bundleDir.FullName
                SummaryPath = Join-Path -Path $bundleDir.FullName -ChildPath 'summary.md'
                CollectionPath = Join-Path -Path $bundleDir.FullName -ChildPath 'collection.json'
                PromptPath = Join-Path -Path $bundleDir.FullName -ChildPath 'analysis_prompt.md'
            }
        }
    }

    @($rows | Sort-Object GeneratedAt -Descending)
}

function Get-ToolkitCollectionPreview {
    param([string]$SummaryPath)

    if ([string]::IsNullOrWhiteSpace($SummaryPath) -or -not (Test-Path -LiteralPath $SummaryPath)) {
        return 'Select a bundle to preview its summary.'
    }

    Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8
}

function ConvertTo-AnalysisChoice {
    param([string]$Label)

    switch ($Label) {
        '2 days' { '1' }
        '7 days' { '2' }
        '14 days' { '3' }
        '30 days' { '4' }
        'All time' { '5' }
        default { '2' }
    }
}
