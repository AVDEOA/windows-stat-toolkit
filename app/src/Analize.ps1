param(
    [string]$PeriodChoice
)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
. "$PSScriptRoot\StatToolkit.Common.ps1"

function Resolve-AnalysisRange {
    param([string]$Choice)

    switch ($Choice) {
        '1' { return [pscustomobject]@{ Label = '2_days';  StartTime = (Get-Date).AddDays(-2) } }
        '2' { return [pscustomobject]@{ Label = '7_days';  StartTime = (Get-Date).AddDays(-7) } }
        '3' { return [pscustomobject]@{ Label = '14_days'; StartTime = (Get-Date).AddDays(-14) } }
        '4' { return [pscustomobject]@{ Label = '30_days'; StartTime = (Get-Date).AddDays(-30) } }
        '5' { return [pscustomobject]@{ Label = 'all_time'; StartTime = [datetime]'2000-01-01T00:00:00' } }
        default { return $null }
    }
}

function Read-AnalysisRange {
    param([string]$InitialChoice)

    $resolved = Resolve-AnalysisRange -Choice $InitialChoice
    if ($resolved) {
        return $resolved
    }

    Write-Host ''
    Write-Host 'Выберите период для анализа:'
    Write-Host '1. За последние 2 дня'
    Write-Host '2. За 7 дней'
    Write-Host '3. За 14 дней'
    Write-Host '4. За 30 дней'
    Write-Host '5. За все время'
    Write-Host ''

    while ($true) {
        $choice = Read-Host 'Введите номер пункта'
        $resolved = Resolve-AnalysisRange -Choice $choice
        if ($resolved) {
            return $resolved
        }

        Write-Host 'Неверный выбор. Введите число от 1 до 5.'
    }
}

function Convert-EventToAnalysisObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Event,
        [Parameter(Mandatory = $true)]
        [string]$Block,
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    [pscustomobject]@{
        type = 'event'
        block = $Block
        category = $Category
        timestamp = (Invoke-Safely -Fallback $null -ScriptBlock { $Event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') })
        provider = (ConvertTo-FlatText $Event.ProviderName)
        event_id = (ConvertTo-FlatText $Event.Id)
        severity = (ConvertTo-FlatText $Event.LevelDisplayName)
        log = (ConvertTo-FlatText $Event.LogName)
        message = (Get-ShortMessage -EventRecord $Event)
    }
}

function Add-ItemsFromEvents {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter(Mandatory = $true)]
        [string]$Block,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [object[]]$Events
    )

    foreach ($event in @($Events)) {
        [void]$Target.Add((Convert-EventToAnalysisObject -Event $event -Block $Block -Category $Category))
    }
}

function Add-DataObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,
        [Parameter(Mandatory = $true)]
        [string]$Block,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [AllowNull()]
        [object]$Data
    )

    [void]$Target.Add([pscustomobject]@{
        type = 'data'
        block = $Block
        category = $Category
        data = $Data
    })
}

$selection = Read-AnalysisRange -InitialChoice $PeriodChoice
$outputRoot = Ensure-StatOutputRoot
$outputPath = Join-Path -Path $outputRoot -ChildPath 'Analize.txt'
$items = [System.Collections.Generic.List[object]]::new()
$now = Get-Date

