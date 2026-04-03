param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '1' -Title 'SystemInfo' -DisplayTitle 'Блок 1. Общая информация о системе' -RunStamp $RunStamp

Add-Section -Report $report -Title 'Операционная система'
$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
if ($os) {
    Add-KeyValue -Report $report -Key 'Название ОС' -Value (ConvertTo-FlatText $os.Caption)
    Add-KeyValue -Report $report -Key 'Версия' -Value (ConvertTo-FlatText $os.Version)
    Add-KeyValue -Report $report -Key 'Сборка' -Value (ConvertTo-FlatText $os.BuildNumber)
    Add-KeyValue -Report $report -Key 'Дата установки' -Value (Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss') })
    Add-KeyValue -Report $report -Key 'Имя компьютера' -Value (ConvertTo-FlatText $os.CSName)
}
else {
    Add-ReportLine -Report $report -Text 'Информация об операционной системе недоступна.'
}

Add-Section -Report $report -Title 'Материнская плата / BIOS / прошивка'
$board = Get-CimSafe -ClassName 'Win32_BaseBoard' | Select-Object -First 1
$bios = Get-CimSafe -ClassName 'Win32_BIOS' | Select-Object -First 1
$computerSystem = Get-CimSafe -ClassName 'Win32_ComputerSystem' | Select-Object -First 1
$computerInfo = Invoke-Safely -Fallback $null -ScriptBlock { Get-ComputerInfo }

Add-KeyValue -Report $report -Key 'Производитель' -Value (ConvertTo-FlatText $computerSystem.Manufacturer)
Add-KeyValue -Report $report -Key 'Модель' -Value (ConvertTo-FlatText $computerSystem.Model)
Add-KeyValue -Report $report -Key 'Материнская плата' -Value (ConvertTo-FlatText $board.Product)
Add-KeyValue -Report $report -Key 'Производитель платы' -Value (ConvertTo-FlatText $board.Manufacturer)
Add-KeyValue -Report $report -Key 'Версия BIOS' -Value (ConvertTo-FlatText $bios.SMBIOSBIOSVersion)
Add-KeyValue -Report $report -Key 'Производитель BIOS' -Value (ConvertTo-FlatText $bios.Manufacturer)
Add-KeyValue -Report $report -Key 'Дата BIOS' -Value (Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { $bios.ReleaseDate.ToString('yyyy-MM-dd HH:mm:ss') })
Add-KeyValue -Report $report -Key 'Тип прошивки' -Value (ConvertTo-FlatText $computerInfo.BiosFirmwareType)

Add-Section -Report $report -Title 'Процессор и топология'
$cpuList = Get-CimSafe -ClassName 'Win32_Processor'
if ($cpuList) {
    foreach ($cpu in $cpuList) {
        Add-KeyValue -Report $report -Key 'Модель CPU' -Value (ConvertTo-FlatText $cpu.Name)
        Add-KeyValue -Report $report -Key 'Сокет' -Value (ConvertTo-FlatText $cpu.SocketDesignation)
        Add-KeyValue -Report $report -Key 'Физические ядра' -Value (ConvertTo-FlatText $cpu.NumberOfCores)
        Add-KeyValue -Report $report -Key 'Логические процессоры' -Value (ConvertTo-FlatText $cpu.NumberOfLogicalProcessors)
        Add-KeyValue -Report $report -Key 'Текущая частота МГц' -Value (ConvertTo-FlatText $cpu.CurrentClockSpeed)
        Add-KeyValue -Report $report -Key 'Виртуализация в прошивке' -Value (ConvertTo-FlatText $cpu.VirtualizationFirmwareEnabled)
        Add-KeyValue -Report $report -Key 'SLAT' -Value (ConvertTo-FlatText $cpu.SecondLevelAddressTranslationExtensions)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Сведения о процессоре недоступны.'
}

Add-Section -Report $report -Title 'Модули памяти и общий объём ОЗУ'
$memoryModules = Get-CimSafe -ClassName 'Win32_PhysicalMemory'
if ($memoryModules) {
    $totalMemory = 0
    foreach ($module in $memoryModules) {
        $totalMemory += [double]$module.Capacity
        Add-KeyValue -Report $report -Key 'Слот' -Value (ConvertTo-FlatText $module.DeviceLocator)
        Add-KeyValue -Report $report -Key 'Объём' -Value (Format-Bytes $module.Capacity)
        Add-KeyValue -Report $report -Key 'Скорость' -Value ("{0} МГц" -f (ConvertTo-FlatText $module.Speed))
        Add-KeyValue -Report $report -Key 'Производитель' -Value (ConvertTo-FlatText $module.Manufacturer)
        Add-KeyValue -Report $report -Key 'Номер детали' -Value (ConvertTo-FlatText $module.PartNumber)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
    Add-KeyValue -Report $report -Key 'Общий объём физической памяти' -Value (Format-Bytes $totalMemory)
}
else {
    Add-ReportLine -Report $report -Text 'Сведения о модулях памяти недоступны.'
}

Add-Section -Report $report -Title 'Список GPU'
$gpus = Get-CimSafe -ClassName 'Win32_VideoController'
if ($gpus) {
    foreach ($gpu in $gpus) {
        Add-KeyValue -Report $report -Key 'Название' -Value (ConvertTo-FlatText $gpu.Name)
        Add-KeyValue -Report $report -Key 'Версия драйвера' -Value (ConvertTo-FlatText $gpu.DriverVersion)
        Add-KeyValue -Report $report -Key 'Дата драйвера' -Value (Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { $gpu.DriverDate.ToString('yyyy-MM-dd HH:mm:ss') })
        Add-KeyValue -Report $report -Key 'Память адаптера' -Value (Format-Bytes $gpu.AdapterRAM)
        Add-KeyValue -Report $report -Key 'Видеопроцессор' -Value (ConvertTo-FlatText $gpu.VideoProcessor)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Информация о GPU недоступна.'
}

Add-Section -Report $report -Title 'Диски и разделы'
$diskDrives = Get-CimSafe -ClassName 'Win32_DiskDrive'
if ($diskDrives) {
    foreach ($disk in $diskDrives) {
        Add-KeyValue -Report $report -Key 'Модель диска' -Value (ConvertTo-FlatText $disk.Model)
        Add-KeyValue -Report $report -Key 'Интерфейс' -Value (ConvertTo-FlatText $disk.InterfaceType)
        Add-KeyValue -Report $report -Key 'Размер' -Value (Format-Bytes $disk.Size)
        Add-KeyValue -Report $report -Key 'Статус' -Value (ConvertTo-FlatText $disk.Status)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Сведения о физических дисках недоступны.'
}

$partitions = Invoke-Safely -Fallback $null -ScriptBlock { Get-Partition | Sort-Object DiskNumber, PartitionNumber }
if ($partitions) {
    Add-Section -Report $report -Title 'Разделы'
    foreach ($partition in $partitions) {
        Add-KeyValue -Report $report -Key 'Диск / раздел' -Value ('{0} / {1}' -f $partition.DiskNumber, $partition.PartitionNumber)
        Add-KeyValue -Report $report -Key 'Буква диска' -Value (ConvertTo-FlatText $partition.DriveLetter)
        Add-KeyValue -Report $report -Key 'Размер' -Value (Format-Bytes $partition.Size)
        Add-KeyValue -Report $report -Key 'Тип' -Value (ConvertTo-FlatText $partition.Type)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}

Add-Section -Report $report -Title 'Сетевые адаптеры'
$netAdapters = Invoke-Safely -Fallback $null -ScriptBlock { Get-NetAdapter | Sort-Object Name }
if (-not $netAdapters) {
    $netAdapters = Get-CimSafe -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter = True'
}

if ($netAdapters) {
    foreach ($adapter in $netAdapters) {
        Add-KeyValue -Report $report -Key 'Имя' -Value (ConvertTo-FlatText $adapter.Name)
        Add-KeyValue -Report $report -Key 'Описание интерфейса' -Value (ConvertTo-FlatText $adapter.InterfaceDescription)
        Add-KeyValue -Report $report -Key 'MAC-адрес' -Value (ConvertTo-FlatText $adapter.MacAddress)
        Add-KeyValue -Report $report -Key 'Статус' -Value (ConvertTo-FlatText $adapter.Status)
        Add-KeyValue -Report $report -Key 'Скорость линка' -Value (ConvertTo-FlatText $adapter.LinkSpeed)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Сведения о сетевых адаптерах недоступны.'
}

Add-Section -Report $report -Title 'IP-адреса и DNS'
$netConfigs = Invoke-Safely -Fallback $null -ScriptBlock { Get-NetIPConfiguration | Sort-Object InterfaceAlias }
if ($netConfigs) {
    foreach ($cfg in $netConfigs) {
        Add-KeyValue -Report $report -Key 'Адаптер' -Value (ConvertTo-FlatText $cfg.InterfaceAlias)
        Add-KeyValue -Report $report -Key 'IPv4' -Value (ConvertTo-FlatText ($cfg.IPv4Address | ForEach-Object { $_.IPAddress }))
        Add-KeyValue -Report $report -Key 'IPv6' -Value (ConvertTo-FlatText ($cfg.IPv6Address | ForEach-Object { $_.IPAddress }))
        Add-KeyValue -Report $report -Key 'Шлюз' -Value (ConvertTo-FlatText ($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }))
        Add-KeyValue -Report $report -Key 'DNS' -Value (ConvertTo-FlatText $cfg.DNSServer.ServerAddresses)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    $legacyConfig = Get-CimSafe -ClassName 'Win32_NetworkAdapterConfiguration' -Filter 'IPEnabled = True'
    if ($legacyConfig) {
        foreach ($cfg in $legacyConfig) {
            Add-KeyValue -Report $report -Key 'Описание' -Value (ConvertTo-FlatText $cfg.Description)
            Add-KeyValue -Report $report -Key 'IP-адрес' -Value (ConvertTo-FlatText $cfg.IPAddress)
            Add-KeyValue -Report $report -Key 'Шлюз' -Value (ConvertTo-FlatText $cfg.DefaultIPGateway)
            Add-KeyValue -Report $report -Key 'DNS' -Value (ConvertTo-FlatText $cfg.DNSServerSearchOrder)
            Add-ReportLine -Report $report -Text ('-' * 50)
        }
    }
    else {
        Add-ReportLine -Report $report -Text 'Сведения о сетевой конфигурации недоступны.'
    }
}

Add-Section -Report $report -Title 'Краткая сводка по установленным драйверам'
$driverSummary = Get-CimSafe -ClassName 'Win32_PnPSignedDriver'
if ($driverSummary) {
    $topDrivers = $driverSummary |
        Sort-Object DriverDate -Descending |
        Select-Object -First 25

    Add-KeyValue -Report $report -Key 'Количество записей в выборке' -Value (ConvertTo-FlatText $topDrivers.Count)
    foreach ($driver in $topDrivers) {
        Add-KeyValue -Report $report -Key 'Устройство' -Value (ConvertTo-FlatText $driver.DeviceName)
        Add-KeyValue -Report $report -Key 'Версия' -Value (ConvertTo-FlatText $driver.DriverVersion)
        Add-KeyValue -Report $report -Key 'Поставщик' -Value (ConvertTo-FlatText $driver.DriverProviderName)
        Add-KeyValue -Report $report -Key 'Дата' -Value (ConvertTo-FlatText $driver.DriverDate)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Сводка по установленным драйверам недоступна.'
}

Add-Section -Report $report -Title 'Функции виртуализации / Hyper-V / WSL'
Add-KeyValue -Report $report -Key 'Гипервизор присутствует' -Value (ConvertTo-FlatText $computerSystem.HypervisorPresent)

$featureNames = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Hyper-V',
    'VirtualMachinePlatform',
    'Microsoft-Windows-Subsystem-Linux',
    'HypervisorPlatform',
    'Containers'
)

$optionalFeatures = Invoke-Safely -Fallback $null -ScriptBlock {
    foreach ($name in $featureNames) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
        [pscustomobject]@{
            FeatureName = $feature.FeatureName
            State       = $feature.State
        }
    }
}

if ($optionalFeatures) {
    foreach ($feature in $optionalFeatures) {
        Add-KeyValue -Report $report -Key $feature.FeatureName -Value (ConvertTo-FlatText $feature.State)
    }
}
else {
    Add-ReportLine -Report $report -Text 'Статус компонентов Windows недоступен или требует другой редакции Windows.'
}

Write-StatReport -Report $report | Out-Null
