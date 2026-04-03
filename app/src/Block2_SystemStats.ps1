param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '2' -Title 'SystemStats' -DisplayTitle 'Блок 2. Статистика, аптайм и обзор состояния системы' -RunStamp $RunStamp
$now = Get-Date
$start24h = $now.AddHours(-24)

Add-Section -Report $report -Title 'Общий обзор состояния'
$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
$cpu = Get-CimSafe -ClassName 'Win32_Processor' | Select-Object -First 1

if ($os) {
    $bootTime = Invoke-Safely -Fallback $null -ScriptBlock { $os.LastBootUpTime }
    if ($bootTime) {
        $uptime = $now - $bootTime
        Add-KeyValue -Report $report -Key 'Время загрузки' -Value ($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))
        Add-KeyValue -Report $report -Key 'Аптайм' -Value ('{0} дн. {1} ч. {2} мин.' -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
    }

    $totalRam = [double]$os.TotalVisibleMemorySize * 1KB
    $freeRam = [double]$os.FreePhysicalMemory * 1KB
    $usedRam = $totalRam - $freeRam
    Add-KeyValue -Report $report -Key 'Память всего' -Value (Format-Bytes $totalRam)
    Add-KeyValue -Report $report -Key 'Память занято' -Value (Format-Bytes $usedRam)
    Add-KeyValue -Report $report -Key 'Память свободно' -Value (Format-Bytes $freeRam)
}
else {
    Add-ReportLine -Report $report -Text 'Сведения о времени работы системы недоступны.'
}

Add-KeyValue -Report $report -Key 'Загрузка CPU' -Value ($(if ($cpu) { '{0}%' -f $cpu.LoadPercentage } else { 'Недоступно' }))

$logicalDisks = Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3'
if ($logicalDisks) {
    Add-Section -Report $report -Title 'Использование дисков'
    foreach ($disk in $logicalDisks) {
        $used = [double]$disk.Size - [double]$disk.FreeSpace
        Add-KeyValue -Report $report -Key 'Диск' -Value (ConvertTo-FlatText $disk.DeviceID)
        Add-KeyValue -Report $report -Key 'Том' -Value (ConvertTo-FlatText $disk.VolumeName)
        Add-KeyValue -Report $report -Key 'Всего' -Value (Format-Bytes $disk.Size)
        Add-KeyValue -Report $report -Key 'Занято' -Value (Format-Bytes $used)
        Add-KeyValue -Report $report -Key 'Свободно' -Value (Format-Bytes $disk.FreeSpace)
        Add-ReportLine -Report $report -Text ('-' * 50)
    }
}

Add-Section -Report $report -Title 'Сводка событий за последние 24 часа'
$recentEvents = Get-FilteredEvents -LogNames @('System', 'Application') -StartTime $start24h -Levels @(1, 2, 3) -MaxPerLog 800
if ($recentEvents) {
    $groupedByLevel = $recentEvents | Group-Object LevelDisplayName | Sort-Object Count -Descending
    foreach ($group in $groupedByLevel) {
        Add-KeyValue -Report $report -Key ('Уровень {0}' -f $group.Name) -Value (ConvertTo-FlatText $group.Count)
    }

    Add-ReportLine -Report $report -Text ''
    Add-ReportLine -Report $report -Text 'Основные источники по количеству событий:'
    $recentEvents |
        Group-Object ProviderName |
        Sort-Object Count -Descending |
        Select-Object -First 15 |
        ForEach-Object {
            Add-ReportLine -Report $report -Text ('- {0}: {1}' -f $_.Name, $_.Count)
        }
}
else {
    Add-ReportLine -Report $report -Text 'Сводка предупреждений и ошибок из журналов System/Application недоступна.'
}

$restartShutdownEvents = Get-FilteredEvents -LogNames @('System') -StartTime $now.AddDays(-7) -Levels @(1, 2, 3, 4) -Ids @(41, 1074, 6005, 6006, 6008, 1076) -MaxPerLog 200
Add-EventSection -Report $report -Title 'История перезагрузок и завершений работы за последние 7 дней' -Events ($restartShutdownEvents | Select-Object -First 40) -EmptyText 'События перезагрузки или завершения работы не найдены.'

Add-Section -Report $report -Title 'Информация о надёжности'
$reliabilityMetrics = Get-CimSafe -Namespace 'root/cimv2' -ClassName 'Win32_ReliabilityStabilityMetrics'
if ($reliabilityMetrics) {
    $latestMetric = $reliabilityMetrics | Sort-Object TimeGenerated -Descending | Select-Object -First 1
    Add-KeyValue -Report $report -Key 'Индекс стабильности' -Value (ConvertTo-FlatText $latestMetric.SystemStabilityIndex)
    Add-KeyValue -Report $report -Key 'Время измерения' -Value (ConvertTo-FlatText $latestMetric.TimeGenerated)
}
else {
    Add-ReportLine -Report $report -Text 'Метрики стабильности недоступны.'
}

$reliabilityRecords = Get-CimSafe -Namespace 'root/cimv2' -ClassName 'Win32_ReliabilityRecords'
if ($reliabilityRecords) {
    Add-ReportLine -Report $report -Text ''
    Add-ReportLine -Report $report -Text 'Последние записи надёжности:'
    $reliabilityRecords |
        Sort-Object TimeGenerated -Descending |
        Select-Object -First 15 |
        ForEach-Object {
            Add-ReportLine -Report $report -Text ('- {0} | {1} | {2}' -f $_.TimeGenerated, $_.SourceName, $_.ProductName)
        }
}
else {
    Add-ReportLine -Report $report -Text 'Записи надёжности недоступны.'
}

Add-Section -Report $report -Title 'Количество критических событий, ошибок и предупреждений по источникам за 24 часа'
if ($recentEvents) {
    $recentEvents |
        Group-Object ProviderName, LevelDisplayName |
        Sort-Object Count -Descending |
        Select-Object -First 25 |
        ForEach-Object {
            Add-ReportLine -Report $report -Text ('- {0}: {1}' -f $_.Name, $_.Count)
        }
}
else {
    Add-ReportLine -Report $report -Text 'Подсчёт событий недоступен.'
}

Write-StatReport -Report $report | Out-Null
