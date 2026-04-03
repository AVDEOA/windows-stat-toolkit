param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '5' -Title 'WHEA_PCI_Errors' -DisplayTitle 'Блок 5. Ошибки WHEA, PCIe и аппаратной стабильности' -RunStamp $RunStamp
$start = (Get-Date).AddDays(-30)

$wheaEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*WHEA*') -MaxPerLog 400 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'События WHEA-Logger' -Events $wheaEvents -EmptyText 'События WHEA не найдены.'

$pcieEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)(PCI Express|PCIe|PCI)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'События PCI Express / PCIe' -Events $pcieEvents -EmptyText 'События, связанные с PCIe, не найдены.'

$busInterconnectEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)(bus error|interconnect|fabric|link failure|link degraded)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Проблемы шины и межсоединений' -Events $busInterconnectEvents -EmptyText 'Проблемы шины или межсоединений не найдены.'

$correctedEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)(corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'Исправленные и неисправленные аппаратные ошибки' -Events $correctedEvents -EmptyText 'Исправленные или неисправленные аппаратные ошибки не найдены.'

Write-StatReport -Report $report | Out-Null
