$ErrorActionPreference = 'Stop'

function Get-StatRunStamp {
    Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
}

function Get-StatOutputRoot {
    'C:\Stat'
}

function Ensure-StatOutputRoot {
    $root = Get-StatOutputRoot
    if (-not (Test-Path -Path $root)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }
    $root
}

function Get-StatSafeName {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'Report'
    }

    (($Text -replace '[^A-Za-z0-9]+', '_').Trim('_'))
}

function Get-StatOutputPath {
    param(
        [string]$RunStamp,
        [string]$Title,
        [string]$BlockNumber
    )

    $root = Ensure-StatOutputRoot
    $safeTitle = Get-StatSafeName -Text $Title

    if ([string]::IsNullOrWhiteSpace($BlockNumber)) {
        return Join-Path -Path $root -ChildPath ('{0}_{1}.txt' -f $RunStamp, $safeTitle)
    }

    Join-Path -Path $root -ChildPath ('{0}_Block{1}_{2}.txt' -f $RunStamp, $BlockNumber, $safeTitle)
}

function New-StatReport {
    param(
        [string]$BlockNumber,
        [string]$Title,
        [string]$DisplayTitle,
        [string]$RunStamp
    )

    if ([string]::IsNullOrWhiteSpace($RunStamp)) {
        $RunStamp = Get-StatRunStamp
    }

    $report = [pscustomobject]@{
        BlockNumber = $BlockNumber
        Title       = $Title
        DisplayTitle = $(if ([string]::IsNullOrWhiteSpace($DisplayTitle)) { $Title } else { $DisplayTitle })
        RunStamp    = $RunStamp
        MachineName = $env:COMPUTERNAME
        StartedAt   = Get-Date
        FilePath    = Get-StatOutputPath -RunStamp $RunStamp -Title $Title -BlockNumber $BlockNumber
        Lines       = New-Object System.Collections.Generic.List[string]
    }

    Add-ReportLine -Report $report -Text ('# {0}' -f $report.DisplayTitle)
    if (-not [string]::IsNullOrWhiteSpace($BlockNumber)) {
        Add-ReportLine -Report $report -Text ('Номер блока: {0}' -f $BlockNumber)
    }
    Add-ReportLine -Report $report -Text ('Время сбора: {0}' -f ($report.StartedAt.ToString('yyyy-MM-dd HH:mm:ss zzz')))
    Add-ReportLine -Report $report -Text ('Компьютер: {0}' -f $report.MachineName)
    Add-ReportLine -Report $report -Text ('Файл отчёта: {0}' -f $report.FilePath)
    Add-ReportLine -Report $report -Text 'Режим: только чтение, без изменений системы'
    Add-ReportLine -Report $report -Text 'Формат: удобно для человека и для анализа в ChatGPT'
    Add-ReportLine -Report $report -Text ''

    $report
}

function Add-ReportLine {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [AllowEmptyString()]
        [string]$Text = ''
    )

    [void]$Report.Lines.Add($Text)
}

function Add-Section {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Add-ReportLine -Report $Report -Text ''
    Add-ReportLine -Report $Report -Text ('=' * 90)
    Add-ReportLine -Report $Report -Text $Title
    Add-ReportLine -Report $Report -Text ('=' * 90)
}

function Add-KeyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowEmptyString()]
        [string]$Value
    )

    Add-ReportLine -Report $Report -Text ('{0,-28}: {1}' -f $Key, $Value)
}

function ConvertTo-FlatText {
    param([object]$Value)

    if ($null -eq $Value) {
        return 'Недоступно'
    }

    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 0) {
            return 'Нет'
        }
        return (($Value | ForEach-Object { [string]$_ }) -join ', ')
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'Недоступно'
    }

    $text.Trim()
}

function Format-Bytes {
    param([Nullable[double]]$Bytes)

    if ($null -eq $Bytes) {
        return 'Недоступно'
    }

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $value = [double]$Bytes
    $unitIndex = 0

    while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $value = $value / 1024
        $unitIndex++
    }

    '{0:N2} {1}' -f $value, $units[$unitIndex]
}

function Invoke-Safely {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [object]$Fallback = $null
    )

    try {
        & $ScriptBlock
    }
    catch {
        $Fallback
    }
}

