param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '3' -Title 'DriverErrors' -DisplayTitle 'Блок 3. Ошибки драйверов и инициализации устройств' -RunStamp $RunStamp
$start = (Get-Date).AddDays(-14)

$generalDriverErrors = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)\bdriver\b') -MaxPerLog 500 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'Общие ошибки драйверов за последние 14 дней' -Events $generalDriverErrors -EmptyText 'Общие предупреждения или ошибки драйверов не найдены.'

$deviceInitFailures = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MessagePatterns @('(?i)(device|driver).*(failed|failure|not started|problem|unable|could not|did not load)') -MaxPerLog 500 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'Сбои инициализации устройств' -Events $deviceInitFailures -EmptyText 'Сбои инициализации устройств не найдены.'

$driverInstallIssues = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*UserPnp*', '*DeviceSetupManager*', '*SetupAPI*') -MessagePatterns @('(?i)(install|update|package|migration|driver package|rollback)') -MaxPerLog 500 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'Проблемы установки и обновления драйверов' -Events $driverInstallIssues -EmptyText 'Проблемы установки или обновления драйверов не найдены.'

$pnpErrors = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MaxPerLog 500 |
    Select-Object -First 60
Add-EventSection -Report $report -Title 'События Plug and Play / Kernel-PnP' -Events $pnpErrors -EmptyText 'Проблемы Plug and Play или Kernel-PnP не найдены.'

Write-StatReport -Report $report | Out-Null
