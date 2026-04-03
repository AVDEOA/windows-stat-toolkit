$ErrorActionPreference = 'Stop'

$ReportPath = Join-Path -Path (Get-Location) -ChildPath 'windows-system-report.txt'
$ReportLines = New-Object System.Collections.Generic.List[string]

function Add-ReportLine {
    param(
        [AllowEmptyString()]
        [string]$Text = ''
    )

    $ReportLines.Add($Text) | Out-Null
}

function Add-Section {
    param([string]$Title)

    Add-ReportLine ''
    Add-ReportLine ('=' * 78)
    Add-ReportLine $Title
    Add-ReportLine ('=' * 78)
}

function Invoke-Safely {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [string]$Fallback = 'Unavailable'
    )

    try {
        & $ScriptBlock
    }
    catch {
        $Fallback
    }
}

function Format-Bytes {
    param([Nullable[double]]$Bytes)

    if ($null -eq $Bytes) {
        return 'Unavailable'
    }

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $value = [double]$Bytes
    $index = 0

    while ($value -ge 1024 -and $index -lt ($units.Count - 1)) {
        $value = $value / 1024
        $index++
    }

    '{0:N2} {1}' -f $value, $units[$index]
}

function Add-KeyValue {
    param(
        [string]$Key,
        [string]$Value
    )

    Add-ReportLine ('{0,-28}: {1}' -f $Key, $Value)
}

function Add-ObjectLines {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,
        [string[]]$Properties
    )

    if (-not $Items -or $Items.Count -eq 0) {
        Add-ReportLine 'No data available.'
        return
    }

    foreach ($item in $Items) {
        foreach ($property in $Properties) {
            $value = Invoke-Safely -ScriptBlock { $item.$property } -Fallback 'Unavailable'
            Add-ReportLine ('{0,-20}: {1}' -f $property, $value)
        }

        Add-ReportLine ('-' * 40)
    }
}

