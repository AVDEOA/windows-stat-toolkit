param(
    [string]$RunStamp
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$report = New-StatReport -BlockNumber '4' -Title 'GPU_Errors' -DisplayTitle 'Блок 4. Ошибки видеодрайвера и GPU' -RunStamp $RunStamp
$start = (Get-Date).AddDays(-14)

$displayEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('Display', '*Display*') -MaxPerLog 400 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'События источника Display' -Events $displayEvents -EmptyText 'Предупреждения или ошибки источника Display не найдены.'

$nvidiaEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('nvlddmkm', '*NVIDIA*') -MaxPerLog 400 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'События nvlddmkm / NVIDIA' -Events $nvidiaEvents -EmptyText 'События драйвера NVIDIA не найдены.'

$amdEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('amdkmdag', 'amdwddmg', '*AMD*') -MaxPerLog 400 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'События драйвера AMD Display' -Events $amdEvents -EmptyText 'События драйвера AMD не найдены.'

$dxgkrnlEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -ProviderPatterns @('*DxgKrnl*', '*DirectX*') -MaxPerLog 400 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'События dxgkrnl / DirectX' -Events $dxgkrnlEvents -EmptyText 'События dxgkrnl или DirectX не найдены.'

$tdrEvents = Get-FilteredEvents -StartTime $start -Levels @(1, 2, 3) -MessagePatterns @('(?i)(TDR|timeout detection|display driver stopped responding|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)') -MaxPerLog 500 |
    Select-Object -First 50
Add-EventSection -Report $report -Title 'Таймауты GPU и TDR-подобные сбои' -Events $tdrEvents -EmptyText 'TDR-подобные проблемы или таймауты GPU не найдены.'

Write-StatReport -Report $report | Out-Null