$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
$computerSystem = Get-CimSafe -ClassName 'Win32_ComputerSystem' | Select-Object -First 1
$bios = Get-CimSafe -ClassName 'Win32_BIOS' | Select-Object -First 1
$board = Get-CimSafe -ClassName 'Win32_BaseBoard' | Select-Object -First 1
$cpuList = @(Get-CimSafe -ClassName 'Win32_Processor')
$memoryModules = @(Get-CimSafe -ClassName 'Win32_PhysicalMemory')
$gpuList = @(Get-CimSafe -ClassName 'Win32_VideoController')
$diskList = @(Get-CimSafe -ClassName 'Win32_DiskDrive')
$partitionList = @(Invoke-Safely -Fallback @() -ScriptBlock { Get-Partition | Sort-Object DiskNumber, PartitionNumber })
$networkConfigs = @(Invoke-Safely -Fallback @() -ScriptBlock { Get-NetIPConfiguration | Sort-Object InterfaceAlias })
$drivers = @()
$reliabilityMetrics = @()
$reliabilityRecords = @()
$logicalDisks = @(Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3')

Add-DataObject -Target $items -Block 'Block1' -Category 'meta' -Data ([pscustomobject]@{
    machine = $env:COMPUTERNAME
    collected_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
    selected_period = $selection.Label
    period_start = $selection.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
})

if ($os) {
    Add-DataObject -Target $items -Block 'Block1' -Category 'os' -Data ([pscustomobject]@{
        caption = $os.Caption
        version = $os.Version
        build = $os.BuildNumber
        install_date = (Invoke-Safely -Fallback $null -ScriptBlock { $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss') })
        computer_name = $os.CSName
        last_boot = (Invoke-Safely -Fallback $null -ScriptBlock { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss') })
    })
}

Add-DataObject -Target $items -Block 'Block1' -Category 'firmware' -Data ([pscustomobject]@{
    manufacturer = (ConvertTo-FlatText $computerSystem.Manufacturer)
    model = (ConvertTo-FlatText $computerSystem.Model)
    board_product = (ConvertTo-FlatText $board.Product)
    board_manufacturer = (ConvertTo-FlatText $board.Manufacturer)
    bios_version = (ConvertTo-FlatText $bios.SMBIOSBIOSVersion)
    bios_vendor = (ConvertTo-FlatText $bios.Manufacturer)
    bios_release_date = (Invoke-Safely -Fallback $null -ScriptBlock { $bios.ReleaseDate.ToString('yyyy-MM-dd HH:mm:ss') })
})

Add-DataObject -Target $items -Block 'Block1' -Category 'cpu' -Data ($cpuList | ForEach-Object {
    [pscustomobject]@{
        name = $_.Name
        socket = $_.SocketDesignation
        cores = $_.NumberOfCores
        logical_processors = $_.NumberOfLogicalProcessors
        current_clock_mhz = $_.CurrentClockSpeed
        load_percentage = $_.LoadPercentage
        virtualization_firmware_enabled = $_.VirtualizationFirmwareEnabled
        slat = $_.SecondLevelAddressTranslationExtensions
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'memory_modules' -Data ($memoryModules | ForEach-Object {
    [pscustomobject]@{
        slot = $_.DeviceLocator
        capacity_bytes = $_.Capacity
        speed_mhz = $_.Speed
        manufacturer = $_.Manufacturer
        part_number = $_.PartNumber
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'gpu' -Data ($gpuList | ForEach-Object {
    [pscustomobject]@{
        name = $_.Name
        driver_version = $_.DriverVersion
        driver_date = (Invoke-Safely -Fallback $null -ScriptBlock { $_.DriverDate.ToString('yyyy-MM-dd HH:mm:ss') })
        adapter_ram = $_.AdapterRAM
        video_processor = $_.VideoProcessor
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'disks' -Data ($diskList | ForEach-Object {
    [pscustomobject]@{
        model = $_.Model
        interface = $_.InterfaceType
        size_bytes = $_.Size
        status = $_.Status
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'partitions' -Data ($partitionList | ForEach-Object {
    [pscustomobject]@{
        disk_number = $_.DiskNumber
        partition_number = $_.PartitionNumber
        drive_letter = $_.DriveLetter
        size_bytes = $_.Size
        type = $_.Type
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'network' -Data ($networkConfigs | ForEach-Object {
    [pscustomobject]@{
        adapter = $_.InterfaceAlias
        ipv4 = @($_.IPv4Address | ForEach-Object { $_.IPAddress })
        ipv6 = @($_.IPv6Address | ForEach-Object { $_.IPAddress })
        gateway = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
        dns = @($_.DnsServer.ServerAddresses)
    }
})

Add-DataObject -Target $items -Block 'Block1' -Category 'drivers_sample' -Data (($drivers | Sort-Object DriverDate -Descending | Select-Object -First 20) | ForEach-Object {
    [pscustomobject]@{
        device_name = $_.DeviceName
        driver_version = $_.DriverVersion
        provider = $_.DriverProviderName
        driver_date = $_.DriverDate
    }
})

$featureNames = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Hyper-V',
    'VirtualMachinePlatform',
    'Microsoft-Windows-Subsystem-Linux',
    'HypervisorPlatform',
    'Containers'
)

$featureStates = Invoke-Safely -Fallback @() -ScriptBlock {
    foreach ($name in $featureNames) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
        [pscustomobject]@{
            name = $feature.FeatureName
            state = $feature.State
        }
    }
}
Add-DataObject -Target $items -Block 'Block1' -Category 'virtualization_features' -Data $featureStates

if ($os) {
    $bootTime = Invoke-Safely -Fallback $null -ScriptBlock { $os.LastBootUpTime }
    $totalRam = [double]$os.TotalVisibleMemorySize * 1KB
    $freeRam = [double]$os.FreePhysicalMemory * 1KB
    $usedRam = $totalRam - $freeRam
    Add-DataObject -Target $items -Block 'Block2' -Category 'runtime' -Data ([pscustomobject]@{
        boot_time = (Invoke-Safely -Fallback $null -ScriptBlock { $bootTime.ToString('yyyy-MM-dd HH:mm:ss') })
        uptime = $(if ($bootTime) { ($now - $bootTime).ToString() } else { $null })
        memory_total_bytes = $totalRam
        memory_used_bytes = $usedRam
        memory_free_bytes = $freeRam
    })
}

Add-DataObject -Target $items -Block 'Block2' -Category 'disk_usage' -Data ($logicalDisks | ForEach-Object {
    [pscustomobject]@{
        drive = $_.DeviceID
        volume = $_.VolumeName
        total_bytes = $_.Size
        free_bytes = $_.FreeSpace
        used_bytes = ([double]$_.Size - [double]$_.FreeSpace)
    }
})

$block2Events = @(Get-FilteredEvents -LogNames @('System', 'Application') -StartTime $selection.StartTime -Levels @(1, 2, 3) -MaxPerLog 1200)
 $block2Summary = @($block2Events | ForEach-Object {
    [pscustomobject]@{
        level = (Invoke-Safely -Fallback 'Unknown' -ScriptBlock { [string]$_.LevelDisplayName })
        provider = (Invoke-Safely -Fallback 'Unknown' -ScriptBlock { [string]$_.ProviderName })
    }
})
Add-DataObject -Target $items -Block 'Block2' -Category 'event_summary' -Data ([pscustomobject]@{
    by_level = @($block2Summary | Group-Object level | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; count = $_.Count }
    })
    by_provider = @($block2Summary | Group-Object provider | Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object {
        [pscustomobject]@{ name = $_.Name; count = $_.Count }
    })
})

Add-ItemsFromEvents -Target $items -Block 'Block2' -Category 'restart_shutdown_history' -Events (@(Get-FilteredEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -Ids @(41, 1074, 6005, 6006, 6008, 1076, 109) -MaxPerLog 300) | Select-Object -First 80)

Add-DataObject -Target $items -Block 'Block2' -Category 'reliability_metrics' -Data ($reliabilityMetrics | Sort-Object TimeGenerated -Descending | Select-Object -First 20 | ForEach-Object {
    [pscustomobject]@{
        generated = $_.TimeGenerated
        stability_index = $_.SystemStabilityIndex
    }
})

Add-DataObject -Target $items -Block 'Block2' -Category 'reliability_records' -Data ($reliabilityRecords | Sort-Object TimeGenerated -Descending | Select-Object -First 20 | ForEach-Object {
    [pscustomobject]@{
        generated = $_.TimeGenerated
        source = $_.SourceName
        product = $_.ProductName
        event_identifier = $_.EventIdentifier
    }
})

Add-ItemsFromEvents -Target $items -Block 'Block3' -Category 'general_driver_errors' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)\bdriver\b') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block3' -Category 'device_initialization_failures' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MessagePatterns @('(?i)(device|driver).*(failed|failure|not started|problem|unable|could not|did not load)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block3' -Category 'driver_install_update_issues' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*UserPnp*', '*DeviceSetupManager*', '*SetupAPI*') -MessagePatterns @('(?i)(install|update|package|migration|driver package|rollback)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block3' -Category 'kernel_pnp' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MaxPerLog 250) | Select-Object -First 60)

Add-ItemsFromEvents -Target $items -Block 'Block4' -Category 'display' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Display', '*Display*') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block4' -Category 'nvidia' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('nvlddmkm', '*NVIDIA*') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block4' -Category 'amd' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('amdkmdag', 'amdwddmg', '*AMD*') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block4' -Category 'directx_dxgkrnl' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*DxgKrnl*', '*DirectX*') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block4' -Category 'tdr_timeout' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(TDR|timeout detection|display driver stopped responding|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)') -MaxPerLog 250) | Select-Object -First 60)

Add-ItemsFromEvents -Target $items -Block 'Block5' -Category 'whea' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*WHEA*') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block5' -Category 'pcie' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(PCI Express|PCIe|PCI)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block5' -Category 'bus_interconnect' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(bus error|interconnect|fabric|link failure|link degraded)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block5' -Category 'hardware_corrected_uncorrected' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)') -MaxPerLog 250) | Select-Object -First 60)

Add-ItemsFromEvents -Target $items -Block 'Block6' -Category 'bugcheck_bsod' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*BugCheck*', '*WER-SystemErrorReporting*', '*Windows Error Reporting*') -MessagePatterns @('(?i)(bugcheck|blue screen|stop code)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block6' -Category 'kernel_power' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -ProviderPatterns @('*Kernel-Power*') -Ids @(41, 109) -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block6' -Category 'unexpected_shutdown' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -Ids @(6008, 1074, 1076) -MaxPerLog 250) | Select-Object -First 60)

$memoryDump = 'C:\Windows\MEMORY.DMP'
$miniDumpDir = 'C:\Windows\Minidump'
Add-DataObject -Target $items -Block 'Block6' -Category 'dump_status' -Data ([pscustomobject]@{
    memory_dump_exists = (Test-Path $memoryDump)
    minidump_dir_exists = (Test-Path $miniDumpDir)
    minidumps = @(
        if (Test-Path $miniDumpDir) {
            Get-ChildItem -Path $miniDumpDir -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 30 |
                ForEach-Object {
                    [pscustomobject]@{
                        name = $_.Name
                        last_write = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                        size_bytes = $_.Length
                    }
                }
        }
    )
})

Add-ItemsFromEvents -Target $items -Block 'Block6' -Category 'live_kernel' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(LiveKernelEvent|live kernel)') -MaxPerLog 250) | Select-Object -First 60)

Add-ItemsFromEvents -Target $items -Block 'Block7' -Category 'storage' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('disk', 'storahci', 'stornvme', 'iaStorA', 'iaStorV', 'volmgr', 'partmgr') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block7' -Category 'filesystem' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Ntfs', 'ReFS', 'Wininit', 'Chkdsk') -MessagePatterns @('(?i)(corrupt|corruption|bad block|file system|dirty bit|volume)') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block7' -Category 'services' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Service Control Manager') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block7' -Category 'defender' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Windows Defender*', 'WinDefend') -MaxPerLog 250) | Select-Object -First 60)
Add-ItemsFromEvents -Target $items -Block 'Block7' -Category 'windows_update' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*WindowsUpdateClient*') -MaxPerLog 250) | Select-Object -First 60)

$items |
    ConvertTo-Json -Depth 8 |
    Set-Content -Path $outputPath -Encoding UTF8

Write-Host ''
Write-Host ('Файл анализа создан: {0}' -f $outputPath)
Write-Host ('Количество объектов: {0}' -f $items.Count)
