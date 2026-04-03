param(
    [string]$RunStamp = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
)

. "$PSScriptRoot\StatToolkit.Common.ps1"

$summary = New-StatReport -BlockNumber '' -Title 'Master_Summary' -DisplayTitle 'Сводный запуск всех диагностических блоков' -RunStamp $RunStamp

Add-Section -Report $summary -Title 'План сбора'
Add-ReportLine -Report $summary -Text 'Этот мастер-скрипт последовательно запускает все диагностические блоки с одной общей временной меткой.'
Add-ReportLine -Report $summary -Text 'Каждый блок выводит отчёт в консоль и сохраняет отдельный текстовый файл в C:\Stat.'

$blocks = @(
    [pscustomobject]@{ Path = "$PSScriptRoot\Block1_SystemInfo.ps1";               Name = 'Блок 1 - общая информация о системе';                    OutputTitle = 'SystemInfo';               BlockNumber = '1' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block2_SystemStats.ps1";              Name = 'Блок 2 - статистика и состояние системы';                OutputTitle = 'SystemStats';              BlockNumber = '2' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block3_DriverErrors.ps1";             Name = 'Блок 3 - ошибки драйверов';                             OutputTitle = 'DriverErrors';             BlockNumber = '3' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block4_GPUDriverErrors.ps1";          Name = 'Блок 4 - ошибки видеодрайвера и GPU';                    OutputTitle = 'GPU_Errors';               BlockNumber = '4' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block5_WHEA_PCI_Errors.ps1";          Name = 'Блок 5 - WHEA, PCIe и аппаратная стабильность';          OutputTitle = 'WHEA_PCI_Errors';          BlockNumber = '5' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block6_BSOD_CrashErrors.ps1";         Name = 'Блок 6 - BSOD, падения и дампы';                         OutputTitle = 'BSOD_CrashErrors';         BlockNumber = '6' },
    [pscustomobject]@{ Path = "$PSScriptRoot\Block7_AdditionalCriticalErrors.ps1"; Name = 'Блок 7 - дополнительные критические категории ошибок';  OutputTitle = 'AdditionalCriticalErrors'; BlockNumber = '7' }
)

Add-Section -Report $summary -Title 'Результаты выполнения'
foreach ($block in $blocks) {
    $expectedPath = Get-StatOutputPath -RunStamp $RunStamp -Title $block.OutputTitle -BlockNumber $block.BlockNumber
    try {
        Add-ReportLine -Report $summary -Text ('Запуск: {0}' -f $block.Name)
        & $block.Path -RunStamp $RunStamp
        Add-ReportLine -Report $summary -Text ('Статус : успешно')
        Add-ReportLine -Report $summary -Text ('Файл    : {0}' -f $expectedPath)
    }
    catch {
        Add-ReportLine -Report $summary -Text ('Статус : ошибка')
        Add-ReportLine -Report $summary -Text ('Файл    : {0}' -f $expectedPath)
        Add-ReportLine -Report $summary -Text ('Причина : {0}' -f $_.Exception.Message)
    }
    Add-ReportLine -Report $summary -Text ('-' * 70)
}

Add-Section -Report $summary -Title 'Сводный файл'
Add-KeyValue -Report $summary -Key 'Файл сводки' -Value $summary.FilePath
Add-KeyValue -Report $summary -Key 'Метка запуска' -Value $RunStamp

Write-StatReport -Report $summary | Out-Null