Add-ReportLine 'Windows System Diagnostics Report'
Add-ReportLine ("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Add-ReportLine ("Computer: {0}" -f $env:COMPUTERNAME)
Add-ReportLine ("Report File: {0}" -f $ReportPath)
Add-ReportLine 'Note: This script collects diagnostics only and does not change the system.'

Add-Section 'Operating System'
$os = Invoke-Safely -ScriptBlock { Get-CimInstance -ClassName Win32_OperatingSystem } -Fallback $null
if ($null -ne $os) {
    $lastBoot = Invoke-Safely -ScriptBlock { [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime) } -Fallback $null
    $uptime = if ($null -ne $lastBoot) {
        $span = (Get-Date) - $lastBoot
        '{0} days {1} hours {2} minutes' -f $span.Days, $span.Hours, $span.Minutes
    }
    else {
        'Unavailable'
    }

    Add-KeyValue -Key 'Windows Version' -Value ("{0}" -f $os.Caption)
    Add-KeyValue -Key 'Version' -Value ("{0}" -f $os.Version)
    Add-KeyValue -Key 'Build' -Value ("{0}" -f $os.BuildNumber)
    Add-KeyValue -Key 'Computer Name' -Value ("{0}" -f $os.CSName)
    Add-KeyValue -Key 'Last Boot Time' -Value ($(if ($lastBoot) { $lastBoot.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Unavailable' }))
    Add-KeyValue -Key 'Uptime' -Value $uptime
}
else {
    Add-ReportLine 'Operating system information unavailable.'
}

Add-Section 'CPU'
$cpu = Invoke-Safely -ScriptBlock { Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 } -Fallback $null
if ($null -ne $cpu) {
    Add-KeyValue -Key 'CPU Model' -Value ("{0}" -f $cpu.Name)
    Add-KeyValue -Key 'Logical Cores' -Value ("{0}" -f $cpu.NumberOfLogicalProcessors)
    Add-KeyValue -Key 'CPU Load' -Value ("{0}%" -f $cpu.LoadPercentage)
}
else {
    Add-ReportLine 'CPU information unavailable.'
}

Add-Section 'Memory'
if ($null -ne $os) {
    $totalMemory = [double]$os.TotalVisibleMemorySize * 1KB
    $freeMemory = [double]$os.FreePhysicalMemory * 1KB
    $usedMemory = $totalMemory - $freeMemory

    Add-KeyValue -Key 'RAM Total' -Value (Format-Bytes -Bytes $totalMemory)
    Add-KeyValue -Key 'RAM Used' -Value (Format-Bytes -Bytes $usedMemory)
    Add-KeyValue -Key 'RAM Free' -Value (Format-Bytes -Bytes $freeMemory)
}
else {
    Add-ReportLine 'Memory information unavailable.'
}

Add-Section 'Disk C:'
$diskC = Invoke-Safely -ScriptBlock { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" } -Fallback $null
if ($null -ne $diskC) {
    $diskUsed = [double]$diskC.Size - [double]$diskC.FreeSpace
    Add-KeyValue -Key 'Total' -Value (Format-Bytes -Bytes $diskC.Size)
    Add-KeyValue -Key 'Used' -Value (Format-Bytes -Bytes $diskUsed)
    Add-KeyValue -Key 'Free' -Value (Format-Bytes -Bytes $diskC.FreeSpace)
}
else {
    Add-ReportLine 'Drive C: information unavailable.'
}

Add-Section 'Physical Disks'
$physicalDisks = Invoke-Safely -ScriptBlock {
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size, HealthStatus, OperationalStatus
} -Fallback $null

if ($physicalDisks) {
    foreach ($disk in $physicalDisks) {
        Add-KeyValue -Key 'Name' -Value ("{0}" -f $disk.FriendlyName)
        Add-KeyValue -Key 'Media Type' -Value ("{0}" -f $disk.MediaType)
        Add-KeyValue -Key 'Size' -Value (Format-Bytes -Bytes $disk.Size)
        Add-KeyValue -Key 'Health' -Value ("{0}" -f $disk.HealthStatus)
        Add-KeyValue -Key 'Operational' -Value ("{0}" -f $disk.OperationalStatus)
        Add-ReportLine ('-' * 40)
    }
}
else {
    $legacyDisks = Invoke-Safely -ScriptBlock {
        Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, InterfaceType, Size, Status
    } -Fallback $null

    if ($legacyDisks) {
        foreach ($disk in $legacyDisks) {
            Add-KeyValue -Key 'Model' -Value ("{0}" -f $disk.Model)
            Add-KeyValue -Key 'Interface' -Value ("{0}" -f $disk.InterfaceType)
            Add-KeyValue -Key 'Size' -Value (Format-Bytes -Bytes $disk.Size)
            Add-KeyValue -Key 'Status' -Value ("{0}" -f $disk.Status)
            Add-ReportLine ('-' * 40)
        }
    }
    else {
        Add-ReportLine 'Physical disk information unavailable.'
    }
}

Add-Section 'Disk Health'
$healthReported = $false

$storageReliability = Invoke-Safely -ScriptBlock {
    Get-PhysicalDisk | ForEach-Object {
        $reliability = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction Stop
        [PSCustomObject]@{
            Disk             = $_.FriendlyName
            HealthStatus     = $_.HealthStatus
            TemperatureC     = $reliability.Temperature
            ReadErrorsTotal  = $reliability.ReadErrorsTotal
            WriteErrorsTotal = $reliability.WriteErrorsTotal
            PowerOnHours     = $reliability.PowerOnHours
        }
    }
} -Fallback $null

if ($storageReliability) {
    foreach ($item in $storageReliability) {
        Add-KeyValue -Key 'Disk' -Value ("{0}" -f $item.Disk)
        Add-KeyValue -Key 'Health' -Value ("{0}" -f $item.HealthStatus)
        Add-KeyValue -Key 'Temperature' -Value ("{0} C" -f $item.TemperatureC)
        Add-KeyValue -Key 'Read Errors' -Value ("{0}" -f $item.ReadErrorsTotal)
        Add-KeyValue -Key 'Write Errors' -Value ("{0}" -f $item.WriteErrorsTotal)
        Add-KeyValue -Key 'Power-On Hours' -Value ("{0}" -f $item.PowerOnHours)
        Add-ReportLine ('-' * 40)
    }
    $healthReported = $true
}

if (-not $healthReported) {
    $wmicStatus = Invoke-Safely -ScriptBlock {
        $wmic = Get-Command -Name wmic.exe -ErrorAction Stop
        & $wmic.Source diskdrive get Model,Status /format:list
    } -Fallback $null

    if ($wmicStatus) {
        Add-ReportLine 'Disk status from WMIC:'
        foreach ($line in $wmicStatus) {
            if ($line -match '\S') {
                Add-ReportLine $line
            }
        }
        $healthReported = $true
    }
}

if (-not $healthReported) {
    Add-ReportLine 'No built-in disk health details were available on this system.'
}

Add-Section 'Network'
$networkConfigs = Invoke-Safely -ScriptBlock {
    Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -ne 'Disconnected' }
} -Fallback $null

if ($networkConfigs) {
    foreach ($cfg in $networkConfigs) {
        Add-KeyValue -Key 'Adapter' -Value ("{0}" -f $cfg.InterfaceAlias)
        Add-KeyValue -Key 'Description' -Value ("{0}" -f $cfg.NetAdapter.InterfaceDescription)
        Add-KeyValue -Key 'Status' -Value ("{0}" -f $cfg.NetAdapter.Status)
        Add-KeyValue -Key 'IPv4' -Value ($(if ($cfg.IPv4Address) { ($cfg.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', ' } else { 'None' }))
        Add-KeyValue -Key 'IPv6' -Value ($(if ($cfg.IPv6Address) { ($cfg.IPv6Address | ForEach-Object { $_.IPAddress }) -join ', ' } else { 'None' }))
        Add-KeyValue -Key 'Default Gateway' -Value ($(if ($cfg.IPv4DefaultGateway) { $cfg.IPv4DefaultGateway.NextHop } else { 'None' }))
        Add-KeyValue -Key 'DNS' -Value ($(if ($cfg.DNSServer.ServerAddresses) { $cfg.DNSServer.ServerAddresses -join ', ' } else { 'None' }))
        Add-ReportLine ('-' * 40)
    }
}
else {
    Add-ReportLine 'Network configuration information unavailable.'
}

Add-Section 'Internet Connectivity'
$pingResult = Invoke-Safely -ScriptBlock {
    Test-Connection -ComputerName '8.8.8.8' -Count 2 -Quiet
} -Fallback $false
Add-KeyValue -Key 'Ping 8.8.8.8' -Value ($(if ($pingResult) { 'Success' } else { 'Failed or unavailable' }))

$httpsResult = Invoke-Safely -ScriptBlock {
    $response = Invoke-WebRequest -Uri 'https://www.microsoft.com' -Method Head -UseBasicParsing -TimeoutSec 15
    if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
        "Success (HTTP $($response.StatusCode))"
    }
    else {
        "Unexpected response (HTTP $($response.StatusCode))"
    }
} -Fallback 'Failed or unavailable'
Add-KeyValue -Key 'HTTPS Request' -Value $httpsResult

Add-Section 'Windows Defender'
$defenderService = Invoke-Safely -ScriptBlock { Get-Service -Name 'WinDefend' } -Fallback $null
if ($null -ne $defenderService) {
    Add-KeyValue -Key 'Service Status' -Value ("{0}" -f $defenderService.Status)
    Add-KeyValue -Key 'Start Type' -Value ("{0}" -f $defenderService.StartType)
}
else {
    Add-ReportLine 'Windows Defender service information unavailable.'
}

$mpComputerStatus = Invoke-Safely -ScriptBlock { Get-MpComputerStatus } -Fallback $null
if ($null -ne $mpComputerStatus) {
    Add-KeyValue -Key 'Antivirus Enabled' -Value ("{0}" -f $mpComputerStatus.AntivirusEnabled)
    Add-KeyValue -Key 'Real-Time Protection' -Value ("{0}" -f $mpComputerStatus.RealTimeProtectionEnabled)
}

Add-Section 'Services'
foreach ($serviceName in @('WinDefend', 'wuauserv', 'EventLog', 'LanmanServer')) {
    $service = Invoke-Safely -ScriptBlock { Get-Service -Name $serviceName } -Fallback $null
    if ($null -ne $service) {
        Add-KeyValue -Key $serviceName -Value ("Status={0}; StartType={1}; DisplayName={2}" -f $service.Status, $service.StartType, $service.DisplayName)
    }
    else {
        Add-KeyValue -Key $serviceName -Value 'Unavailable'
    }
}

Add-Section 'Critical and Error Events (Last 24 Hours)'
$startTime = (Get-Date).AddHours(-24)
foreach ($logName in @('System', 'Application')) {
    Add-ReportLine ("Log: {0}" -f $logName)
    $events = Invoke-Safely -ScriptBlock {
        Get-WinEvent -FilterHashtable @{
            LogName   = $logName
            StartTime = $startTime
            Level     = 1, 2
        } -MaxEvents 25 |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message
    } -Fallback $null

    if ($events) {
        foreach ($event in $events) {
            Add-ReportLine ('[{0}] ID {1} {2} - {3}' -f $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $event.Id, $event.LevelDisplayName, $event.ProviderName)
            $message = if ($event.Message) {
                ($event.Message -replace '\s+', ' ').Trim()
            }
            else {
                'No message.'
            }
            Add-ReportLine ("  {0}" -f $message)
        }
    }
    else {
        Add-ReportLine 'No critical or error events found, or log access unavailable.'
    }

    Add-ReportLine ('-' * 40)
}

try {
    $ReportLines | Tee-Object -FilePath $ReportPath
}
catch {
    $ReportLines | ForEach-Object { Write-Output $_ }
    Write-Warning ("Could not write report file: {0}" -f $_.Exception.Message)
}
