param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '7' -Title 'AdditionalCriticalErrors' -DisplayTitle 'Блок 7. Дополнительные критические категории стабильности' -RunStamp $RunStamp
$start = (Get-Date).AddDays(-14)

$storageEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('disk', 'storahci', 'stornvme', 'iaStorA', 'iaStorV', 'volmgr', 'partmgr') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Ошибки диска, контроллера и подсистемы хранения' -Events $storageEvents -EmptyText 'Предупреждения или ошибки подсистемы хранения не найдены.'

$filesystemEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('Ntfs', 'ReFS', 'Wininit', 'Chkdsk') -MessagePatterns @('(?i)(corrupt|corruption|bad block|file system|dirty bit|volume)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Признаки повреждения файловой системы' -Events $filesystemEvents -EmptyText 'Признаки повреждения файловой системы не найдены.'

$serviceEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('Service Control Manager') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Сбои служб' -Events $serviceEvents -EmptyText 'Недавние сбои служб не найдены.'

$defenderEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*Windows Defender*', 'WinDefend') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Сбои Windows Defender и связанных служб безопасности' -Events $defenderEvents -EmptyText 'Подходящие предупреждения или ошибки Windows Defender не найдены.'

$updateEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*WindowsUpdateClient*') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Сбои Windows Update' -Events $updateEvents -EmptyText 'Предупреждения или ошибки Windows Update не найдены.'

Write-StatReport -Report $report | Out-Null