function Get-CimSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter
    )

    Invoke-Safely -Fallback $null -ScriptBlock {
        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            if ($Filter) {
                Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter
            }
            else {
                Get-CimInstance -Namespace $Namespace -ClassName $ClassName
            }
        }
        elseif (Get-Command -Name Get-WmiObject -ErrorAction SilentlyContinue) {
            if ($Filter) {
                Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter
            }
            else {
                Get-WmiObject -Namespace $Namespace -Class $ClassName
            }
        }
        else {
            throw 'No CIM or WMI command available.'
        }
    }
}

function Get-ShortMessage {
    param([object]$EventRecord)

    $message = Invoke-Safely -Fallback 'Сообщение недоступно.' -ScriptBlock { [string]$EventRecord.Message }
    $message = ($message -replace '\s+', ' ').Trim()

    if ($message.Length -gt 320) {
        return $message.Substring(0, 320) + '...'
    }

    $message
}

function Add-EventSection {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [object[]]$Events,
        [string]$EmptyText = 'Подходящие события не найдены.'
    )

    Add-Section -Report $Report -Title $Title

    if (-not $Events -or $Events.Count -eq 0) {
        Add-ReportLine -Report $Report -Text $EmptyText
        return
    }

    Add-ReportLine -Report $Report -Text ('Количество событий: {0}' -f $Events.Count)
    Add-ReportLine -Report $Report -Text ''

    foreach ($event in $Events) {
        $timestamp = Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') }
        $provider = ConvertTo-FlatText $event.ProviderName
        $eventId = ConvertTo-FlatText $event.Id
        $level = ConvertTo-FlatText $event.LevelDisplayName
        $logName = ConvertTo-FlatText $event.LogName
        $message = Get-ShortMessage -EventRecord $event

        Add-ReportLine -Report $Report -Text ('[{0}] {1} | ID события {2} | {3} | Журнал: {4}' -f $timestamp, $provider, $eventId, $level, $logName)
        Add-ReportLine -Report $Report -Text ('Сообщение: {0}' -f $message)
        Add-ReportLine -Report $Report -Text ('-' * 70)
    }
}

function Get-FilteredEvents {
    param(
        [string[]]$LogNames = @('System', 'Application'),
        [datetime]$StartTime = (Get-Date).AddDays(-7),
        [int[]]$Levels = @(1, 2, 3),
        [string[]]$ProviderPatterns = @(),
        [string[]]$MessagePatterns = @(),
        [int[]]$Ids = @(),
        [int]$MaxPerLog = 400
    )

    $allEvents = New-Object System.Collections.Generic.List[object]

    foreach ($logName in $LogNames) {
        $filter = @{
            LogName   = $logName
            StartTime = $StartTime
        }

        if ($Levels -and $Levels.Count -gt 0) {
            $filter.Level = $Levels
        }

        $events = Invoke-Safely -Fallback @() -ScriptBlock {
            Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxPerLog
        }

        foreach ($event in $events) {
            $providerOk = $true
            $messageOk = $true
            $idOk = $true

            if ($ProviderPatterns.Count -gt 0) {
                $providerOk = $false
                foreach ($pattern in $ProviderPatterns) {
                    if ($event.ProviderName -like $pattern) {
                        $providerOk = $true
                        break
                    }
                }
            }

            if ($MessagePatterns.Count -gt 0) {
                $messageOk = $false
                $messageText = Invoke-Safely -Fallback '' -ScriptBlock { [string]$event.Message }
                foreach ($pattern in $MessagePatterns) {
                    if ($messageText -match $pattern) {
                        $messageOk = $true
                        break
                    }
                }
            }

            if ($Ids.Count -gt 0) {
                $idOk = $Ids -contains [int]$event.Id
            }

            if ($providerOk -and $messageOk -and $idOk) {
                [void]$allEvents.Add($event)
            }
        }
    }

    $allEvents | Sort-Object TimeCreated -Descending
}

function Write-StatReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    $Report.Lines | Tee-Object -FilePath $Report.FilePath
}

function Add-CommandCaptureSection {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [string]$UnavailableText = 'Команда недоступна или завершилась ошибкой.'
    )

    Add-Section -Report $Report -Title $Title
    $lines = Invoke-Safely -Fallback $null -ScriptBlock $ScriptBlock

    if (-not $lines) {
        Add-ReportLine -Report $Report -Text $UnavailableText
        return
    }

    foreach ($line in $lines) {
        Add-ReportLine -Report $Report -Text ([string]$line)
    }
}
