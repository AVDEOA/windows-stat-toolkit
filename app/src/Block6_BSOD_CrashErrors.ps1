param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '6' -Title 'BSOD_CrashErrors' -DisplayTitle 'Блок 6. BSOD, падения системы и дампы' -RunStamp $RunStamp
$start = (Get-Date).AddDays(-30)

$bugCheckEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*BugCheck*', '*WER-SystemErrorReporting*', '*Windows Error Reporting*') -MessagePatterns @('(?i)(bugcheck|blue screen|stop code)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'События BugCheck / BSOD' -Events $bugCheckEvents -EmptyText 'События BugCheck или BSOD не найдены.'

$kernelPowerEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3, 4) -ProviderPatterns @('*Kernel-Power*') -Ids @(41, 109) -MaxPerLog 300 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Критические события Kernel-Power' -Events $kernelPowerEvents -EmptyText 'Критические события Kernel-Power не найдены.'

$unexpectedShutdownEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3, 4) -Ids @(6008, 1074, 1076) -MaxPerLog 300 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Неожиданные выключения и перезапуски' -Events $unexpectedShutdownEvents -EmptyText 'Неожиданные выключения или перезапуски не найдены.'

Add-Section -Report $report -Title 'Состояние файлов дампа'
$memoryDump = 'C:\Windows\MEMORY.DMP'
$miniDumpDir = 'C:\Windows\Minidump'
Add-KeyValue -Report $report -Key 'Файл MEMORY.DMP существует' -Value ($(if (Test-Path $memoryDump) { 'Да' } else { 'Нет' }))
Add-KeyValue -Report $report -Key 'Папка Minidump существует' -Value ($(if (Test-Path $miniDumpDir) { 'Да' } else { 'Нет' }))
if (Test-Path $miniDumpDir) {
    $dumpFiles = Invoke-Safely -Fallback @() -ScriptBlock { Get-ChildItem -Path $miniDumpDir -File | Sort-Object LastWriteTime -Descending }
    Add-KeyValue -Report $report -Key 'Количество файлов Minidump' -Value (ConvertTo-FlatText $dumpFiles.Count)
    foreach ($dumpFile in ($dumpFiles | Select-Object -First 10)) {
        Add-ReportLine -Report $report -Text ('- {0} | {1} | {2}' -f $dumpFile.Name, $dumpFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), (Format-Bytes $dumpFile.Length))
    }
}

$liveKernelEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)(LiveKernelEvent|live kernel)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Записи Live Kernel Event' -Events $liveKernelEvents -EmptyText 'Записи Live Kernel Event не найдены.'

Write-StatReport -Report $report | Out-Null
