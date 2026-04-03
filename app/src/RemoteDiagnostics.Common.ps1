Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RemoteDiagnosticsStateRoot {
    Join-Path -Path $PSScriptRoot -ChildPath 'state\remote-diagnostics'
}

function Get-RemoteDiagnosticsConfigRoot {
    Join-Path -Path (Get-RemoteDiagnosticsStateRoot) -ChildPath 'config'
}

function Get-RemoteDiagnosticsCollectionsRoot {
    Join-Path -Path (Get-RemoteDiagnosticsStateRoot) -ChildPath 'collections'
}

function Ensure-RemoteDiagnosticsLayout {
    $paths = @(
        (Get-RemoteDiagnosticsStateRoot),
        (Get-RemoteDiagnosticsConfigRoot),
        (Get-RemoteDiagnosticsCollectionsRoot)
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Get-RemoteHostsConfigPath {
    Join-Path -Path (Get-RemoteDiagnosticsConfigRoot) -ChildPath 'hosts.json'
}

function Get-RemoteHostsExamplePath {
    Join-Path -Path $PSScriptRoot -ChildPath 'remote_hosts.example.json'
}

function Initialize-RemoteDiagnosticsState {
    Ensure-RemoteDiagnosticsLayout

    $configPath = Get-RemoteHostsConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        $exampleHosts = @(
            [ordered]@{
                name = 'sample-node'
                address = '192.168.1.20'
                user_name = 'administrator'
                port = 22
                key_path = ''
                shell = 'powershell.exe'
                notes = 'Use SSH key or agent auth.'
                tags = @('windows', 'sample')
            }
        )

        $payload = [ordered]@{
            version = 1
            updated_at = (Get-Date).ToString('s')
            hosts = $exampleHosts
        }

        [System.IO.File]::WriteAllText($configPath, ($payload | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    }

    $examplePath = Get-RemoteHostsExamplePath
    if (-not (Test-Path -LiteralPath $examplePath)) {
        [System.IO.File]::WriteAllText($examplePath, [System.IO.File]::ReadAllText($configPath), [System.Text.UTF8Encoding]::new($false))
    }

    $configPath
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $raw | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Get-RemoteHostsConfig {
    Initialize-RemoteDiagnosticsState | Out-Null
    $configPath = Get-RemoteHostsConfigPath
    $config = Read-JsonFile -Path $configPath
    if ($null -eq $config) {
        return [ordered]@{
            version = 1
            updated_at = (Get-Date).ToString('s')
            hosts = @()
        }
    }

    return $config
}

function Save-RemoteHostsConfig {
    param([Parameter(Mandatory = $true)][object]$Config)

    $Config.updated_at = (Get-Date).ToString('s')
    Write-JsonFile -Path (Get-RemoteHostsConfigPath) -Value $Config
}

function Get-RemoteHost {
    param([Parameter(Mandatory = $true)][string]$Name)

    $config = Get-RemoteHostsConfig
    foreach ($host in @($config.hosts)) {
        if ($host.name -eq $Name) {
            return $host
        }
    }

    return $null
}

function Save-RemoteHost {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Address,
        [Parameter(Mandatory = $true)][string]$UserName,
        [int]$Port = 22,
        [string]$KeyPath = '',
        [string]$Shell = 'powershell.exe',
        [string[]]$Tags = @(),
        [string]$Notes = ''
    )

    $config = Get-RemoteHostsConfig
    if (@($Tags).Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($Tags[0]) -and $Tags[0].Contains(',')) {
        $Tags = @($Tags[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $hosts = @()
    $updated = $false

    foreach ($existing in @($config.hosts)) {
        if ($existing.name -eq $Name) {
            $hosts += [pscustomobject]@{
                name = $Name
                address = $Address
                user_name = $UserName
                port = $Port
                key_path = $KeyPath
                shell = $Shell
                notes = $Notes
                tags = @($Tags)
            }
            $updated = $true
        }
        else {
            $hosts += $existing
        }
    }

    if (-not $updated) {
        $hosts += [pscustomobject]@{
            name = $Name
            address = $Address
            user_name = $UserName
            port = $Port
            key_path = $KeyPath
            shell = $Shell
            notes = $Notes
            tags = @($Tags)
        }
    }

    $config.hosts = @($hosts)
    Save-RemoteHostsConfig -Config $config
}

function Remove-RemoteHost {
    param([Parameter(Mandatory = $true)][string]$Name)

    $config = Get-RemoteHostsConfig
    $filtered = @($config.hosts | Where-Object { $_.name -ne $Name })
    $config.hosts = $filtered
    Save-RemoteHostsConfig -Config $config
}

function Resolve-RemoteDays {
    param([Parameter(Mandatory = $true)][int]$Days)

    if ($Days -notin @(3, 7, 14, 30)) {
        throw 'Supported periods are 3, 7, 14, and 30 days.'
    }

    $Days
}

function Get-CollectionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Days
    )

    $safeHost = ($HostName -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    Join-Path -Path (Get-RemoteDiagnosticsCollectionsRoot) -ChildPath "$safeHost\$stamp-$Days-days"
}

function Get-SshCommandPath {
    $candidates = @(
        (Get-Command -Name 'ssh.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
        'C:\Windows\System32\OpenSSH\ssh.exe'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'ssh.exe was not found. Install OpenSSH Client on this machine first.'
}

function ConvertTo-ShortText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $trimmed = ($text -replace '\s+', ' ').Trim()
    if ($trimmed.Length -gt 280) {
        return $trimmed.Substring(0, 280) + '...'
    }

    $trimmed
}

function New-RemoteCollectorEncodedCommand {
    param(
        [Parameter(Mandatory = $true)][int]$Days,
        [int]$MaxEvents = 40
    )

    $script = @"
`$ErrorActionPreference = 'Stop'
`$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Invoke-Safely {
    param(
        [Parameter(Mandatory = `$true)][scriptblock]`$ScriptBlock,
        [object]`$Fallback = `$null
    )

    try { & `$ScriptBlock } catch { `$Fallback }
}

function Get-CimSafe {
    param(
        [Parameter(Mandatory = `$true)][string]`$ClassName,
        [string]`$Namespace = 'root/cimv2',
        [string]`$Filter
    )

    Invoke-Safely -Fallback `$null -ScriptBlock {
        if (`$Filter) {
            Get-CimInstance -Namespace `$Namespace -ClassName `$ClassName -Filter `$Filter -ErrorAction Stop
        }
        else {
            Get-CimInstance -Namespace `$Namespace -ClassName `$ClassName -ErrorAction Stop
        }
    }
}

function Get-ShortMessage {
    param([object]`$EventRecord)

    `$message = Invoke-Safely -Fallback 'Message unavailable.' -ScriptBlock { [string]`$EventRecord.Message }
    `$message = (`$message -replace '\s+', ' ').Trim()
    if (`$message.Length -gt 260) {
        return `$message.Substring(0, 260) + '...'
    }

    `$message
}

function Get-FilteredEvents {
    param(
        [string[]]`$LogNames = @('System', 'Application'),
        [datetime]`$StartTime,
        [int[]]`$Levels = @(1, 2, 3),
        [string[]]`$ProviderPatterns = @(),
        [string[]]`$MessagePatterns = @(),
        [int[]]`$Ids = @(),
        [int]`$MaxPerLog = 200
    )

    `$allEvents = New-Object System.Collections.Generic.List[object]
    foreach (`$logName in `$LogNames) {
        `$filter = @{
            LogName = `$logName
            StartTime = `$StartTime
        }

        if (`$Levels -and `$Levels.Count -gt 0) {
            `$filter.Level = `$Levels
        }

        `$events = Invoke-Safely -Fallback @() -ScriptBlock {
            Get-WinEvent -FilterHashtable `$filter -MaxEvents `$MaxPerLog -ErrorAction Stop
        }

        foreach (`$event in `$events) {
            `$providerOk = `$true
            `$messageOk = `$true
            `$idOk = `$true

            if (`$ProviderPatterns.Count -gt 0) {
                `$providerOk = `$false
                foreach (`$pattern in `$ProviderPatterns) {
                    if (`$event.ProviderName -like `$pattern) {
                        `$providerOk = `$true
                        break
                    }
                }
            }

            if (`$MessagePatterns.Count -gt 0) {
                `$messageOk = `$false
                `$messageText = Invoke-Safely -Fallback '' -ScriptBlock { [string]`$event.Message }
                foreach (`$pattern in `$MessagePatterns) {
                    if (`$messageText -match `$pattern) {
                        `$messageOk = `$true
                        break
                    }
                }
            }

            if (`$Ids.Count -gt 0) {
                `$idOk = `$Ids -contains [int]`$event.Id
            }

            if (`$providerOk -and `$messageOk -and `$idOk) {
                [void]`$allEvents.Add(`$event)
            }
        }
    }

    `$allEvents | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents
}

function Convert-EventSet {
    param(
        [string]`$Title,
        [object[]]`$Events
    )

    [ordered]@{
        title = `$Title
        count = @(`$Events).Count
        events = @(
            @(`$Events) | ForEach-Object {
                [ordered]@{
                    time_created = Invoke-Safely -Fallback `$null -ScriptBlock { `$_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') }
                    provider = `$_.ProviderName
                    id = [int]`$_.Id
                    level = `$_.LevelDisplayName
                    message = Get-ShortMessage -EventRecord `$_
                }
            }
        )
    }
}

`$days = $Days
`$startTime = (Get-Date).AddDays(-`$days)
`$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
`$bios = Get-CimSafe -ClassName 'Win32_BIOS'
`$cpu = @(Get-CimSafe -ClassName 'Win32_Processor')
`$gpus = @(Get-CimSafe -ClassName 'Win32_VideoController')
`$memoryModules = @(Get-CimSafe -ClassName 'Win32_PhysicalMemory')
`$disks = @(Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter "DriveType=3")

`$restartEvents = @(Get-FilteredEvents -LogNames @('System') -StartTime `$startTime -Levels @(1,2,3,4) -Ids @(41,1074,6005,6006,6008,1076,109) -MaxPerLog 500)
`$driverEvents = @(Get-FilteredEvents -StartTime `$startTime -Levels @(1,2,3) -ProviderPatterns @('*Kernel-PnP*','*UserPnp*','*DeviceSetupManager*') -MessagePatterns @('(?i)(driver|device).*(failed|failure|not started|problem|unable|could not|did not load)') -MaxPerLog 400)
`$gpuEvents = @(Get-FilteredEvents -StartTime `$startTime -Levels @(1,2,3) -ProviderPatterns @('Display','*Display*','nvlddmkm','*NVIDIA*','amdkmdag','amdwddmg','*AMD*','*DxgKrnl*') -MessagePatterns @('(?i)(TDR|timeout|display driver|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)') -MaxPerLog 400)
`$hardwareEvents = @(Get-FilteredEvents -StartTime `$startTime -Levels @(1,2,3) -ProviderPatterns @('*WHEA*') -MessagePatterns @('(?i)(PCI Express|PCIe|corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)') -MaxPerLog 400)
`$bsodEvents = @(Get-FilteredEvents -StartTime `$startTime -Levels @(1,2,3) -ProviderPatterns @('*BugCheck*','*WER-SystemErrorReporting*','*Windows Error Reporting*','*Kernel-Power*') -MessagePatterns @('(?i)(bugcheck|blue screen|stop code|LiveKernelEvent|dump)') -MaxPerLog 400)
`$storageEvents = @(Get-FilteredEvents -StartTime `$startTime -Levels @(1,2,3) -ProviderPatterns @('disk','storahci','stornvme','iaStorA','iaStorV','volmgr','partmgr','Ntfs','ReFS','Chkdsk') -MessagePatterns @('(?i)(bad block|file system|corrupt|corruption|volume|storage|disk)') -MaxPerLog 400)

`$result = [ordered]@{
    generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    period_days = `$days
    start_time = `$startTime.ToString('yyyy-MM-dd HH:mm:ss')
    host = [ordered]@{
        computer_name = `$env:COMPUTERNAME
        os_caption = Invoke-Safely -Fallback `$null -ScriptBlock { `$os.Caption }
        os_version = Invoke-Safely -Fallback `$null -ScriptBlock { `$os.Version }
        last_boot = Invoke-Safely -Fallback `$null -ScriptBlock { ([datetime]`$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm:ss') }
        uptime_days = Invoke-Safely -Fallback `$null -ScriptBlock { [math]::Round(((Get-Date) - [datetime]`$os.LastBootUpTime).TotalDays, 2) }
        bios_version = Invoke-Safely -Fallback `$null -ScriptBlock { (`$bios.SMBIOSBIOSVersion -join ', ') }
        cpu = @(`$cpu | ForEach-Object { `$_.Name })
        gpus = @(`$gpus | ForEach-Object { `$_.Name })
        memory_gb = Invoke-Safely -Fallback `$null -ScriptBlock { [math]::Round(((@(`$memoryModules | Measure-Object -Property Capacity -Sum).Sum) / 1GB), 2) }
        disks = @(`$disks | ForEach-Object {
            [ordered]@{
                device_id = `$_.DeviceID
                size_gb = [math]::Round((`$_.Size / 1GB), 2)
                free_gb = [math]::Round((`$_.FreeSpace / 1GB), 2)
                file_system = `$_.FileSystem
            }
        })
    }
    categories = [ordered]@{
        restart_shutdown = Convert-EventSet -Title 'Restart and shutdown history' -Events `$restartEvents
        driver = Convert-EventSet -Title 'Driver and device failures' -Events `$driverEvents
        gpu = Convert-EventSet -Title 'GPU and display failures' -Events `$gpuEvents
        hardware = Convert-EventSet -Title 'WHEA and hardware failures' -Events `$hardwareEvents
        bsod = Convert-EventSet -Title 'BSOD and crash failures' -Events `$bsodEvents
        storage = Convert-EventSet -Title 'Storage and file system failures' -Events `$storageEvents
    }
}

`$result | ConvertTo-Json -Depth 8 -Compress
"@

    [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
}

function Invoke-RemoteCollection {
    param(
        [Parameter(Mandatory = $true)][object]$Host,
        [Parameter(Mandatory = $true)][int]$Days,
        [int]$MaxEvents = 40
    )

    $Days = Resolve-RemoteDays -Days $Days
    $sshExe = Get-SshCommandPath
    $target = if ([string]::IsNullOrWhiteSpace($Host.user_name)) { $Host.address } else { '{0}@{1}' -f $Host.user_name, $Host.address }
    $encoded = New-RemoteCollectorEncodedCommand -Days $Days -MaxEvents $MaxEvents
    $remoteShell = if ([string]::IsNullOrWhiteSpace($Host.shell)) { 'powershell.exe' } else { [string]$Host.shell }

    $args = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=accept-new'
    )

    if ($Host.port) {
        $args += @('-p', [string]$Host.port)
    }

    if (-not [string]::IsNullOrWhiteSpace($Host.key_path)) {
        $args += @('-i', [string]$Host.key_path)
    }

    $args += @(
        $target,
        $remoteShell,
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        $encoded
    )

    $stdout = & $sshExe @args 2>&1 | ForEach-Object { [string]$_ }
    if ($LASTEXITCODE -ne 0) {
        throw ("SSH collection failed for {0}: {1}" -f $Host.name, (($stdout -join [Environment]::NewLine).Trim()))
    }

    $text = ($stdout -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "SSH collection returned an empty payload for $($Host.name)."
    }

    $jsonLine = ($text -split '\r?\n' | Where-Object { $_.TrimStart().StartsWith('{') -and $_.TrimEnd().EndsWith('}') } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($jsonLine)) {
        throw ("SSH collection for {0} did not return a JSON payload. Raw output:`n{1}" -f $Host.name, $text)
    }

    return $jsonLine | ConvertFrom-Json
}

function New-RemoteCollectionSummary {
    param(
        [Parameter(Mandatory = $true)][object]$Collection,
        [Parameter(Mandatory = $true)][object]$Host
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Remote Diagnostics Summary") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add(("Host: {0} ({1})" -f $Host.name, $Host.address)) | Out-Null
    $lines.Add(("Collected at: {0}" -f $Collection.generated_at)) | Out-Null
    $lines.Add(("Period: last {0} days" -f $Collection.period_days)) | Out-Null
    $lines.Add('') | Out-Null

    if ($Collection.host) {
        $lines.Add('## System') | Out-Null
        $lines.Add(("- Computer: {0}" -f $Collection.host.computer_name)) | Out-Null
        $lines.Add(("- OS: {0} {1}" -f $Collection.host.os_caption, $Collection.host.os_version)) | Out-Null
        $lines.Add(("- Last boot: {0}" -f $Collection.host.last_boot)) | Out-Null
        $lines.Add(("- Uptime days: {0}" -f $Collection.host.uptime_days)) | Out-Null
        $lines.Add(("- CPU: {0}" -f ((@($Collection.host.cpu) -join ', ')))) | Out-Null
        $lines.Add(("- GPU: {0}" -f ((@($Collection.host.gpus) -join ', ')))) | Out-Null
        $lines.Add(("- Memory GB: {0}" -f $Collection.host.memory_gb)) | Out-Null
        $lines.Add('') | Out-Null
    }

    $lines.Add('## Category Counts') | Out-Null
    foreach ($property in $Collection.categories.PSObject.Properties) {
        $category = $property.Value
        $lines.Add(("- {0}: {1}" -f $category.title, $category.count)) | Out-Null
    }

    $lines.Add('') | Out-Null
    $lines.Add('## Top Events') | Out-Null
    foreach ($property in $Collection.categories.PSObject.Properties) {
        $category = $property.Value
        if (@($category.events).Count -eq 0) {
            continue
        }

        $lines.Add('') | Out-Null
        $lines.Add(("### {0}" -f $category.title)) | Out-Null
        foreach ($event in @($category.events | Select-Object -First 5)) {
            $lines.Add(("- [{0}] {1} | ID {2} | {3}" -f $event.time_created, $event.provider, $event.id, (ConvertTo-ShortText -Value $event.message))) | Out-Null
        }
    }

    @($lines)
}

function New-AnalysisPromptText {
    param(
        [Parameter(Mandatory = $true)][object]$Collection,
        [Parameter(Mandatory = $true)][object]$Host
    )

@"
You are analyzing a Windows diagnostics bundle collected over SSH.

Target host:
- Name: $($Host.name)
- Address: $($Host.address)
- Period: last $($Collection.period_days) days

Files in this bundle:
- `collection.json`: raw structured diagnostics payload
- `summary.md`: compact local summary

Task:
1. Identify the most likely root causes or failure clusters.
2. Separate confirmed evidence from hypotheses.
3. Rank issues by severity and urgency.
4. Note whether the pattern suggests driver, GPU, hardware, storage, or shutdown instability.
5. Recommend the next diagnostic or remediation steps.
6. Produce a detailed analysis in Russian.

Output format:
- Executive summary
- Confirmed signals
- Likely root causes
- Recommended next steps
- Risks if ignored
"@
}

function Save-RemoteCollectionBundle {
    param(
        [Parameter(Mandatory = $true)][object]$Host,
        [Parameter(Mandatory = $true)][int]$Days,
        [Parameter(Mandatory = $true)][object]$Collection,
        [switch]$IncludePrompt
    )

    $directory = Get-CollectionDirectory -HostName $Host.name -Days $Days
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $collectionPath = Join-Path -Path $directory -ChildPath 'collection.json'
    $summaryPath = Join-Path -Path $directory -ChildPath 'summary.md'
    $metaPath = Join-Path -Path $directory -ChildPath 'bundle.meta.json'

    Write-JsonFile -Path $collectionPath -Value $Collection
    (New-RemoteCollectionSummary -Collection $Collection -Host $Host) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $meta = [ordered]@{
        host_name = $Host.name
        host_address = $Host.address
        period_days = $Days
        generated_at = (Get-Date).ToString('s')
        collection_path = $collectionPath
        summary_path = $summaryPath
    }

    if ($IncludePrompt) {
        $promptPath = Join-Path -Path $directory -ChildPath 'analysis_prompt.md'
        (New-AnalysisPromptText -Collection $Collection -Host $Host) | Set-Content -LiteralPath $promptPath -Encoding UTF8
        $meta.analysis_prompt_path = $promptPath
    }

    Write-JsonFile -Path $metaPath -Value $meta

    [ordered]@{
        directory = $directory
        collection_path = $collectionPath
        summary_path = $summaryPath
        analysis_prompt_path = $(if ($IncludePrompt) { Join-Path -Path $directory -ChildPath 'analysis_prompt.md' } else { $null })
        metadata_path = $metaPath
    }
}

function Get-LatestCollectionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Days
    )

    $safeHost = ($HostName -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    $root = Join-Path -Path (Get-RemoteDiagnosticsCollectionsRoot) -ChildPath $safeHost
    if (-not (Test-Path -LiteralPath $root)) {
        return $null
    }

    Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { $_.Name -like "*-$Days-days" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}
