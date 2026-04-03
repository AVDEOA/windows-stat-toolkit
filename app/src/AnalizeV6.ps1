param(
    [string]$PeriodChoice
)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$commonModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'StatToolkit.Common.ps1'
if (Test-Path -Path $commonModulePath) {
    . $commonModulePath
}

if (-not (Get-Command -Name Ensure-StatOutputRoot -ErrorAction SilentlyContinue)) {
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
                    Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop
                }
                else {
                    Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
                }
            }
            elseif (Get-Command -Name Get-WmiObject -ErrorAction SilentlyContinue) {
                if ($Filter) {
                    Get-WmiObject -Namespace $Namespace -Class $ClassName -Filter $Filter -ErrorAction Stop
                }
                else {
                    Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop
                }
            }
            else {
                throw 'No CIM or WMI command available.'
            }
        }
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

    function Get-ShortMessage {
        param([object]$EventRecord)

        $message = Invoke-Safely -Fallback 'Сообщение недоступно.' -ScriptBlock { [string]$EventRecord.Message }
        $message = ($message -replace '\s+', ' ').Trim()

        if ($message.Length -gt 320) {
            return $message.Substring(0, 320) + '...'
        }

        $message
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
                LogName = $logName
                StartTime = $StartTime
            }

            if ($Levels -and $Levels.Count -gt 0) {
                $filter.Level = $Levels
            }

            $events = Invoke-Safely -Fallback @() -ScriptBlock {
                Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxPerLog -ErrorAction Stop
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
}

function Resolve-AnalysisRange {
    param([string]$Choice)

    switch ($Choice) {
        '1' { return [pscustomobject]@{ Label = '2_days'; StartTime = (Get-Date).AddDays(-2) } }
        '2' { return [pscustomobject]@{ Label = '7_days'; StartTime = (Get-Date).AddDays(-7) } }
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

function Convert-ToUtcText {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    Invoke-Safely -Fallback $null -ScriptBlock {
        if ($Value -is [datetime]) {
            return $Value.ToString('yyyy-MM-dd HH:mm:ss')
        }

        ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Ensure-Array {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    @($Value)
}

function New-List {
    New-Object System.Collections.Generic.List[object]
}

function Add-UniqueText {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Text
    )

    if (-not [string]::IsNullOrWhiteSpace($Text) -and -not $Target.Contains($Text)) {
        [void]$Target.Add($Text)
    }
}

function Get-EventDataFields {
    param([object]$Event)

    $items = New-Object System.Collections.Generic.List[object]
    $xml = Invoke-Safely -Fallback $null -ScriptBlock { [xml]$Event.ToXml() }
    if ($null -eq $xml) {
        return @()
    }

    $index = 0
    foreach ($node in @(Invoke-Safely -Fallback @() -ScriptBlock { $xml.Event.EventData.Data })) {
        $value = ([string]$node.'#text').Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $name = if ($node.Name) { [string]$node.Name } else { 'Data{0}' -f $index }
            [void]$items.Add([pscustomobject]@{
                name = $name
                value = $value
            })
        }
        $index++
    }

    foreach ($child in @(Invoke-Safely -Fallback @() -ScriptBlock { $xml.Event.UserData.ChildNodes })) {
        foreach ($node in @($child.ChildNodes)) {
            $value = ([string]$node.InnerText).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                [void]$items.Add([pscustomobject]@{
                    name = [string]$node.Name
                    value = $value
                })
            }
        }
    }

    @($items | ForEach-Object { $_ })
}

function Get-EventPropertyValues {
    param([object]$Event)

    @(
        foreach ($property in @(Invoke-Safely -Fallback @() -ScriptBlock { $Event.Properties })) {
            $value = Invoke-Safely -Fallback $null -ScriptBlock { $property.Value }
            if ($null -ne $value) {
                $text = ([string]$value).Trim()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $text
                }
            }
        }
    )
}

function Get-ObjectPropertyValueSafe {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    $property.Value
}

function Get-SpecializedEventText {
    param([object]$Event)

    $provider = Invoke-Safely -Fallback '' -ScriptBlock { [string]$Event.ProviderName }
    $eventId = Invoke-Safely -Fallback '' -ScriptBlock { [string]$Event.Id }
    $eventDataFields = @(Get-EventDataFields -Event $Event)
    $propertyValues = @(Get-EventPropertyValues -Event $Event)

    if ($provider -eq 'nvlddmkm' -and $eventId -eq '153') {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($field in $eventDataFields) {
            Add-UniqueText -Target $parts -Text ('{0}={1}' -f $field.name, $field.value)
        }
        foreach ($value in $propertyValues) {
            Add-UniqueText -Target $parts -Text ([string]$value)
        }

        if ($parts.Count -gt 0) {
            return [pscustomobject]@{
                text = ('Событие nvlddmkm 153: локализованный текст недоступен, но извлечены поля события: {0}' -f (($parts | Select-Object -First 8) -join '; '))
                source = 'synthesized'
            }
        }

        return [pscustomobject]@{
            text = 'Событие nvlddmkm 153: локализованный текст недоступен. Сам факт повторения этих записей указывает на нестабильность NVIDIA-драйвера, GPU или графического стека.'
            source = 'synthesized'
        }
    }

    $null
}

function Get-EventMessageForAnalysis {
    param([object]$Event)

    $directMessage = Invoke-Safely -Fallback $null -ScriptBlock { [string]$Event.Message }
    if (-not [string]::IsNullOrWhiteSpace($directMessage)) {
        return [pscustomobject]@{
            text = ((($directMessage -replace '\s+', ' ').Trim()))
            source = 'message'
        }
    }

    $specializedText = Get-SpecializedEventText -Event $Event
    if ($specializedText) {
        return $specializedText
    }

    $eventDataText = @(
        Get-EventDataFields -Event $Event | ForEach-Object {
            '{0}={1}' -f $_.name, $_.value
        }
    ) -join '; '
    if (-not [string]::IsNullOrWhiteSpace($eventDataText)) {
        return [pscustomobject]@{
            text = $eventDataText
            source = 'event_data'
        }
    }

    $propertyText = @(Get-EventPropertyValues -Event $Event) -join '; '
    if (-not [string]::IsNullOrWhiteSpace($propertyText)) {
        return [pscustomobject]@{
            text = $propertyText
            source = 'properties'
        }
    }

    [pscustomobject]@{
        text = 'Сообщение недоступно.'
        source = 'fallback'
    }
}

function Convert-EventToCanonicalObject {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Event,
        [Parameter(Mandatory = $true)]
        [string]$Block,
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    $timestamp = Invoke-Safely -Fallback $null -ScriptBlock { Convert-ToUtcText -Value $Event.TimeCreated }
    $provider = Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { ConvertTo-FlatText $Event.ProviderName }
    $eventId = Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { ConvertTo-FlatText $Event.Id }
    $severity = Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { ConvertTo-FlatText $Event.LevelDisplayName }
    $logName = Invoke-Safely -Fallback 'Недоступно' -ScriptBlock { ConvertTo-FlatText $Event.LogName }
    $messageInfo = Invoke-Safely -Fallback ([pscustomobject]@{ text = 'Сообщение недоступно.'; source = 'fallback' }) -ScriptBlock { Get-EventMessageForAnalysis -Event $Event }
    $message = [string]$messageInfo.text
    if (-not [string]::IsNullOrWhiteSpace($message) -and $message.Length -gt 320) {
        $message = $message.Substring(0, 320) + '...'
    }
    $eventData = @(Invoke-Safely -Fallback @() -ScriptBlock { Get-EventDataFields -Event $Event })
    $propertyValues = @(Invoke-Safely -Fallback @() -ScriptBlock { Get-EventPropertyValues -Event $Event })
    $signature = '{0}|{1}|{2}|{3}|{4}' -f $timestamp, $provider, $eventId, $logName, $message

    [pscustomobject]@{
        event_key = $signature
        timestamp = $timestamp
        provider = $provider
        event_id = $eventId
        severity = $severity
        log = $logName
        message = $message
        message_source = $messageInfo.source
        event_data = $eventData
        properties = $propertyValues
        matched_categories = @(
            [pscustomobject]@{
                block = $Block
                category = $Category
            }
        )
    }
}

function Add-DedupedEvents {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Block,
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [object[]]$Events
    )

    foreach ($event in @(Ensure-Array $Events)) {
        if ($null -eq $event) {
            continue
        }

        if (-not (Get-Member -InputObject $event -Name 'TimeCreated' -ErrorAction SilentlyContinue)) {
            continue
        }

        $canonical = Invoke-Safely -Fallback $null -ScriptBlock {
            Convert-EventToCanonicalObject -Event $event -Block $Block -Category $Category
        }
        if ($null -eq $canonical) {
            continue
        }

        if ($Map.ContainsKey($canonical.event_key)) {
            $existing = $Map[$canonical.event_key]
            $alreadyPresent = $false

            foreach ($match in $existing.matched_categories) {
                if ($match.block -eq $Block -and $match.category -eq $Category) {
                    $alreadyPresent = $true
                    break
                }
            }

            if (-not $alreadyPresent) {
                $existing.matched_categories += [pscustomobject]@{
                    block = $Block
                    category = $Category
                }
            }
        }
        else {
            $Map[$canonical.event_key] = $canonical
        }
    }
}

function Get-ExactIdEvents {
    param(
        [string[]]$LogNames = @('System'),
        [datetime]$StartTime = (Get-Date).AddDays(-7),
        [int[]]$Levels = @(),
        [int[]]$Ids = @(),
        [int]$MaxPerLog = 1000
    )

    $allEvents = New-Object System.Collections.Generic.List[object]

    foreach ($logName in $LogNames) {
        $filter = @{
            LogName = $logName
            StartTime = $StartTime
        }

        if ($Levels -and $Levels.Count -gt 0) {
            $filter.Level = $Levels
        }

        if ($Ids -and $Ids.Count -gt 0) {
            $filter.Id = $Ids
        }

        $events = Invoke-Safely -Fallback @() -ScriptBlock {
            Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxPerLog -ErrorAction Stop
        }

        foreach ($event in @($events)) {
            [void]$allEvents.Add($event)
        }
    }

    @($allEvents | Sort-Object TimeCreated -Descending)
}

function Get-ExactProviderIdEvents {
    param(
        [string[]]$LogNames = @('System'),
        [datetime]$StartTime = (Get-Date).AddDays(-7),
        [int[]]$Levels = @(),
        [int[]]$Ids = @(),
        [string[]]$ProviderNames = @(),
        [int]$MaxPerLog = 1000
    )

    $allEvents = New-Object System.Collections.Generic.List[object]

    foreach ($logName in $LogNames) {
        $filter = @{
            LogName = $logName
            StartTime = $StartTime
        }

        if ($Levels -and $Levels.Count -gt 0) {
            $filter.Level = $Levels
        }

        if ($Ids -and $Ids.Count -gt 0) {
            $filter.Id = $Ids
        }

        if ($ProviderNames -and $ProviderNames.Count -gt 0) {
            $filter.ProviderName = $ProviderNames
        }

        $events = Invoke-Safely -Fallback @() -ScriptBlock {
            Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxPerLog -ErrorAction Stop
        }

        foreach ($event in @($events)) {
            [void]$allEvents.Add($event)
        }
    }

    @($allEvents | Sort-Object TimeCreated -Descending)
}

function Get-BugcheckInterpretation {
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) {
        return 'Код bugcheck не удалось извлечь из события.'
    }

    switch -Regex ($Code.ToUpper()) {
        '^0X116$' { return 'VIDEO_TDR_FAILURE: типичный признак зависания видеодрайвера или GPU при попытке recovery.' }
        '^0X117$' { return 'VIDEO_TDR_TIMEOUT_DETECTED: видеостек переставал отвечать достаточно долго.' }
        '^0X119$' { return 'VIDEO_SCHEDULER_INTERNAL_ERROR: проблема в графическом планировщике/драйверном стеке GPU.' }
        '^0X133$' { return 'DPC_WATCHDOG_VIOLATION: система зависала на высоком IRQL, часто из-за драйвера или подсистемы хранения.' }
        '^0X141$' { return 'VIDEO_ENGINE_TIMEOUT_DETECTED: одно из графических устройств или engine перестало отвечать.' }
        '^0X9F$'  { return 'DRIVER_POWER_STATE_FAILURE: драйвер некорректно отработал переход питания или sleep/resume.' }
        '^0X7E$'  { return 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED: системный поток завершился исключением, часто по вине драйвера.' }
        '^0X3B$'  { return 'SYSTEM_SERVICE_EXCEPTION: ошибка в системном сервисе, нередко связана с драйвером или памятью.' }
        default   { return 'Нужен отдельный разбор stop code, дампа и драйверного стека для точной интерпретации.' }
    }
}

function Get-BugcheckCodeFromEventRecord {
    param([object]$EventRecord)

    $candidates = New-Object System.Collections.Generic.List[string]
    Add-UniqueText -Target $candidates -Text ([string]$EventRecord.message)
    foreach ($item in @(Ensure-Array $EventRecord.event_data)) {
        Add-UniqueText -Target $candidates -Text ([string]$item.value)
    }
    foreach ($item in @(Ensure-Array $EventRecord.properties)) {
        Add-UniqueText -Target $candidates -Text ([string]$item)
    }

    foreach ($text in @($candidates)) {
        $match = [regex]::Match($text, '(?i)\b0x[0-9a-f]{1,8}\b')
        if ($match.Success) {
            return $match.Value.ToUpper()
        }
    }

    $null
}

function Get-PnpDevicePropertyValueSafe {
    param(
        [string]$InstanceId,
        [string]$KeyName
    )

    Invoke-Safely -Fallback $null -ScriptBlock {
        $property = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop
        if ($property -and $null -ne $property.Data) {
            [string]$property.Data
        }
        else {
            $null
        }
    }
}

function Get-DisplayPnpInventory {
    if (-not (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue)) {
        return @()
    }

    @(
        Invoke-Safely -Fallback @() -ScriptBlock { Get-PnpDevice -Class Display -ErrorAction Stop } |
            ForEach-Object {
                $instanceId = $_.InstanceId
                [pscustomobject]@{
                    friendly_name = $_.FriendlyName
                    status = $_.Status
                    class = $_.Class
                    instance_id = $instanceId
                    present = (Invoke-Safely -Fallback $null -ScriptBlock { $_.Present })
                    manufacturer = (Get-PnpDevicePropertyValueSafe -InstanceId $instanceId -KeyName 'DEVPKEY_Device_Manufacturer')
                    driver_version = (Get-PnpDevicePropertyValueSafe -InstanceId $instanceId -KeyName 'DEVPKEY_Device_DriverVersion')
                    location_info = (Get-PnpDevicePropertyValueSafe -InstanceId $instanceId -KeyName 'DEVPKEY_Device_LocationInfo')
                    location_paths = (Get-PnpDevicePropertyValueSafe -InstanceId $instanceId -KeyName 'DEVPKEY_Device_LocationPaths')
                    service = (Get-PnpDevicePropertyValueSafe -InstanceId $instanceId -KeyName 'DEVPKEY_Device_Service')
                }
            }
    )
}

function Get-NvidiaSmiCommand {
    $candidates = @(
        'nvidia-smi.exe',
        'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe',
        'C:\Windows\System32\nvidia-smi.exe'
    )

    foreach ($candidate in $candidates) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }

        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }

    $null
}

function Get-NvidiaSmiInventory {
    $commandPath = Get-NvidiaSmiCommand
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        return @()
    }

    @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            & $commandPath --query-gpu=name,pci.bus_id,driver_version,gpu_uuid --format=csv,noheader
        } |
            ForEach-Object {
                $line = ([string]$_).Trim()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $parts = $line -split '\s*,\s*'
                    [pscustomobject]@{
                        name = $(if ($parts.Count -ge 1) { $parts[0] } else { $null })
                        pci_bus_id = $(if ($parts.Count -ge 2) { $parts[1] } else { $null })
                        driver_version = $(if ($parts.Count -ge 3) { $parts[2] } else { $null })
                        gpu_uuid = $(if ($parts.Count -ge 4) { $parts[3] } else { $null })
                    }
                }
            }
    )
}

function Get-EventHeuristics {
    param([Parameter(Mandatory = $true)][object]$EventRecord)

    $tags = New-Object System.Collections.Generic.List[string]
    $causes = New-Object System.Collections.Generic.List[string]
    $message = [string]$EventRecord.message
    $provider = [string]$EventRecord.provider
    $eventId = [string]$EventRecord.event_id

    if ($provider -like '*Kernel-Power*' -and $eventId -eq '41') {
        Add-UniqueText -Target $tags -Text 'unexpected_restart'
        Add-UniqueText -Target $tags -Text 'power_or_crash_symptom'
        Add-UniqueText -Target $tags -Text 'crash_signal'
        Add-UniqueText -Target $causes -Text 'Система перезагрузилась без корректного завершения работы.'
        Add-UniqueText -Target $causes -Text 'Возможные причины: зависание системы, аппаратный сбой, потеря питания или принудительная перезагрузка.'
    }

    if ($eventId -eq '6008') {
        Add-UniqueText -Target $tags -Text 'unexpected_shutdown'
        Add-UniqueText -Target $tags -Text 'crash_signal'
        Add-UniqueText -Target $causes -Text 'Windows зафиксировала предыдущее неожиданное завершение работы.'
    }

    if (($provider -eq 'User32' -and $eventId -eq '1074') -or ($provider -like '*Kernel-Power*' -and $eventId -eq '109') -or ($provider -eq 'EventLog' -and $eventId -in @('6005', '6006'))) {
        Add-UniqueText -Target $tags -Text 'planned_restart_signal'
    }

    if ($eventId -eq '1001' -and $message -match '(?i)(bugcheck|blue screen|dump)') {
        Add-UniqueText -Target $tags -Text 'bugcheck_bsod'
        Add-UniqueText -Target $tags -Text 'crash_signal'
        Add-UniqueText -Target $causes -Text 'Windows зафиксировала bugcheck / BSOD и, вероятно, создала дамп памяти.'
    }

    if ($provider -like '*Kernel-PnP*' -and $message -match '(?i)vmbusr') {
        Add-UniqueText -Target $tags -Text 'driver_load_failure'
        Add-UniqueText -Target $tags -Text 'hyperv_vm_bus'
        Add-UniqueText -Target $causes -Text 'Не загрузился драйвер VMBus, связанный с виртуализацией Hyper-V.'
        Add-UniqueText -Target $causes -Text 'Это часто указывает на неполную доступность функций гипервизора или несоответствие виртуализационных компонентов.'
    }

    if ($provider -eq 'Service Control Manager' -and $message -match '(?i)WSLService') {
        Add-UniqueText -Target $tags -Text 'wsl_timeout'
        Add-UniqueText -Target $causes -Text 'Служба WSL ответила с таймаутом, что может мешать запуску или обслуживанию WSL-компонентов.'
    }

    if ($provider -eq 'Service Control Manager' -and $message -match '(?i)HvHost|Nested Network Virtualization|VMSP') {
        Add-UniqueText -Target $tags -Text 'hyperv_service_failure'
        Add-UniqueText -Target $causes -Text 'Службы Hyper-V/виртуализации не стартовали или завершились с ошибкой.'
        Add-UniqueText -Target $causes -Text 'Вероятная причина: отключённые или недоступные функции виртуализации, либо нехватка системных ресурсов.'
    }

    if ($provider -like '*WindowsUpdateClient*') {
        Add-UniqueText -Target $tags -Text 'update_install_failure'
        Add-UniqueText -Target $causes -Text 'Не удалось установить обновление Windows или компонент Microsoft Store.'
        if ($message -match '0x80240016') {
            Add-UniqueText -Target $causes -Text 'Код 0x80240016 часто означает, что другая установка уже выполнялась или обновление было занято.'
        }
        if ($message -match '0x80073D02') {
            Add-UniqueText -Target $causes -Text 'Код 0x80073D02 часто означает, что обновляемый пакет был занят работающим процессом.'
        }
    }

    if ($provider -like '*Hyper-V-Hypervisor*' -and $message -match '(?i)VMX not present|not enabled in BIOS') {
        Add-UniqueText -Target $tags -Text 'virtualization_not_available'
        Add-UniqueText -Target $causes -Text 'Гипервизор не смог стартовать, потому что VMX отсутствует или не включён.'
    }

    if ($provider -eq 'nvlddmkm' -and $eventId -eq '153') {
        Add-UniqueText -Target $tags -Text 'nvidia_driver_instability'
        Add-UniqueText -Target $tags -Text 'gpu_instability'
        Add-UniqueText -Target $causes -Text 'Повторяющиеся nvlddmkm 153 часто указывают на нестабильность NVIDIA-драйвера, устройства GPU или рендер-стека.'
    }

    if ($provider -eq 'disk' -and ($eventId -eq '7' -or $message -match '(?i)bad block')) {
        Add-UniqueText -Target $tags -Text 'storage_bad_block'
        Add-UniqueText -Target $tags -Text 'storage_instability'
        Add-UniqueText -Target $causes -Text 'Зафиксирован bad block в подсистеме хранения, что является красным флагом деградации накопителя или ошибок чтения.'
    }

    [pscustomobject]@{
        diagnostic_tags = @($tags)
        probable_causes = @($causes)
    }
}

function New-Finding {
    param(
        [string]$Id,
        [string]$Severity,
        [string]$Title,
        [string]$Summary,
        [string[]]$EvidenceKeys,
        [string[]]$ProbableCauses,
        [string[]]$UserQuestionsSupported
    )

    [pscustomobject]@{
        id = $Id
        severity = $Severity
        title = $Title
        summary = $Summary
        evidence_event_keys = @(Ensure-Array $EvidenceKeys)
        probable_causes = @(Ensure-Array $ProbableCauses)
        questions_supported = @(Ensure-Array $UserQuestionsSupported)
    }
}

function Get-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name
    )

    Invoke-Safely -Fallback $null -ScriptBlock {
        (Get-ItemProperty -Path $Path -ErrorAction Stop).$Name
    }
}

function Convert-RegistryFlagToState {
    param(
        [object]$Value,
        [hashtable]$Map,
        [string]$Unknown = 'unknown'
    )

    if ($null -eq $Value) {
        return $Unknown
    }

    $key = [string]$Value
    if ($Map.ContainsKey($key)) {
        return $Map[$key]
    }

    $Unknown
}

function Get-ActivePowerPlanInfo {
    $powerSchemesPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $activeGuid = Get-RegistryValueSafe -Path $powerSchemesPath -Name 'ActivePowerScheme'
    $friendlyName = $null

    if (-not [string]::IsNullOrWhiteSpace([string]$activeGuid)) {
        $friendlyName = Get-RegistryValueSafe -Path (Join-Path -Path $powerSchemesPath -ChildPath ([string]$activeGuid)) -Name 'FriendlyName'
    }

    $knownPlans = @{
        '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'
        'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'
        'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate Performance'
    }

    if ([string]::IsNullOrWhiteSpace([string]$friendlyName) -and -not [string]::IsNullOrWhiteSpace([string]$activeGuid)) {
        $guidKey = ([string]$activeGuid).ToLower()
        if ($knownPlans.ContainsKey($guidKey)) {
            $friendlyName = $knownPlans[$guidKey]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$friendlyName) -and [string]$friendlyName -match ',([^,]+)$') {
        $friendlyName = $Matches[1].Trim()
    }

    [pscustomobject]@{
        guid = $(if ([string]::IsNullOrWhiteSpace([string]$activeGuid)) { $null } else { [string]$activeGuid })
        name = $(if ([string]::IsNullOrWhiteSpace([string]$friendlyName)) { $null } else { [string]$friendlyName })
    }
}

function Get-PathCandidateFromCommandText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $trimmed = $Text.Trim()
    $trimmed = $trimmed -replace ':[A-Za-z]+$',''
    $trimmed = [Environment]::ExpandEnvironmentVariables($trimmed)

    $quoted = [regex]::Match($trimmed, '^"([^"]+)"')
    if ($quoted.Success) {
        return $quoted.Groups[1].Value.Trim()
    }

    $exe = [regex]::Match($trimmed, '^[A-Za-z]:\\[^|><\r\n]+?\.(exe|cmd|bat|ps1)')
    if ($exe.Success) {
        return $exe.Value.Trim()
    }

    if ($trimmed -match '^[A-Za-z]:\\[^:*?<>|"\r\n]+$') {
        return $trimmed.Trim('"')
    }

    $null
}

function Test-SafePathLiteral {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $candidate = $Path.Trim().Trim('"')
    if ($candidate -match ':[A-Za-z]+$') {
        return $false
    }
    if ($candidate -notmatch '^[A-Za-z]:\\') {
        return $false
    }
    if ($candidate -match '[\*\?<>|]') {
        return $false
    }

    Invoke-Safely -Fallback $false -ScriptBlock {
        Test-Path -Path $candidate -ErrorAction Stop
    }
}

function Convert-TimeValueSafe {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    Invoke-Safely -Fallback $null -ScriptBlock {
        if ($Value -is [datetime]) {
            return $Value.ToString('yyyy-MM-dd HH:mm:ss')
        }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        if ($text -match '^\d{14}\.\d{6}[\+\-]\d{3}$') {
            return ([Management.ManagementDateTimeConverter]::ToDateTime($text)).ToString('yyyy-MM-dd HH:mm:ss')
        }

        ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Get-InstalledSoftwareInventory {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    @(
        foreach ($path in $paths) {
            foreach ($item in @(Invoke-Safely -Fallback @() -ScriptBlock { Get-ItemProperty -Path $path -ErrorAction Stop })) {
                if (-not [string]::IsNullOrWhiteSpace($item.DisplayName)) {
                    [pscustomobject]@{
                        name = $item.DisplayName
                        version = $item.DisplayVersion
                        publisher = $item.Publisher
                        install_date = $item.InstallDate
                        install_location = $item.InstallLocation
                        uninstall_string = $item.UninstallString
                    }
                }
            }
        }
    )
}

function Get-DriversInventory {
    param([object[]]$Drivers)

    @(
        @($Drivers) |
            Sort-Object DriverDate -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    device_name = $_.DeviceName
                    device_id = $_.DeviceID
                    manufacturer = $_.Manufacturer
                    driver_provider = $_.DriverProviderName
                    driver_version = $_.DriverVersion
                    driver_date = $_.DriverDate
                    inf_name = $_.InfName
                    driver_name = $_.DriverName
                    device_class = $_.DeviceClass
                    signer = $_.Signer
                    is_signed = $_.IsSigned
                    location = $_.Location
                }
            }
    )
}

function Get-ServiceInventory {
    @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                Select-Object Name, DisplayName, State, StartMode, PathName
        }
    )
}

function Get-ScheduledTaskInventory {
    if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        return @()
    }

    @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            Get-ScheduledTask -ErrorAction Stop |
                Select-Object TaskName, TaskPath, State, Author, Description
        }
    )
}

function Get-StartupInventory {
    $startupCommands = @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop |
                Select-Object Name, Command, Location, User
        }
    )

    $runPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )

    $registryItems = @(
        foreach ($path in $runPaths) {
            $item = Invoke-Safely -Fallback $null -ScriptBlock { Get-ItemProperty -Path $path -ErrorAction Stop }
            if ($item) {
                foreach ($property in $item.PSObject.Properties) {
                    if ($property.Name -notmatch '^PS') {
                        [pscustomobject]@{
                            Name = $property.Name
                            Command = [string]$property.Value
                            Location = $path
                            User = $env:USERNAME
                        }
                    }
                }
            }
        }
    )

    @($startupCommands + $registryItems)
}

function Get-WindowsUpdateInventory {
    @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            Get-HotFix -ErrorAction Stop |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 50 HotFixID, Description, InstalledBy, InstalledOn
        }
    )
}

function Get-NetworkAdapterInventory {
    @(
        Invoke-Safely -Fallback @() -ScriptBlock {
            Get-NetAdapter -IncludeHidden -ErrorAction Stop |
                Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion, DriverFileName, InterfaceGuid
        }
    )
}

function Get-ApplicationCrashInventory {
    @(
        Get-FilteredEvents -LogNames @('Application') -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Application Error', '.NET Runtime', 'Application Hang', 'Windows Error Reporting', 'Application Popup') -MaxPerLog 400 |
            Select-Object -First 120 |
            ForEach-Object {
                [pscustomobject]@{
                    timestamp = (Invoke-Safely -Fallback $null -ScriptBlock { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') })
                    provider = $_.ProviderName
                    event_id = $_.Id
                    level = $_.LevelDisplayName
                    message = (Get-EventMessageForAnalysis -Event $_).text
                }
            }
    )
}

function Get-DriverUpdateHistory {
    @(
        Get-FilteredEvents -LogNames @('System', 'Application') -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -ProviderPatterns @('*UserPnp*', '*DeviceSetupManager*', '*SetupAPI*') -MessagePatterns @('(?i)(install|update|driver package|configured|migrat|device install|rollback)') -MaxPerLog 500 |
            Select-Object -First 150 |
            ForEach-Object {
                [pscustomobject]@{
                    timestamp = (Invoke-Safely -Fallback $null -ScriptBlock { $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') })
                    provider = $_.ProviderName
                    event_id = $_.Id
                    level = $_.LevelDisplayName
                    message = (Get-EventMessageForAnalysis -Event $_).text
                }
            }
    )
}

function Get-PotentiallyConflictingSoftware {
    param([object[]]$Software)

    $definitions = @(
        @{ category = 'gpu_driver_stack'; pattern = '(?i)(nvidia|amd|geforce|radeon|cuda|physx)' ; rationale = 'Может влиять на графический стек и совместимость видеодрайверов.' }
        @{ category = 'monitoring_tuning_overlay'; pattern = '(?i)(msi afterburner|rivatuner|rtss|gpu-z|hwinfo|aida|overclock|tuning|precision x)' ; rationale = 'Мониторинг, overlay или тюнинг могут влиять на стабильность GPU и рендера.' }
        @{ category = 'vendor_utility_rgb'; pattern = '(?i)(rgb|aura|armoury|armory|icue|nzxt|gigabyte control|dragon center)' ; rationale = 'Вендорские утилиты и RGB-слой иногда создают конфликтный фон служб и драйверов.' }
        @{ category = 'remote_access_agent'; pattern = '(?i)(mesh|vpn|parsec|teamviewer|anydesk|rustdesk|openssh|ssh|remote)' ; rationale = 'Remote access / mesh / VPN инструменты влияют на сетевой и сервисный контекст узла.' }
        @{ category = 'render_pipeline'; pattern = '(?i)(deadline|thinkbox|launcher|worker|monitor|draft|chaos|v-ray|autodesk|maya|3ds max)' ; rationale = 'Рендерный и DCC-контекст важен для сопоставления с задачами и падениями приложений.' }
        @{ category = 'updater_agent'; pattern = '(?i)(updater|update service|cosmos|adsk|autodesk access)' ; rationale = 'Updater-агенты могут создавать фоновые задачи, сервисы и перезапуски.' }
    )

    $matches = @(
        foreach ($item in @($Software)) {
            foreach ($definition in $definitions) {
                if ($item.name -match $definition.pattern) {
                    [pscustomobject]@{
                        name = $item.name
                        version = $item.version
                        publisher = $item.publisher
                        category = $definition.category
                        rationale = $definition.rationale
                    }
                    break
                }
            }
        }
    )

    @($matches | Sort-Object category, name -Unique)
}

function Get-DeadlineContext {
    param(
        [object[]]$Software,
        [object[]]$Services,
        [object[]]$Tasks,
        [object[]]$StartupItems
    )

    $patterns = '(?i)(deadline|thinkbox|launcher|worker|pulse|monitor|draft)'
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Software)) {
        if ($item.name -match $patterns) {
            Add-UniqueText -Target $candidatePaths -Text ([string]$item.install_location)
        }
    }
    foreach ($item in @($Services)) {
        Add-UniqueText -Target $candidatePaths -Text (Get-PathCandidateFromCommandText -Text ([string]$item.PathName))
    }
    foreach ($item in @($StartupItems)) {
        Add-UniqueText -Target $candidatePaths -Text (Get-PathCandidateFromCommandText -Text ([string]$item.Command))
    }

    Add-UniqueText -Target $candidatePaths -Text 'C:\ProgramData\Thinkbox\Deadline10'
    Add-UniqueText -Target $candidatePaths -Text 'C:\ProgramData\Thinkbox\Deadline10\logs'
    Add-UniqueText -Target $candidatePaths -Text 'C:\Program Files\Thinkbox\Deadline10'

    $existingPaths = @(
        foreach ($path in @($candidatePaths)) {
            $trimmed = ([string]$path).Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and (Test-SafePathLiteral -Path $trimmed)) {
                [pscustomobject]@{
                    path = $trimmed
                    type = $(if (Invoke-Safely -Fallback $false -ScriptBlock { Test-Path -Path $trimmed -PathType Container -ErrorAction Stop }) { 'directory' } else { 'file' })
                }
            }
        }
    )

    $recentLogCandidates = @(
        foreach ($pathInfo in @($existingPaths | Where-Object { $_.type -eq 'directory' -and $_.path -match '(?i)(deadline|thinkbox)' })) {
            foreach ($file in @(Invoke-Safely -Fallback @() -ScriptBlock {
                Get-ChildItem -Path $pathInfo.path -File -Recurse -ErrorAction Stop |
                    Where-Object { $_.Extension -match '(?i)\.(log|txt|ini|xml)$' } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 10
            })) {
                [pscustomobject]@{
                    path = $file.FullName
                    last_write = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                    size_bytes = $file.Length
                }
            }
        }
    )
    $recentLogFiles = @($recentLogCandidates | Sort-Object last_write -Descending | Select-Object -First 20)

    [ordered]@{
        detected = $(if ((@($Software) | Where-Object { $_.name -match $patterns }).Count -gt 0 -or (@($Services) | Where-Object { $_.Name -match $patterns -or $_.DisplayName -match $patterns }).Count -gt 0 -or (@($Tasks) | Where-Object { $_.TaskName -match $patterns -or $_.Description -match $patterns }).Count -gt 0 -or (@($StartupItems) | Where-Object { $_.Name -match $patterns -or $_.Command -match $patterns }).Count -gt 0) { $true } else { $false })
        software = @(@($Software) | Where-Object { $_.name -match $patterns } | Sort-Object name -Unique)
        services = @(@($Services) | Where-Object { $_.Name -match $patterns -or $_.DisplayName -match $patterns } | Sort-Object Name -Unique)
        scheduled_tasks = @(@($Tasks) | Where-Object { $_.TaskName -match $patterns -or $_.Description -match $patterns } | Sort-Object TaskPath, TaskName -Unique)
        startup_items = @(@($StartupItems) | Where-Object { $_.Name -match $patterns -or $_.Command -match $patterns } | Sort-Object Name -Unique)
        existing_paths = @($existingPaths)
        recent_log_files = @($recentLogFiles)
    }
}

function Get-StorageHealthInventory {
    $items = New-Object System.Collections.Generic.List[object]

    $physicalDisks = @(Ensure-Array (Invoke-Safely -Fallback @() -ScriptBlock { Get-PhysicalDisk -ErrorAction Stop }))
    foreach ($disk in $physicalDisks) {
        $reliability = Invoke-Safely -Fallback $null -ScriptBlock {
            if (Get-Command -Name Get-StorageReliabilityCounter -ErrorAction SilentlyContinue) {
                Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
            }
        }

        [void]$items.Add([pscustomobject]@{
            source = 'Get-PhysicalDisk'
            device_name = (Get-ObjectPropertyValueSafe -Object $disk -Name 'FriendlyName')
            serial_number = (Get-ObjectPropertyValueSafe -Object $disk -Name 'SerialNumber')
            health_status = (Get-ObjectPropertyValueSafe -Object $disk -Name 'HealthStatus')
            operational_status = @((Get-ObjectPropertyValueSafe -Object $disk -Name 'OperationalStatus')) -join ', '
            media_type = (Get-ObjectPropertyValueSafe -Object $disk -Name 'MediaType')
            bus_type = (Get-ObjectPropertyValueSafe -Object $disk -Name 'BusType')
            size_bytes = (Get-ObjectPropertyValueSafe -Object $disk -Name 'Size')
            firmware_version = (Get-ObjectPropertyValueSafe -Object $disk -Name 'FirmwareVersion')
            temperature_celsius = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'Temperature')
            wear = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'Wear')
            read_errors_total = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'ReadErrorsTotal')
            write_errors_total = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'WriteErrorsTotal')
            power_on_hours = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'PowerOnHours')
            unsafe_shutdowns = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'UnsafeShutdownCount')
            media_errors_total = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'MediaErrorsTotal')
            temperature_max_celsius = (Get-ObjectPropertyValueSafe -Object $reliability -Name 'TemperatureMax')
        })
    }

    $predictStatus = @(Ensure-Array (Get-CimSafe -Namespace 'root/wmi' -ClassName 'MSStorageDriver_FailurePredictStatus'))
    foreach ($status in $predictStatus) {
        [void]$items.Add([pscustomobject]@{
            source = 'MSStorageDriver_FailurePredictStatus'
            instance_name = (Get-ObjectPropertyValueSafe -Object $status -Name 'InstanceName')
            predict_failure = (Get-ObjectPropertyValueSafe -Object $status -Name 'PredictFailure')
            reason = (Get-ObjectPropertyValueSafe -Object $status -Name 'Reason')
        })
    }

    $predictData = @(Ensure-Array (Get-CimSafe -Namespace 'root/wmi' -ClassName 'MSStorageDriver_FailurePredictData'))
    foreach ($data in $predictData) {
        [void]$items.Add([pscustomobject]@{
            source = 'MSStorageDriver_FailurePredictData'
            instance_name = (Get-ObjectPropertyValueSafe -Object $data -Name 'InstanceName')
            vendor_specific_length = @((Get-ObjectPropertyValueSafe -Object $data -Name 'VendorSpecific')).Count
        })
    }

    $result = @()
    foreach ($item in $items) {
        $result += $item
    }
    $result
}

function Get-ReliabilityMonitorData {
    $metrics = @(
        Ensure-Array (Get-CimSafe -ClassName 'Win32_ReliabilityStabilityMetrics') |
            Sort-Object TimeGenerated -Descending |
            Select-Object -First 30 |
            ForEach-Object {
                [pscustomobject]@{
                    time_generated = $(if (Convert-TimeValueSafe -Value $_.TimeGenerated) { Convert-TimeValueSafe -Value $_.TimeGenerated } else { Convert-TimeValueSafe -Value $_.EndMeasurementDate })
                    system_stability_index = $_.SystemStabilityIndex
                }
            }
    )

    $records = @(
        Ensure-Array (Get-CimSafe -ClassName 'Win32_ReliabilityRecords') |
            Sort-Object TimeGenerated -Descending |
            Select-Object -First 120 |
            ForEach-Object {
                [pscustomobject]@{
                    time_generated = (Convert-TimeValueSafe -Value $_.TimeGenerated)
                    source_name = $_.SourceName
                    event_identifier = $_.EventIdentifier
                    log_file = $_.LogFile
                    product_name = $_.ProductName
                    message = (ConvertTo-FlatText $_.Message)
                }
            }
    )

    [pscustomobject]@{
        metrics = @($metrics)
        records = @($records)
    }
}

function Get-ConfigAudit {
    $crashDumpEnabled = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled'
    $tdrDelay = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'TdrDelay'
    $tdrDdiDelay = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'TdrDdiDelay'
    $hags = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
    $hibernateEnabled = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
    $fastStartupEnabled = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled'
    $powerPlan = Get-ActivePowerPlanInfo

    [ordered]@{
        power_plan = $powerPlan
        fast_startup_enabled = (Convert-RegistryFlagToState -Value $fastStartupEnabled -Map @{ '0' = 'disabled'; '1' = 'enabled' })
        hibernation_enabled = (Convert-RegistryFlagToState -Value $hibernateEnabled -Map @{ '0' = 'disabled'; '1' = 'enabled' })
        crash_dump_enabled = $crashDumpEnabled
        tdr_delay = $tdrDelay
        tdr_ddi_delay = $tdrDdiDelay
        hardware_accelerated_gpu_scheduling = (Convert-RegistryFlagToState -Value $hags -Map @{ '1' = 'disabled'; '2' = 'enabled' })
        secure_boot = (Invoke-Safely -Fallback $null -ScriptBlock { Confirm-SecureBootUEFI })
        memory_integrity = (Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled')
        remote_desktop_enabled = (Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections')
    }
}

function Get-EventImpactArea {
    param([object]$EventRecord)

    $tags = @($EventRecord.diagnostic_tags)
    $provider = [string]$EventRecord.provider
    $paths = @($EventRecord.matched_categories | ForEach-Object { '{0}/{1}' -f $_.block, $_.category })

    if ($tags -contains 'storage_bad_block') { return 'Disk' }
    if ($tags -contains 'nvidia_driver_instability' -or $tags -contains 'gpu_instability') { return 'GPU' }
    if ($tags -contains 'bugcheck_bsod' -or $tags -contains 'crash_signal') { return 'OS' }
    if ($paths -contains 'Block7/services') { return 'Service' }
    if ($paths -contains 'Block3/kernel_pnp') { return 'Driver' }
    if ($paths -contains 'Block5/whea') { return 'Hardware' }
    if ($provider -like '*WindowsUpdateClient*') { return 'Update' }
    if ($provider -eq 'Service Control Manager') { return 'Service' }
    'Driver'
}

function Get-EventSeverityEffective {
    param([object]$EventRecord)

    $tags = @($EventRecord.diagnostic_tags)
    $provider = [string]$EventRecord.provider
    $eventId = [string]$EventRecord.event_id

    if ($tags -contains 'storage_bad_block') { return 'high' }
    if ($tags -contains 'bugcheck_bsod') { return 'high' }
    if ($provider -like '*Kernel-Power*' -and $eventId -eq '41') { return 'high' }
    if ($tags -contains 'nvidia_driver_instability') { return 'high' }
    if ($provider -eq 'Service Control Manager') { return 'medium' }
    if ($provider -like '*WindowsUpdateClient*') { return 'medium' }
    if ($EventRecord.severity -eq 'Critical') { return 'high' }
    if ($EventRecord.severity -eq 'Error') { return 'medium' }
    'low'
}

function Get-EventConfidence {
    param([object]$EventRecord)

    if ($EventRecord.message_source -eq 'message') { return 'high' }
    if ($EventRecord.message_source -eq 'synthesized') { return 'medium' }
    if ($EventRecord.message_source -in @('event_data', 'properties')) { return 'medium' }
    'low'
}

function Get-EventExplanation {
    param([object]$EventRecord)

    $impact = Get-EventImpactArea -EventRecord $EventRecord
    $causes = @($EventRecord.probable_causes)
    if ($causes.Count -gt 0) {
        return $causes[0]
    }
    'Событие требует дополнительной интерпретации в контексте подсистемы ' + $impact + '.'
}

function Get-EventRecommendation {
    param([object]$EventRecord)

    $tags = @($EventRecord.diagnostic_tags)
    $provider = [string]$EventRecord.provider

    if ($tags -contains 'storage_bad_block') {
        return 'Сохранить бэкап, проверить SMART/NVMe health, исключить деградацию диска и готовить замену накопителя при подтверждении.'
    }
    if ($tags -contains 'nvidia_driver_instability') {
        return 'Проверить чистоту GPU-драйверного стека, сверить PnP и nvidia-smi, исключить ghost devices и сбои драйвера.'
    }
    if ($tags -contains 'bugcheck_bsod') {
        return 'Проверить minidump и stop code, сопоставить с драйверами GPU/диска и недавними изменениями системы.'
    }
    if ($provider -eq 'Service Control Manager') {
        return 'Проверить зависимые службы и компоненты, которые могли не запуститься или зависнуть по таймауту.'
    }
    if ($provider -like '*WindowsUpdateClient*') {
        return 'Повторить установку после завершения фоновых установок и закрытия приложений, удерживающих пакет.'
    }
    'Использовать событие как часть общей корреляции инцидента, а не как единственный источник вывода.'
}

function Convert-EventToRecentIssue {
    param([object]$EventRecord)

    [pscustomobject]@{
        timestamp = $EventRecord.timestamp
        provider = $EventRecord.provider
        event_id = $EventRecord.event_id
        category = @($EventRecord.matched_categories | ForEach-Object { '{0}/{1}' -f $_.block, $_.category })
        subsystem = (Get-EventImpactArea -EventRecord $EventRecord)
        full_message = $EventRecord.message
        severity_raw = $EventRecord.severity
        severity_effective = (Get-EventSeverityEffective -EventRecord $EventRecord)
        confidence = (Get-EventConfidence -EventRecord $EventRecord)
        impact_area = (Get-EventImpactArea -EventRecord $EventRecord)
        human_explanation = (Get-EventExplanation -EventRecord $EventRecord)
        probable_cause = (@($EventRecord.probable_causes) -join ' ')
        recommendation = (Get-EventRecommendation -EventRecord $EventRecord)
        criticality = (Get-EventSeverityEffective -EventRecord $EventRecord)
        business_impact = $(switch (Get-EventImpactArea -EventRecord $EventRecord) {
            'GPU' { 'Может влиять на рендер, вывод изображения и стабильность графического стека.' }
            'Disk' { 'Может влиять на сохранность данных, чтение файлов, дампы и общую стабильность узла.' }
            'Service' { 'Может влиять на фоновые агенты, automation и доступность сервисов.' }
            'OS' { 'Может влиять на общую стабильность и приводить к аварийным перезапускам.' }
            default { 'Требует оценки в контексте остальных событий и конфигурации узла.' }
        })
    }
}

function Get-ReportSafeMachineName {
    param([string]$MachineName)

    $candidate = [string]$MachineName
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:COMPUTERNAME
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = 'UnknownMachine'
    }

    (($candidate -replace '[^A-Za-z0-9\-_]+', '_').Trim('_'))
}

function New-AnalizeReportMetadata {
    param(
        [string]$RootPath,
        [string]$MachineName,
        [datetime]$GeneratedAt
    )

    $reportsRoot = Join-Path -Path $RootPath -ChildPath 'Reports'
    if (-not (Test-Path -Path $reportsRoot)) {
        New-Item -Path $reportsRoot -ItemType Directory -Force | Out-Null
    }

    $safeMachineName = Get-ReportSafeMachineName -MachineName $MachineName
    $datePart = $GeneratedAt.ToString('yyyy-MM-dd')
    $timePart = $GeneratedAt.ToString('HH-mm-ss')
    $reportFileName = 'Analize_{0}_{1}_{2}.txt' -f $safeMachineName, $datePart, $timePart
    $latestFileName = 'Analize_{0}_latest.txt' -f $safeMachineName

    [pscustomobject]@{
        reports_root = $reportsRoot
        report_file_name = $reportFileName
        report_basename = [System.IO.Path]::GetFileNameWithoutExtension($reportFileName)
        report_path = (Join-Path -Path $reportsRoot -ChildPath $reportFileName)
        latest_report_path = (Join-Path -Path $reportsRoot -ChildPath $latestFileName)
    }
}

function Get-EventFieldValue {
    param(
        [object[]]$Fields,
        [string[]]$Names
    )

    foreach ($name in @(Ensure-Array $Names)) {
        $matched = @($Fields | Where-Object { $_.name -eq $name } | Select-Object -First 1)
        if ($matched.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$matched[0].value)) {
            return [string]$matched[0].value
        }
    }

    $null
}

function Get-SecurityLogonTypeLabel {
    param([string]$LogonType)

    switch ([string]$LogonType) {
        '2' { 'interactive' }
        '3' { 'network' }
        '4' { 'batch' }
        '5' { 'service' }
        '7' { 'unlock' }
        '8' { 'network_cleartext' }
        '9' { 'new_credentials' }
        '10' { 'remote_interactive_rdp' }
        '11' { 'cached_interactive' }
        default { $null }
    }
}

function Get-SecuritySeverity {
    param(
        [string]$EventId,
        [string]$LevelDisplayName
    )

    if ($EventId -in @('1102', '4697', '4719', '4720', '4722', '4723', '4724', '4725', '4726', '4738', '4740', '7045')) {
        return 'high'
    }
    if ($EventId -in @('4625', '5157', '4771', '4776')) {
        return 'medium'
    }
    if (-not [string]::IsNullOrWhiteSpace($LevelDisplayName)) {
        return ([string]$LevelDisplayName).ToLower()
    }
    'informational'
}

function Get-SecurityCategoryInfo {
    param(
        [string]$Provider,
        [string]$EventId,
        [string]$LogName,
        [string]$LogonType
    )

    $category = 'security'
    $subcategory = 'general'
    $action = 'observed'

    switch ([string]$EventId) {
        '4624' {
            $category = 'authentication'
            $subcategory = if ($LogonType -eq '10') { 'rdp_successful_logon' } else { 'successful_logon' }
            $action = 'success'
        }
        '4625' {
            $category = 'authentication'
            $subcategory = if ($LogonType -eq '10') { 'rdp_failed_logon' } else { 'failed_logon' }
            $action = 'failed'
        }
        '4634' {
            $category = 'authentication'
            $subcategory = 'logoff'
            $action = 'success'
        }
        '4647' {
            $category = 'authentication'
            $subcategory = 'user_initiated_logoff'
            $action = 'success'
        }
        '4648' {
            $category = 'authentication'
            $subcategory = 'explicit_credentials'
            $action = 'observed'
        }
        '4672' {
            $category = 'privilege'
            $subcategory = 'special_privileges_assigned'
            $action = 'success'
        }
        '4740' {
            $category = 'account'
            $subcategory = 'account_lockout'
            $action = 'blocked'
        }
        '4768' {
            $category = 'authentication'
            $subcategory = 'kerberos_tgt_request'
            $action = 'success'
        }
        '4769' {
            $category = 'authentication'
            $subcategory = 'kerberos_service_ticket'
            $action = 'success'
        }
        '4771' {
            $category = 'authentication'
            $subcategory = 'kerberos_preauth_failed'
            $action = 'failed'
        }
        '4776' {
            $category = 'authentication'
            $subcategory = 'credential_validation'
            $action = 'observed'
        }
        '4778' {
            $category = 'remote_access'
            $subcategory = 'session_reconnect'
            $action = 'success'
        }
        '4779' {
            $category = 'remote_access'
            $subcategory = 'session_disconnect'
            $action = 'success'
        }
        '4800' {
            $category = 'session'
            $subcategory = 'workstation_lock'
            $action = 'success'
        }
        '4801' {
            $category = 'session'
            $subcategory = 'workstation_unlock'
            $action = 'success'
        }
        '5152' {
            $category = 'firewall'
            $subcategory = 'wfp_packet_drop'
            $action = 'blocked'
        }
        '5154' {
            $category = 'firewall'
            $subcategory = 'listening_port_allowed'
            $action = 'allowed'
        }
        '5156' {
            $category = 'firewall'
            $subcategory = 'connection_allowed'
            $action = 'allowed'
        }
        '5157' {
            $category = 'firewall'
            $subcategory = 'connection_blocked'
            $action = 'blocked'
        }
        '4719' {
            $category = 'security_configuration'
            $subcategory = 'audit_policy_changed'
            $action = 'changed'
        }
        '4697' {
            $category = 'security_configuration'
            $subcategory = 'service_installed'
            $action = 'changed'
        }
        '7045' {
            $category = 'security_configuration'
            $subcategory = 'service_installed_system'
            $action = 'changed'
        }
        '1102' {
            $category = 'security_configuration'
            $subcategory = 'audit_log_cleared'
            $action = 'changed'
        }
        '1149' {
            $category = 'remote_access'
            $subcategory = 'rdp_authentication'
            $action = 'success'
        }
        default {
            if ($LogName -like '*Firewall*') {
                $category = 'firewall'
                $subcategory = 'firewall_event'
            }
            elseif ($Provider -like '*LocalSessionManager*' -or $Provider -like '*RemoteConnectionManager*') {
                $category = 'remote_access'
                $subcategory = 'terminal_services'
            }
            elseif ($Provider -like '*Windows Defender*') {
                $category = 'defender'
                $subcategory = 'defender_event'
            }
        }
    }

    [pscustomobject]@{
        category = $category
        subcategory = $subcategory
        action = $action
    }
}

function Get-SecurityExplanation {
    param(
        [object]$CategoryInfo,
        [string]$EventId,
        [string]$SourceIp,
        [string]$TargetPort,
        [string]$Username
    )

    switch ([string]$EventId) {
        '4624' { 'Зафиксирован успешный вход в систему.' }
        '4625' { 'Зафиксирована неуспешная попытка входа в систему.' }
        '4672' { 'Учетной записи были назначены привилегии повышенного уровня.' }
        '4740' { 'Произошла блокировка учетной записи после неудачных попыток входа или административного действия.' }
        '4778' { 'Сеанс был переподключен, что часто встречается при RDP.' }
        '4779' { 'Сеанс был отключен или разорван.' }
        '5157' { 'Брандмауэр или Windows Filtering Platform заблокировали сетевое соединение.' }
        '4719' { 'Изменена политика аудита безопасности системы.' }
        '4697' { 'Установлена новая служба через Security log.' }
        '7045' { 'В System log зарегистрирована установка новой службы.' }
        '1102' { 'Журнал аудита безопасности был очищен.' }
        '1149' { 'Успешная аутентификация через Remote Desktop Services.' }
        default {
            if ($CategoryInfo.category -eq 'firewall' -and -not [string]::IsNullOrWhiteSpace($TargetPort)) {
                return 'Сетевое событие брандмауэра для локального порта {0}.' -f $TargetPort
            }
            if ($CategoryInfo.category -eq 'remote_access' -and -not [string]::IsNullOrWhiteSpace($SourceIp)) {
                return 'Событие удаленного доступа, связанное с адресом {0}.' -f $SourceIp
            }
            if (-not [string]::IsNullOrWhiteSpace($Username)) {
                return 'Событие безопасности затрагивает учетную запись {0}.' -f $Username
            }
            'Событие безопасности требует дополнительной ручной интерпретации.'
        }
    }
}

function Get-SecurityCriticality {
    param(
        [string]$EventId,
        [string]$Action,
        [string]$TargetPort
    )

    if ($EventId -in @('1102', '4719', '4697', '7045', '4740')) { return 'high' }
    if ($EventId -eq '5157' -and $TargetPort -in @('3389', '5985', '5986', '22')) { return 'high' }
    if ($EventId -eq '4625') { return 'medium' }
    if ($Action -eq 'blocked') { return 'medium' }
    'low'
}

function Get-SecurityConfidence {
    param(
        [string]$SourceIp,
        [string]$Username,
        [string]$EventId
    )

    if ($EventId -in @('1102', '4719', '4697', '7045')) { return 'high' }
    if (-not [string]::IsNullOrWhiteSpace($SourceIp) -and -not [string]::IsNullOrWhiteSpace($Username)) { return 'high' }
    if (-not [string]::IsNullOrWhiteSpace($Username)) { return 'medium' }
    'low'
}

function Get-SecurityRecommendation {
    param(
        [string]$EventId,
        [string]$TargetPort,
        [string]$SourceIp
    )

    switch ([string]$EventId) {
        '4625' { 'Проверить источник попытки входа, корректность пароля и наличие серии неудачных авторизаций с этого пользователя/IP.' }
        '4740' { 'Выяснить, кто вызвал блокировку учетной записи, и сверить это с журналами неуспешных входов.' }
        '5157' {
            if ($TargetPort -in @('3389', '5985', '5986', '22')) {
                return 'Проверить, был ли это ожидаемый удаленный доступ; при повторении с одного источника рассматривать как probing/bruteforce candidate.'
            }
            'Проверить локальный порт, процесс и контекст блокировки в политике брандмауэра.'
        }
        '4719' { 'Проверить, кто и зачем менял политику аудита; подтвердить соответствие базовой конфигурации безопасности.' }
        '4697' { 'Проверить происхождение новой службы, путь к исполняемому файлу и необходимость ее установки.' }
        '7045' { 'Проверить установившуюся службу, подпись файла и связанный процесс/пакет.' }
        '1102' { 'Немедленно проверить, кто очистил Security log, и сохранить остальные журналы до ротации.' }
        '1149' { 'Сопоставить это событие с 4624 LogonType 10 и последующим поведением пользователя/сессии.' }
        default {
            if (-not [string]::IsNullOrWhiteSpace($SourceIp)) {
                return 'Сопоставить событие с активностью источника {0} и проверить, является ли оно ожидаемым.' -f $SourceIp
            }
            'Использовать событие как часть security-корреляции, а не как изолированный индикатор.'
        }
    }
}

function Convert-EventToSecurityRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Event,
        [string]$MachineName
    )

    $fields = @(Get-EventDataFields -Event $Event)
    $provider = Invoke-Safely -Fallback '' -ScriptBlock { [string]$Event.ProviderName }
    $eventId = Invoke-Safely -Fallback '' -ScriptBlock { [string]$Event.Id }
    $channel = Invoke-Safely -Fallback '' -ScriptBlock { [string]$Event.LogName }
    $messageInfo = Get-EventMessageForAnalysis -Event $Event
    $username = Get-EventFieldValue -Fields $fields -Names @('TargetUserName', 'SubjectUserName', 'Param1', 'User', 'UserDataUser')
    $domain = Get-EventFieldValue -Fields $fields -Names @('TargetDomainName', 'SubjectDomainName', 'Param2')
    $logonType = Get-EventFieldValue -Fields $fields -Names @('LogonType')
    $sessionId = Get-EventFieldValue -Fields $fields -Names @('TargetLogonId', 'SessionID', 'SessionId')
    $sourceIp = Get-EventFieldValue -Fields $fields -Names @('IpAddress', 'ClientAddress', 'Address', 'SourceAddress')
    $sourceHost = Get-EventFieldValue -Fields $fields -Names @('WorkstationName', 'ClientName')
    $port = Get-EventFieldValue -Fields $fields -Names @('IpPort', 'SourcePort')
    $processName = Get-EventFieldValue -Fields $fields -Names @('ProcessName', 'Application', 'Image')
    $targetAccount = Get-EventFieldValue -Fields $fields -Names @('TargetUserName', 'TargetAccount', 'AccountName')
    $targetPort = Get-EventFieldValue -Fields $fields -Names @('DestPort', 'DestinationPort', 'TargetPort')
    $direction = Get-EventFieldValue -Fields $fields -Names @('Direction')
    $categoryInfo = Get-SecurityCategoryInfo -Provider $provider -EventId $eventId -LogName $channel -LogonType $logonType
    $humanExplanation = Get-SecurityExplanation -CategoryInfo $categoryInfo -EventId $eventId -SourceIp $sourceIp -TargetPort $targetPort -Username $username
    $criticality = Get-SecurityCriticality -EventId $eventId -Action $categoryInfo.action -TargetPort $targetPort
    $confidence = Get-SecurityConfidence -SourceIp $sourceIp -Username $username -EventId $eventId
    $normalizedLogonType = if ([string]::IsNullOrWhiteSpace($logonType)) { $null } else { '{0} ({1})' -f $logonType, (Get-SecurityLogonTypeLabel -LogonType $logonType) }

    [pscustomobject]@{
        timestamp = (Convert-ToUtcText -Value $Event.TimeCreated)
        provider = $provider
        event_id = $eventId
        channel = $channel
        severity = (Get-SecuritySeverity -EventId $eventId -LevelDisplayName ([string]$Event.LevelDisplayName))
        category = $categoryInfo.category
        subcategory = $categoryInfo.subcategory
        machine = $(if ([string]::IsNullOrWhiteSpace($MachineName)) { $env:COMPUTERNAME } else { $MachineName })
        username = $username
        domain = $domain
        logon_type = $normalizedLogonType
        session_id = $sessionId
        source_ip = $sourceIp
        source_host = $sourceHost
        port = $port
        process_name = $processName
        target_account = $targetAccount
        target_port = $targetPort
        direction = $direction
        action = $categoryInfo.action
        full_message = [string]$messageInfo.text
        human_explanation = $humanExplanation
        criticality = $criticality
        confidence = $confidence
        recommendation = (Get-SecurityRecommendation -EventId $eventId -TargetPort $targetPort -SourceIp $sourceIp)
        event_data = @($fields)
    }
}

function Test-OffHoursTimestamp {
    param([string]$Timestamp)

    $parsed = Invoke-Safely -Fallback $null -ScriptBlock { [datetime]::ParseExact($Timestamp, 'yyyy-MM-dd HH:mm:ss', $null) }
    if ($null -eq $parsed) {
        return $false
    }

    ($parsed.Hour -lt 6 -or $parsed.Hour -ge 21)
}

function Get-SecurityAuditData {
    param(
        [datetime]$StartTime,
        [string]$MachineName
    )

    $securityIds = @(4624, 4625, 4634, 4647, 4648, 4672, 4697, 4719, 4720, 4722, 4723, 4724, 4725, 4726, 4738, 4740, 4768, 4769, 4771, 4776, 4778, 4779, 4800, 4801, 5152, 5154, 5156, 5157, 1102)
    $systemIds = @(7045)
    $rdpManagerIds = @(1149)
    $rdpSessionIds = @(21, 22, 23, 24, 25, 39, 40)

    $rawEvents = @()
    $rawEvents += @(Get-ExactIdEvents -LogNames @('Security') -StartTime $StartTime -Ids $securityIds -MaxPerLog 4000)
    $rawEvents += @(Get-ExactIdEvents -LogNames @('System') -StartTime $StartTime -Ids $systemIds -MaxPerLog 600)
    $rawEvents += @(Get-ExactIdEvents -LogNames @('Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational') -StartTime $StartTime -Ids $rdpManagerIds -MaxPerLog 1000)
    $rawEvents += @(Get-ExactIdEvents -LogNames @('Microsoft-Windows-TerminalServices-LocalSessionManager/Operational') -StartTime $StartTime -Ids $rdpSessionIds -MaxPerLog 1200)
    $rawEvents += @(Get-ExactProviderIdEvents -LogNames @('Microsoft-Windows-Windows Defender/Operational') -StartTime $StartTime -ProviderNames @('Microsoft-Windows-Windows Defender') -MaxPerLog 300)
    $rawEvents += @(Get-FilteredEvents -LogNames @('Microsoft-Windows-Windows Firewall With Advanced Security/Firewall') -StartTime $StartTime -Levels @(1, 2, 3, 4) -MaxPerLog 400)

    $records = @(
        $rawEvents |
            Sort-Object TimeCreated -Descending |
            ForEach-Object { Convert-EventToSecurityRecord -Event $_ -MachineName $MachineName }
    )

    $failedLogons = @($records | Where-Object { $_.event_id -eq '4625' })
    $rdpLogonActivity = @($records | Where-Object { $_.event_id -in @('1149', '4624', '4778', '4779', '21', '22', '23', '24', '25', '39', '40') -and ($_.subcategory -like 'rdp*' -or $_.logon_type -like '10*' -or $_.category -eq 'remote_access') })
    $successfulRemoteAccess = @($records | Where-Object { ($_.event_id -eq '1149') -or ($_.event_id -eq '4624' -and $_.logon_type -like '10*') })
    $firewallAndPortActivity = @($records | Where-Object { $_.category -eq 'firewall' })
    $securityConfigurationAudit = @($records | Where-Object { $_.category -eq 'security_configuration' })
    $accountAndPrivilegeEvents = @($records | Where-Object { $_.event_id -in @('4672', '4740', '4720', '4722', '4723', '4724', '4725', '4726', '4738') })

    $findings = New-List
    $recommendedActions = New-Object System.Collections.Generic.List[string]

    $failedGroups = @(
        $failedLogons |
            Group-Object {
                $userKey = if ([string]::IsNullOrWhiteSpace($_.username)) { 'unknown_user' } else { $_.username }
                $ipKey = if ([string]::IsNullOrWhiteSpace($_.source_ip)) { 'unknown_ip' } else { $_.source_ip }
                $window = Invoke-Safely -Fallback 'unknown' -ScriptBlock { ([datetime]::ParseExact($_.timestamp, 'yyyy-MM-dd HH:mm:ss', $null)).ToString('yyyy-MM-dd HH:mm') }
                '{0}|{1}|{2}' -f $userKey, $ipKey, $window
            } |
            Where-Object { $_.Count -ge 5 } |
            Sort-Object Count -Descending
    )

    foreach ($group in $failedGroups) {
        $sample = @($group.Group | Select-Object -First 1)[0]
        [void]$findings.Add([pscustomobject]@{
            id = 'possible_bruteforce'
            severity = 'high'
            title = 'Есть серия неуспешных входов, похожая на brute-force candidate'
            summary = ('За короткое окно найдено {0} неуспешных входов для пользователя {1} с IP {2}.' -f $group.Count, $(if ($sample.username) { $sample.username } else { 'unknown' }), $(if ($sample.source_ip) { $sample.source_ip } else { 'unknown' }))
            evidence = @($group.Group | Select-Object -First 10)
        })
        Add-UniqueText -Target $recommendedActions -Text 'Проверить серии 4625 по IP/пользователю и при необходимости ограничить источник на firewall/VPN/RDP gateway.'
    }

    $rdpSuccessCandidates = @(
        foreach ($authEvent in @($records | Where-Object { $_.event_id -eq '1149' })) {
            $authTime = Invoke-Safely -Fallback $null -ScriptBlock { [datetime]::ParseExact($authEvent.timestamp, 'yyyy-MM-dd HH:mm:ss', $null) }
            $matched = @(
                $records |
                    Where-Object {
                        $_.event_id -eq '4624' -and $_.logon_type -like '10*' -and
                        ($_.username -eq $authEvent.username -or [string]::IsNullOrWhiteSpace($authEvent.username) -or [string]::IsNullOrWhiteSpace($_.username)) -and
                        ($_.source_ip -eq $authEvent.source_ip -or [string]::IsNullOrWhiteSpace($authEvent.source_ip) -or [string]::IsNullOrWhiteSpace($_.source_ip))
                    } |
                    Where-Object {
                        $candidateTime = Invoke-Safely -Fallback $null -ScriptBlock { [datetime]::ParseExact($_.timestamp, 'yyyy-MM-dd HH:mm:ss', $null) }
                        $authTime -and $candidateTime -and ([math]::Abs(($candidateTime - $authTime).TotalMinutes) -le 10)
                    } |
                    Select-Object -First 1
            )

            if ($matched.Count -gt 0) {
                [pscustomobject]@{
                    timestamp = $authEvent.timestamp
                    username = $authEvent.username
                    source_ip = $authEvent.source_ip
                    evidence = @($authEvent, $matched[0])
                }
            }
        }
    )

    if ($rdpSuccessCandidates.Count -gt 0) {
        [void]$findings.Add([pscustomobject]@{
            id = 'successful_rdp_login'
            severity = 'medium'
            title = 'Обнаружены успешные RDP-входы с корреляцией 1149 + 4624 LogonType 10'
            summary = ('Найдено {0} подтвержденных RDP-сессий за выбранный период.' -f $rdpSuccessCandidates.Count)
            evidence = @($rdpSuccessCandidates | Select-Object -First 10)
        })
        Add-UniqueText -Target $recommendedActions -Text 'Проверить, все ли успешные RDP-сессии ожидаемы, особенно вне рабочего времени и с внешних IP.'
    }

    $blockedRemoteAccess = @(
        $firewallAndPortActivity |
            Where-Object { $_.event_id -eq '5157' -and $_.target_port -in @('3389', '5985', '5986', '22') }
    )
    if ($blockedRemoteAccess.Count -gt 0) {
        [void]$findings.Add([pscustomobject]@{
            id = 'blocked_remote_access_attempt'
            severity = 'medium'
            title = 'Есть заблокированные попытки удаленного доступа на чувствительные порты'
            summary = ('Найдено {0} blocked events 5157 на RDP/WinRM/SSH-порты.' -f $blockedRemoteAccess.Count)
            evidence = @($blockedRemoteAccess | Select-Object -First 15)
        })
        Add-UniqueText -Target $recommendedActions -Text 'Проверить источник и частоту 5157 на 3389/5985/5986/22; повторение с одного IP рассматривать как probing.'
    }

    $highRiskConfigEvents = @($securityConfigurationAudit | Where-Object { $_.event_id -in @('1102', '4719', '4697', '7045') })
    if ($highRiskConfigEvents.Count -gt 0) {
        [void]$findings.Add([pscustomobject]@{
            id = 'security_configuration_alerts'
            severity = 'high'
            title = 'Есть события изменения security-конфигурации или установки служб'
            summary = ('Найдено {0} событий по audit policy / log cleared / service install.' -f $highRiskConfigEvents.Count)
            evidence = @($highRiskConfigEvents | Select-Object -First 15)
        })
        Add-UniqueText -Target $recommendedActions -Text 'Отдельно проверить события 1102/4719/4697/7045 и подтвердить, что они были санкционированы.'
    }

    $offHoursRemoteAccess = @($successfulRemoteAccess | Where-Object { Test-OffHoursTimestamp -Timestamp $_.timestamp })
    if ($offHoursRemoteAccess.Count -gt 0) {
        [void]$findings.Add([pscustomobject]@{
            id = 'offhours_remote_access'
            severity = 'medium'
            title = 'Есть успешный удаленный доступ в нерабочее время'
            summary = ('Найдено {0} успешных удаленных входов в диапазоне 21:00-06:00.' -f $offHoursRemoteAccess.Count)
            evidence = @($offHoursRemoteAccess | Select-Object -First 15)
        })
        Add-UniqueText -Target $recommendedActions -Text 'Проверить off-hours логины на соответствие ожидаемому admin/operations расписанию.'
    }

    $portProbeCandidates = @(
        $firewallAndPortActivity |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.target_port) } |
            Group-Object {
                $ipKey = if ([string]::IsNullOrWhiteSpace($_.source_ip)) { 'unknown_ip' } else { $_.source_ip }
                '{0}|{1}' -f $ipKey, $_.target_port
            } |
            Where-Object { $_.Count -ge 10 } |
            Sort-Object Count -Descending
    )
    foreach ($group in $portProbeCandidates | Select-Object -First 10) {
        $sample = @($group.Group | Select-Object -First 1)[0]
        [void]$findings.Add([pscustomobject]@{
            id = 'possible_port_scan'
            severity = 'medium'
            title = 'Есть повторяющиеся обращения к одному локальному порту'
            summary = ('Для порта {0} найдено {1} событий от источника {2}.' -f $sample.target_port, $group.Count, $(if ($sample.source_ip) { $sample.source_ip } else { 'unknown' }))
            evidence = @($group.Group | Select-Object -First 10)
        })
    }
    if ($portProbeCandidates.Count -gt 0) {
        Add-UniqueText -Target $recommendedActions -Text 'Проверить repeated firewall events по одному IP/порту и при необходимости включить дополнительную фильтрацию источника.'
    }

    if ($recommendedActions.Count -eq 0) {
        Add-UniqueText -Target $recommendedActions -Text 'Использовать recent_security_events и security_findings как базу для ручного security-разбора.'
    }

    $summary = [ordered]@{
        total_security_events = $records.Count
        failed_logon_count = $failedLogons.Count
        successful_remote_access_count = $successfulRemoteAccess.Count
        rdp_activity_count = $rdpLogonActivity.Count
        blocked_connection_count = @($firewallAndPortActivity | Where-Object { $_.action -eq 'blocked' }).Count
        allowed_connection_count = @($firewallAndPortActivity | Where-Object { $_.action -eq 'allowed' }).Count
        account_lockout_count = @($records | Where-Object { $_.event_id -eq '4740' }).Count
        privilege_event_count = @($records | Where-Object { $_.event_id -eq '4672' }).Count
        security_configuration_change_count = $securityConfigurationAudit.Count
        defender_event_count = @($records | Where-Object { $_.category -eq 'defender' }).Count
        distinct_source_ips = @($records | ForEach-Object { $_.source_ip } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique).Count
    }

    [pscustomobject]@{
        security_summary = $summary
        recent_security_events = @($records | Sort-Object timestamp -Descending | Select-Object -First 80)
        rdp_logon_activity = @($rdpLogonActivity | Sort-Object timestamp -Descending | Select-Object -First 80)
        failed_logons = @($failedLogons | Sort-Object timestamp -Descending | Select-Object -First 120)
        successful_remote_access = @($successfulRemoteAccess | Sort-Object timestamp -Descending | Select-Object -First 80)
        firewall_and_port_activity = @($firewallAndPortActivity | Sort-Object timestamp -Descending | Select-Object -First 120)
        security_configuration_audit = @($securityConfigurationAudit | Sort-Object timestamp -Descending | Select-Object -First 80)
        account_and_privilege_events = @($accountAndPrivilegeEvents | Sort-Object timestamp -Descending | Select-Object -First 80)
        security_findings = @($findings | ForEach-Object { $_ })
        top_security_risks = @(
            $findings |
                Sort-Object @{ Expression = {
                    switch ($_.severity) {
                        'high' { 0 }
                        'medium' { 1 }
                        default { 2 }
                    }
                } }, title |
                Select-Object -First 7 |
                ForEach-Object {
                    [pscustomobject]@{
                        severity = $_.severity
                        title = $_.title
                        summary = $_.summary
                    }
                }
        )
        recommended_security_actions = @($recommendedActions)
        raw_security_events = @($records)
    }
}

$selection = Read-AnalysisRange -InitialChoice $PeriodChoice
$outputRoot = Ensure-StatOutputRoot
$now = Get-Date
$reportMetadata = New-AnalizeReportMetadata -RootPath $outputRoot -MachineName $env:COMPUTERNAME -GeneratedAt $now
$outputPath = $reportMetadata.report_path

$os = Get-CimSafe -ClassName 'Win32_OperatingSystem'
$computerSystem = Get-CimSafe -ClassName 'Win32_ComputerSystem' | Select-Object -First 1
$bios = Get-CimSafe -ClassName 'Win32_BIOS' | Select-Object -First 1
$board = Get-CimSafe -ClassName 'Win32_BaseBoard' | Select-Object -First 1
$cpuList = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_Processor'))
$memoryModules = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_PhysicalMemory'))
$gpuList = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_VideoController'))
$diskList = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_DiskDrive'))
$partitionList = @(Ensure-Array (Invoke-Safely -Fallback @() -ScriptBlock { Get-Partition | Sort-Object DiskNumber, PartitionNumber }))
$networkConfigs = @(Ensure-Array (Invoke-Safely -Fallback @() -ScriptBlock { Get-NetIPConfiguration | Sort-Object InterfaceAlias }))
$drivers = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_PnPSignedDriver'))
$logicalDisks = @(Ensure-Array (Get-CimSafe -ClassName 'Win32_LogicalDisk' -Filter 'DriveType = 3'))

$featureNames = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Hyper-V',
    'VirtualMachinePlatform',
    'Microsoft-Windows-Subsystem-Linux',
    'HypervisorPlatform',
    'Containers'
)

$featureStates = @(Ensure-Array (Invoke-Safely -Fallback @() -ScriptBlock {
    foreach ($name in $featureNames) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
        [pscustomobject]@{
            name = $feature.FeatureName
            state = $feature.State
        }
    }
}))

$displayPnpDevices = @(Ensure-Array (Get-DisplayPnpInventory))
$nvidiaSmiGpus = @(Ensure-Array (Get-NvidiaSmiInventory))
$driversInventory = @(Ensure-Array (Get-DriversInventory -Drivers $drivers))
$storageHealthInventory = @(Ensure-Array (Get-StorageHealthInventory))
$reliabilityData = Get-ReliabilityMonitorData
$installedSoftware = @(Ensure-Array (Get-InstalledSoftwareInventory))
$serviceInventory = @(Ensure-Array (Get-ServiceInventory))
$scheduledTaskInventory = @(Ensure-Array (Get-ScheduledTaskInventory))
$startupInventory = @(Ensure-Array (Get-StartupInventory))
$windowsUpdateInventory = @(Ensure-Array (Get-WindowsUpdateInventory))
$networkAdapterInventory = @(Ensure-Array (Get-NetworkAdapterInventory))
$applicationCrashInventory = @(Ensure-Array (Get-ApplicationCrashInventory))
$driverUpdateHistory = @(Ensure-Array (Get-DriverUpdateHistory))
$conflictingSoftware = @(Ensure-Array (Get-PotentiallyConflictingSoftware -Software $installedSoftware))
$deadlineContext = Get-DeadlineContext -Software $installedSoftware -Services $serviceInventory -Tasks $scheduledTaskInventory -StartupItems $startupInventory
$configAudit = Get-ConfigAudit
$securityAudit = Get-SecurityAuditData -StartTime $selection.StartTime -MachineName $env:COMPUTERNAME

$eventMap = @{}

Add-DedupedEvents -Map $eventMap -Block 'Block2' -Category 'restart_shutdown_history' -Events (@(Get-ExactIdEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -Ids @(41, 1074, 6005, 6006, 6008, 1076, 109) -MaxPerLog 1500) | Select-Object -First 80)
Add-DedupedEvents -Map $eventMap -Block 'Block3' -Category 'general_driver_errors' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)\bdriver\b') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block3' -Category 'device_initialization_failures' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MessagePatterns @('(?i)(device|driver).*(failed|failure|not started|problem|unable|could not|did not load)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block3' -Category 'driver_install_update_issues' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*UserPnp*', '*DeviceSetupManager*', '*SetupAPI*') -MessagePatterns @('(?i)(install|update|package|migration|driver package|rollback)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block3' -Category 'kernel_pnp' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Kernel-PnP*', '*UserPnp*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'display' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Display', '*Display*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'nvidia' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('nvlddmkm', '*NVIDIA*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'nvidia_153' -Events (@(Get-ExactProviderIdEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3) -Ids @(153) -ProviderNames @('nvlddmkm') -MaxPerLog 1000) | Select-Object -First 120)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'amd' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('amdkmdag', 'amdwddmg', '*AMD*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'directx_dxgkrnl' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*DxgKrnl*', '*DirectX*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block4' -Category 'tdr_timeout' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(TDR|timeout detection|display driver stopped responding|LiveKernelEvent 117|LiveKernelEvent 141|graphics timeout|GPU timeout)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block5' -Category 'whea' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*WHEA*') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block5' -Category 'pcie' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(PCI Express|PCIe|PCI)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block5' -Category 'bus_interconnect' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(bus error|interconnect|fabric|link failure|link degraded)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block5' -Category 'hardware_corrected_uncorrected' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(corrected hardware error|uncorrected hardware error|fatal hardware error|machine check|cache hierarchy error)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block6' -Category 'bugcheck_bsod' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*BugCheck*', '*WER-SystemErrorReporting*', '*Windows Error Reporting*') -MessagePatterns @('(?i)(bugcheck|blue screen|stop code)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block6' -Category 'system_1001_bugcheck' -Events (@(Get-ExactIdEvents -LogNames @('System') -StartTime $selection.StartTime -Ids @(1001) -MaxPerLog 1000 | Where-Object { $_.Message -match '(?i)(bugcheck|blue screen|dump)' }) | Select-Object -First 120)
Add-DedupedEvents -Map $eventMap -Block 'Block6' -Category 'kernel_power' -Events (@(Get-ExactIdEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -Ids @(41, 109) -MaxPerLog 1000 | Where-Object { $_.ProviderName -like '*Kernel-Power*' }) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block6' -Category 'unexpected_shutdown' -Events (@(Get-ExactIdEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3, 4) -Ids @(6008, 1074, 1076) -MaxPerLog 1000) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block6' -Category 'live_kernel' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -MessagePatterns @('(?i)(LiveKernelEvent|live kernel)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'storage' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('disk', 'storahci', 'stornvme', 'iaStorA', 'iaStorV', 'volmgr', 'partmgr') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'storage_bad_block' -Events (@(Get-ExactProviderIdEvents -LogNames @('System') -StartTime $selection.StartTime -Levels @(1, 2, 3) -Ids @(7) -ProviderNames @('disk') -MaxPerLog 1000 | Where-Object { $_.Message -match '(?i)bad block' }) | Select-Object -First 80)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'filesystem' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Ntfs', 'ReFS', 'Wininit', 'Chkdsk') -MessagePatterns @('(?i)(corrupt|corruption|bad block|file system|dirty bit|volume)') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'services' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('Service Control Manager') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'defender' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*Windows Defender*', 'WinDefend') -MaxPerLog 250) | Select-Object -First 60)
Add-DedupedEvents -Map $eventMap -Block 'Block7' -Category 'windows_update' -Events (@(Get-FilteredEvents -StartTime $selection.StartTime -Levels @(1, 2, 3) -ProviderPatterns @('*WindowsUpdateClient*') -MaxPerLog 250) | Select-Object -First 60)

$events = @(
    foreach ($eventKey in ($eventMap.Keys | Sort-Object)) {
        $eventRecord = $eventMap[$eventKey]
        $heuristics = Get-EventHeuristics -EventRecord $eventRecord

        [pscustomobject]@{
            event_key = $eventRecord.event_key
            timestamp = $eventRecord.timestamp
            provider = $eventRecord.provider
            event_id = $eventRecord.event_id
            severity = $eventRecord.severity
            log = $eventRecord.log
            message = $eventRecord.message
            message_source = $eventRecord.message_source
            event_data = @($eventRecord.event_data)
            properties = @($eventRecord.properties)
            matched_categories = @($eventRecord.matched_categories | Sort-Object block, category)
            diagnostic_tags = @($heuristics.diagnostic_tags)
            probable_causes = @($heuristics.probable_causes)
        }
    }
)

$block2Events = @(Get-FilteredEvents -LogNames @('System', 'Application') -StartTime $selection.StartTime -Levels @(1, 2, 3) -MaxPerLog 1200)
$block2Summary = @(
    $block2Events | ForEach-Object {
        [pscustomobject]@{
            level = (Invoke-Safely -Fallback 'Unknown' -ScriptBlock { [string]$_.LevelDisplayName })
            provider = (Invoke-Safely -Fallback 'Unknown' -ScriptBlock { [string]$_.ProviderName })
        }
    }
)

$eventSummaryByLevel = @(
    $block2Summary |
        Group-Object level |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                count = $_.Count
            }
        }
)

$eventSummaryByProvider = @(
    $block2Summary |
        Group-Object provider |
        Sort-Object Count -Descending |
        Select-Object -First 30 |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                count = $_.Count
            }
        }
)

$eventCategoriesPresent = @(
    $events |
        ForEach-Object { $_.matched_categories } |
        ForEach-Object { '{0}/{1}' -f $_.block, $_.category } |
        Sort-Object -Unique
)

$trackedCategories = @(
    'Block2/restart_shutdown_history',
    'Block3/general_driver_errors',
    'Block3/device_initialization_failures',
    'Block3/driver_install_update_issues',
    'Block3/kernel_pnp',
    'Block4/display',
    'Block4/nvidia',
    'Block4/nvidia_153',
    'Block4/amd',
    'Block4/directx_dxgkrnl',
    'Block4/tdr_timeout',
    'Block5/whea',
    'Block5/pcie',
    'Block5/bus_interconnect',
    'Block5/hardware_corrected_uncorrected',
    'Block6/bugcheck_bsod',
    'Block6/system_1001_bugcheck',
    'Block6/kernel_power',
    'Block6/unexpected_shutdown',
    'Block6/live_kernel',
    'Block7/storage',
    'Block7/storage_bad_block',
    'Block7/filesystem',
    'Block7/services',
    'Block7/defender',
    'Block7/windows_update'
)

$emptyCategories = @(
    foreach ($categoryPath in $trackedCategories) {
        if ($eventCategoriesPresent -notcontains $categoryPath) {
            $parts = $categoryPath.Split('/')
            [pscustomobject]@{
                block = $parts[0]
                category = $parts[1]
                status = 'no_matching_events_in_selected_period'
            }
        }
    }
)

$memoryDump = 'C:\Windows\MEMORY.DMP'
$miniDumpDir = 'C:\Windows\Minidump'
$dumpStatus = [pscustomobject]@{
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
}

$cpuProfile = @(
    $cpuList | ForEach-Object {
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
    }
)

$memoryProfile = @(
    $memoryModules | ForEach-Object {
        [pscustomobject]@{
            slot = $_.DeviceLocator
            capacity_bytes = $_.Capacity
            speed_mhz = $_.Speed
            manufacturer = $_.Manufacturer
            part_number = $_.PartNumber
        }
    }
)

$gpuProfile = @(
    $gpuList | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            driver_version = $_.DriverVersion
            driver_date = (Invoke-Safely -Fallback $null -ScriptBlock { $_.DriverDate.ToString('yyyy-MM-dd HH:mm:ss') })
            adapter_ram = $_.AdapterRAM
            video_processor = $_.VideoProcessor
        }
    }
)

$diskProfile = @(
    $diskList | ForEach-Object {
        [pscustomobject]@{
            model = $_.Model
            interface = $_.InterfaceType
            size_bytes = $_.Size
            status = $_.Status
        }
    }
)

$partitionProfile = @(
    $partitionList | ForEach-Object {
        [pscustomobject]@{
            disk_number = $_.DiskNumber
            partition_number = $_.PartitionNumber
            drive_letter = $_.DriveLetter
            size_bytes = $_.Size
            type = $_.Type
        }
    }
)

$networkProfile = @(
    $networkConfigs | ForEach-Object {
        [pscustomobject]@{
            adapter = $_.InterfaceAlias
            ipv4 = @($_.IPv4Address | ForEach-Object { $_.IPAddress })
            ipv6 = @($_.IPv6Address | ForEach-Object { $_.IPAddress })
            gateway = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
            dns = @($_.DnsServer.ServerAddresses)
        }
    }
)

$driversSample = @($driversInventory | Select-Object -First 20)

$diskUsage = @(
    $logicalDisks | ForEach-Object {
        [pscustomobject]@{
            drive = $_.DeviceID
            volume = $_.VolumeName
            total_bytes = $_.Size
            free_bytes = $_.FreeSpace
            used_bytes = ([double]$_.Size - [double]$_.FreeSpace)
        }
    }
)

$bootTime = Invoke-Safely -Fallback $null -ScriptBlock { $os.LastBootUpTime }
$runtimeData = [pscustomobject]@{}
if ($os) {
    $totalRam = [double]$os.TotalVisibleMemorySize * 1KB
    $freeRam = [double]$os.FreePhysicalMemory * 1KB
    $uptimeText = Invoke-Safely -Fallback $null -ScriptBlock {
        if ($bootTime -is [datetime]) {
            return ($now - $bootTime).ToString()
        }

        $parsedBoot = [Management.ManagementDateTimeConverter]::ToDateTime([string]$bootTime)
        ($now - $parsedBoot).ToString()
    }

    $runtimeData = [pscustomobject]@{
        boot_time = (Invoke-Safely -Fallback $null -ScriptBlock {
            if ($bootTime -is [datetime]) {
                return $bootTime.ToString('yyyy-MM-dd HH:mm:ss')
            }

            ([Management.ManagementDateTimeConverter]::ToDateTime([string]$bootTime)).ToString('yyyy-MM-dd HH:mm:ss')
        })
        uptime = $uptimeText
        memory_total_bytes = $totalRam
        memory_used_bytes = ($totalRam - $freeRam)
        memory_free_bytes = $freeRam
    }
}

$plannedRestartEvents = @(
    $events | Where-Object {
        $_.diagnostic_tags -contains 'planned_restart_signal'
    }
)

$crashSignalEvents = @(
    $events | Where-Object {
        $_.diagnostic_tags -contains 'crash_signal'
    }
)

$bugcheckEvents = @(
    $events | Where-Object {
        $_.diagnostic_tags -contains 'bugcheck_bsod'
    }
)

$bugcheckCorrelations = @(
    foreach ($event in $bugcheckEvents) {
        $eventTime = Invoke-Safely -Fallback $null -ScriptBlock { [datetime]::ParseExact($event.timestamp, 'yyyy-MM-dd HH:mm:ss', $null) }
        $bugcheckCode = Get-BugcheckCodeFromEventRecord -EventRecord $event
        $matchedDump = $null

        if ($eventTime -and $dumpStatus.minidumps.Count -gt 0) {
            $matchedDump = @(
                $dumpStatus.minidumps |
                    Where-Object {
                        $dumpTime = Invoke-Safely -Fallback $null -ScriptBlock { [datetime]::ParseExact($_.last_write, 'yyyy-MM-dd HH:mm:ss', $null) }
                        $dumpTime -and ([math]::Abs(($dumpTime - $eventTime).TotalHours) -le 48)
                    } |
                    Sort-Object {
                        $dumpTime = Invoke-Safely -Fallback $eventTime -ScriptBlock { [datetime]::ParseExact($_.last_write, 'yyyy-MM-dd HH:mm:ss', $null) }
                        [math]::Abs(($dumpTime - $eventTime).TotalMinutes)
                    } |
                    Select-Object -First 1
            )
        }

        [pscustomobject]@{
            timestamp = $event.timestamp
            provider = $event.provider
            event_id = $event.event_id
            bugcheck_code = $bugcheckCode
            interpretation = (Get-BugcheckInterpretation -Code $bugcheckCode)
            matched_minidump = $(if ($matchedDump) { $matchedDump.name } else { $null })
            matched_minidump_last_write = $(if ($matchedDump) { $matchedDump.last_write } else { $null })
            evidence_event_key = $event.event_key
            message = $event.message
        }
    }
)

$nvidia153Events = @(
    $events | Where-Object {
        $_.provider -eq 'nvlddmkm' -and $_.event_id -eq '153'
    }
)

$nvidia153ByDay = @(
    $nvidia153Events |
        Group-Object { $_.timestamp.Substring(0, 10) } |
        Sort-Object Name -Descending |
        ForEach-Object {
            [pscustomobject]@{
                date = $_.Name
                count = $_.Count
            }
        }
)

$storageBadBlockEvents = @(
    $events | Where-Object {
        $_.diagnostic_tags -contains 'storage_bad_block'
    }
)

$wheaEvents = @(
    $events | Where-Object {
        ($_.matched_categories | ForEach-Object { '{0}/{1}' -f $_.block, $_.category }) -contains 'Block5/whea'
    }
)

$pcieEvents = @(
    $events | Where-Object {
        $paths = @($_.matched_categories | ForEach-Object { '{0}/{1}' -f $_.block, $_.category })
        ($paths -contains 'Block5/pcie') -or ($paths -contains 'Block5/bus_interconnect')
    }
)

$pcieEventClassification = [ordered]@{}
$pcieEventClassification.driver_installation = @(
    $pcieEvents | Where-Object { $_.message -match '(?i)(install|driver package|configured|migrat|setup|device install)' }
)
$pcieEventClassification.network_adapter_resets = @(
    $pcieEvents | Where-Object { $_.message -match '(?i)(realtek|network|nic|adapter|reset|link is disconnected|link has been disconnected)' }
)
$pcieEventClassification.hardware_like = @(
    $pcieEvents | Where-Object { $_.message -match '(?i)(PCI Express|PCIe|bus error|link failure|link degraded|fatal|corrected hardware error|uncorrected hardware error)' }
)

$displayPnpAnomalies = @(
    $displayPnpDevices | Where-Object {
        $_.status -in @('Unknown', 'Error', 'Degraded') -or $_.friendly_name -match '(?i)unknown'
    }
)

$win32GpuNames = @($gpuProfile | ForEach-Object { $_.name } | Sort-Object -Unique)
$pnpDisplayNames = @($displayPnpDevices | ForEach-Object { $_.friendly_name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$nvidiaSmiNames = @($nvidiaSmiGpus | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

$gpuInventoryAssessment = [ordered]@{}
$gpuInventoryAssessment.win32_video_controller_names = $win32GpuNames
$gpuInventoryAssessment.pnp_display_names = $pnpDisplayNames
$gpuInventoryAssessment.nvidia_smi_names = $nvidiaSmiNames
$gpuInventoryAssessment.pnp_total = $displayPnpDevices.Count
$gpuInventoryAssessment.pnp_anomaly_count = $displayPnpAnomalies.Count
$gpuInventoryAssessment.nvidia_smi_gpu_count = $nvidiaSmiGpus.Count
$gpuInventoryAssessment.notes = @()
if ($displayPnpAnomalies.Count -gt 0) {
    $gpuInventoryAssessment.notes += 'В PnP есть display-устройства со статусом Unknown/Error/Degraded.'
}
if ($nvidiaSmiGpus.Count -gt 0 -and (($displayPnpDevices | Where-Object { $_.friendly_name -match '(?i)NVIDIA' }).Count -ne $nvidiaSmiGpus.Count)) {
    $gpuInventoryAssessment.notes += 'Число NVIDIA-устройств в PnP не совпадает с количеством GPU, которые реально видит nvidia-smi.'
}
if (($win32GpuNames -join '|') -ne ($pnpDisplayNames -join '|')) {
    $gpuInventoryAssessment.notes += 'Состав Win32_VideoController и PnP Display различается, поэтому профиль GPU может быть неполным или устаревшим.'
}

$gpuTopology = [ordered]@{}
$gpuTopology.win32_video_controller = @($gpuProfile)
$gpuTopology.pnp_display_devices = @($displayPnpDevices)
$gpuTopology.nvidia_smi = @($nvidiaSmiGpus)
$gpuTopology.assessment = $gpuInventoryAssessment

$wheaContext = [ordered]@{}
$wheaContext.event_count = $wheaEvents.Count
$wheaContext.note = $(if ($wheaEvents.Count -eq 0 -and (($crashSignalEvents.Count -gt 0) -or ($nvidia153Events.Count -gt 0) -or ($storageBadBlockEvents.Count -gt 0))) {
    'WHEA-события не найдены, но это не исключает аппаратную или драйверную проблему: есть crash-сигналы, GPU-ошибки и/или ошибки хранения.'
} elseif ($wheaEvents.Count -eq 0) {
    'WHEA-события не найдены за выбранный период.'
} else {
    'В журнале есть WHEA-события, их нужно разбирать отдельно как возможный аппаратный сигнал.'
})

$restartAnalysis = [ordered]@{}
$restartAnalysis.planned_events = @(
    $plannedRestartEvents | ForEach-Object {
        [pscustomobject]@{
            timestamp = $_.timestamp
            provider = $_.provider
            event_id = $_.event_id
            message = $_.message
        }
    }
)
$restartAnalysis.crash_events = @(
    $crashSignalEvents | ForEach-Object {
        [pscustomobject]@{
            timestamp = $_.timestamp
            provider = $_.provider
            event_id = $_.event_id
            message = $_.message
        }
    }
)
$restartAnalysis.assessment = $(if ($crashSignalEvents.Count -gt 0 -and $plannedRestartEvents.Count -gt 0) {
    'В системе есть и штатные/инициированные перезапуски, и отдельная линия аварийных crash/unexpected shutdown событий.'
} elseif ($crashSignalEvents.Count -gt 0) {
    'Преобладают crash/unexpected shutdown сигналы, это уже не только штатные перезапуски.'
} else {
    'За выбранный период преобладают штатные restart/shutdown сигналы.'
})

$gpuInstabilityAnalysis = [ordered]@{}
$gpuInstabilityAnalysis.nvidia_153_count = $nvidia153Events.Count
$gpuInstabilityAnalysis.nvidia_153_by_day = @($nvidia153ByDay)
$gpuInstabilityAnalysis.last_event_dates = @($nvidia153Events | Select-Object -First 10 | ForEach-Object { $_.timestamp })
$gpuInstabilityAnalysis.notes = @()
if ($nvidia153Events.Count -gt 0) {
    $gpuInstabilityAnalysis.notes += 'Повторяющиеся nvlddmkm 153 указывают на активную проблему в NVIDIA-стеке или на уровне устройства GPU.'
}
if (($nvidia153Events | Where-Object { $_.message_source -ne 'message' }).Count -gt 0) {
    $gpuInstabilityAnalysis.notes += 'Часть nvlddmkm-событий потребовала fallback к EventData/Properties, потому что обычное поле Message было пустым.'
}

$storageAnalysis = [ordered]@{}
$storageAnalysis.bad_block_events = @(
    $storageBadBlockEvents | ForEach-Object {
        [pscustomobject]@{
            timestamp = $_.timestamp
            provider = $_.provider
            event_id = $_.event_id
            message = $_.message
        }
    }
)
$storageAnalysis.health_inventory = @($storageHealthInventory)
$storageAnalysis.predict_failure_count = @($storageHealthInventory | Where-Object { $_.predict_failure -eq $true }).Count
$storageAnalysis.unhealthy_physical_disks = @(
    $storageHealthInventory | Where-Object {
        $_.source -eq 'Get-PhysicalDisk' -and ($_.health_status -notin @($null, 'Healthy') -or $_.media_errors_total -gt 0 -or $_.read_errors_total -gt 0 -or $_.write_errors_total -gt 0)
    }
)
$storageAnalysis.assessment = $(if ($storageBadBlockEvents.Count -gt 0) {
    'Обнаружены bad block события в System log, это высокий риск деградации накопителя или ошибок чтения.'
} elseif ($storageAnalysis.unhealthy_physical_disks.Count -gt 0 -or $storageAnalysis.predict_failure_count -gt 0) {
    'Прямых bad block в журнале нет, но storage telemetry указывает на признаки неблагополучия накопителя.'
} else {
    'Bad block события в storage-секциях не найдены; явных красных флагов по доступной storage telemetry тоже нет.'
})

$machineOverview = [ordered]@{}
$machineOverview.machine = $env:COMPUTERNAME
$machineOverview.os_caption = (ConvertTo-FlatText $os.Caption)
$machineOverview.os_version = (ConvertTo-FlatText $os.Version)
$machineOverview.os_build = (ConvertTo-FlatText $os.BuildNumber)
$machineOverview.model = (ConvertTo-FlatText $computerSystem.Model)
$machineOverview.manufacturer = (ConvertTo-FlatText $computerSystem.Manufacturer)
$machineOverview.total_ram_gb = $(if ($runtimeData.memory_total_bytes) { [math]::Round(([double]$runtimeData.memory_total_bytes / 1GB), 2) } else { $null })
$machineOverview.cpu = @($cpuProfile | ForEach-Object { $_.name })
$machineOverview.gpu = @($gpuProfile | ForEach-Object { $_.name })
$machineOverview.gpu_summary = [ordered]@{
    active_gpu_names = @($nvidiaSmiNames + ($gpuProfile | Where-Object { $_.name -match '(?i)AMD|Radeon|Intel|Remote Display' } | ForEach-Object { $_.name }) | Sort-Object -Unique)
    pnp_total = $displayPnpDevices.Count
    anomaly_total = $displayPnpAnomalies.Count
    unknown_or_error = @($displayPnpDevices | Where-Object { $_.status -in @('Unknown', 'Error', 'Degraded') } | ForEach-Object { $_.friendly_name } | Sort-Object -Unique)
    not_present = @($displayPnpDevices | Where-Object { $_.present -eq $false } | ForEach-Object { $_.friendly_name } | Sort-Object -Unique)
}
$machineOverview.disks = @($diskProfile | ForEach-Object { $_.model })
$machineOverview.network_adapters = @($networkProfile | ForEach-Object { $_.adapter })
$machineOverview.last_boot = $runtimeData.boot_time
$machineOverview.uptime = $runtimeData.uptime
$machineOverview.disk_usage = @(
    $diskUsage | ForEach-Object {
        [pscustomobject]@{
            drive = $_.drive
            total_gb = $(if ($_.total_bytes) { [math]::Round(([double]$_.total_bytes / 1GB), 2) } else { $null })
            free_gb = $(if ($_.free_bytes) { [math]::Round(([double]$_.free_bytes / 1GB), 2) } else { $null })
            used_gb = $(if ($_.used_bytes) { [math]::Round(([double]$_.used_bytes / 1GB), 2) } else { $null })
        }
    }
)

$findings = New-List

$unexpectedRestartEvents = @($crashSignalEvents | Where-Object { $_.provider -like '*Kernel-Power*' -or $_.provider -eq 'EventLog' -or $_.event_id -eq '1001' })
if ($unexpectedRestartEvents.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'crash_history' -Severity 'high' -Title 'Есть отдельная линия аварийных crash / unexpected shutdown событий' -Summary $restartAnalysis.assessment -EvidenceKeys ($unexpectedRestartEvents | ForEach-Object { $_.event_key }) -ProbableCauses @('Нужно отделять штатные user-initiated рестарты от реальных crash-событий: в журнале присутствуют Kernel-Power 41, EventLog 6008 и/или System 1001.') -UserQuestionsSupported @('Были ли на компьютере реальные аварийные перезагрузки?', 'Это просто штатные рестарты или уже crash history?', 'Есть ли отдельная аварийная линия событий?')))
}

if ($bugcheckCorrelations.Count -gt 0) {
    $bugcheckDates = @($bugcheckCorrelations | ForEach-Object { $_.timestamp.Substring(0, 10) } | Sort-Object -Unique)
    [void]$findings.Add((New-Finding -Id 'bugcheck_bsod_history' -Severity 'high' -Title 'Обнаружена история BSOD / bugcheck с корреляцией на minidump' -Summary ('Найдены bugcheck-события System 1001 / WER на датах: {0}.' -f ($bugcheckDates -join ', ')) -EvidenceKeys ($bugcheckCorrelations | ForEach-Object { $_.evidence_event_key }) -ProbableCauses @('На машине уже были реальные BSOD. Для точной первопричины нужен разбор stop code, minidump и связанного драйверного/дискового контекста.') -UserQuestionsSupported @('Были ли реальные BSOD?', 'На какие даты приходятся bugcheck-события?', 'Есть ли связь между bugcheck и minidump?')))
}

if ($nvidia153Events.Count -gt 0) {
    $recentNvidiaDates = @($nvidia153ByDay | Select-Object -First 5 | ForEach-Object { $_.date })
    [void]$findings.Add((New-Finding -Id 'nvidia_driver_instability' -Severity 'high' -Title 'Есть повторяющиеся ошибки NVIDIA nvlddmkm 153' -Summary ('Повторяющиеся nvlddmkm 153 зафиксированы по дням: {0}.' -f ($recentNvidiaDates -join ', ')) -EvidenceKeys ($nvidia153Events | ForEach-Object { $_.event_key }) -ProbableCauses @('Это похоже на активную нестабильность NVIDIA-драйвера, рендер-стека, устройства GPU или связанного PnP-окружения.') -UserQuestionsSupported @('Есть ли активная проблема с NVIDIA?', 'Насколько часто повторяется nvlddmkm 153?', 'Похоже ли это на TDR / GPU instability?')))
}

if ($storageBadBlockEvents.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'storage_bad_blocks' -Severity 'high' -Title 'Обнаружены bad block события в подсистеме хранения' -Summary $storageAnalysis.assessment -EvidenceKeys ($storageBadBlockEvents | ForEach-Object { $_.event_key }) -ProbableCauses @('Bad block может указывать на деградацию накопителя, ошибки чтения и косвенно усиливать проблемы драйверов, дампов и общей стабильности.') -UserQuestionsSupported @('Есть ли плохие сигналы по диску?', 'Обнаружены ли bad block события?', 'Может ли диск влиять на нестабильность системы?')))
}

if ($storageAnalysis.unhealthy_physical_disks.Count -gt 0 -or $storageAnalysis.predict_failure_count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'storage_health_telemetry' -Severity 'high' -Title 'Storage telemetry содержит признаки неблагополучия диска' -Summary 'Доступные SMART/NVMe/PhysicalDisk-показатели содержат аномалии, которые нужно рассматривать вместе с bad block и crash history.' -EvidenceKeys @() -ProbableCauses @('Даже при неполном SMART-слое физический диск может уже показывать health/media/read/write error сигналы.') -UserQuestionsSupported @('Есть ли признаки проблем по SMART/NVMe/PhysicalDisk?', 'Показывает ли storage telemetry деградацию?', 'Подтверждается ли риск диска не только по event log?')))
}

if ($displayPnpAnomalies.Count -gt 0 -or (($nvidiaSmiGpus.Count -gt 0) -and ($gpuInventoryAssessment.notes.Count -gt 0))) {
    [void]$findings.Add((New-Finding -Id 'gpu_pnp_inventory_anomalies' -Severity 'medium' -Title 'Есть аномалии в составе и статусах display-устройств' -Summary 'Состав Win32_VideoController, PnP Display и nvidia-smi не полностью совпадает, есть признаки ghost/unknown/error устройств или конфликтного GPU-стека.' -EvidenceKeys @() -ProbableCauses @('Видеостек может быть засорён старыми или неактивными устройствами, что мешает чистой диагностике и может влиять на стабильность драйвера.') -UserQuestionsSupported @('Есть ли ghost/unknown display устройства?', 'Совпадает ли PnP с nvidia-smi?', 'Актуален ли профиль GPU в системе?')))
}

if ($wheaEvents.Count -eq 0 -and (($crashSignalEvents.Count -gt 0) -or ($nvidia153Events.Count -gt 0) -or ($storageBadBlockEvents.Count -gt 0))) {
    [void]$findings.Add((New-Finding -Id 'no_whea_but_other_red_flags' -Severity 'medium' -Title 'Отсутствие WHEA не снимает другие красные флаги' -Summary $wheaContext.note -EvidenceKeys @() -ProbableCauses @('Даже без WHEA проблема может быть драйверной, дисковой, PnP-стековой или связанной с конкретным устройством GPU.') -UserQuestionsSupported @('Если WHEA пустой, значит ли это что железо точно в порядке?', 'Можно ли иметь серьёзную проблему без WHEA?', 'Что означают crash/GPU/storage сигналы без WHEA?')))
}

$virtualizationEvents = @($events | Where-Object { $_.diagnostic_tags -contains 'hyperv_vm_bus' -or $_.diagnostic_tags -contains 'hyperv_service_failure' -or $_.diagnostic_tags -contains 'virtualization_not_available' })
if ($virtualizationEvents.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'virtualization_stack_issues' -Severity 'medium' -Title 'Есть признаки проблем со стеком виртуализации / Hyper-V' -Summary 'Журналы содержат ошибки VMBus, Hyper-V Hypervisor или связанных служб виртуализации.' -EvidenceKeys ($virtualizationEvents | ForEach-Object { $_.event_key }) -ProbableCauses @('Виртуализация может быть недоступна из-за настроек BIOS/UEFI, ограничений виртуальной машины или недоступных компонентов Hyper-V/WSL.') -UserQuestionsSupported @('Почему не запускаются компоненты Hyper-V?', 'Есть ли проблемы с виртуализацией?', 'С чем может быть связана ошибка VMBus/HvHost/VMSP?')))
}

$updateEvents = @($events | Where-Object { $_.diagnostic_tags -contains 'update_install_failure' })
if ($updateEvents.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'update_failures' -Severity 'medium' -Title 'Есть ошибки установки обновлений и пакетов Store' -Summary 'WindowsUpdateClient зафиксировал несколько неудачных установок пакетов и runtime-компонентов.' -EvidenceKeys ($updateEvents | ForEach-Object { $_.event_key }) -ProbableCauses @('Обновление могло конфликтовать с уже выполняющейся установкой или быть занятым запущенным приложением.') -UserQuestionsSupported @('Почему не ставятся обновления?', 'Какие ошибки обновления есть на компьютере?', 'Что означают коды 0x80240016 и 0x80073D02?')))
}

$serviceEvents = @($events | Where-Object { $_.provider -eq 'Service Control Manager' })
if ($serviceEvents.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'service_failures' -Severity 'medium' -Title 'Есть ошибки запуска или работы служб' -Summary 'Service Control Manager сообщил о таймаутах и неудачных стартах отдельных служб.' -EvidenceKeys ($serviceEvents | ForEach-Object { $_.event_key }) -ProbableCauses @('Часть служб зависит от недоступных компонентов, виртуализации или сталкивается с нехваткой ресурсов/таймаутом.') -UserQuestionsSupported @('Какие службы работают с ошибками?', 'Есть ли таймауты служб?', 'Что может мешать запуску служб виртуализации и WSL?')))
}

if ($conflictingSoftware.Count -gt 0) {
    [void]$findings.Add((New-Finding -Id 'potentially_conflicting_software' -Severity 'medium' -Title 'Обнаружено ПО, которое стоит учитывать как конфликтный фон' -Summary ('Найдено {0} записей ПО из категорий GPU stack / monitoring / remote / updater / render pipeline.' -f $conflictingSoftware.Count) -EvidenceKeys @() -ProbableCauses @('Не каждое из этих приложений является причиной проблемы, но они формируют диагностически важный фон служб, драйверов, startup и update-агентов.') -UserQuestionsSupported @('Есть ли потенциально конфликтное ПО?', 'Что в системе может влиять на GPU/службы/remote context?', 'Есть ли updater/monitoring/render utilities, которые стоит учитывать?')))
}

foreach ($securityFinding in @($securityAudit.security_findings)) {
    [void]$findings.Add([pscustomobject]@{
        id = $securityFinding.id
        severity = $securityFinding.severity
        title = $securityFinding.title
        summary = $securityFinding.summary
        evidence_event_keys = @()
        probable_causes = @('Security-корреляция выявила паттерн доступа, изменения конфигурации или сетевой активности, требующий отдельной проверки.')
        questions_supported = @(
            'Есть ли признаки brute-force, suspicious access или blocked remote attempts?',
            'Были ли изменения security-конфигурации или установка служб?',
            'Есть ли значимая RDP / failed logon активность?'
        )
    })
}

$findingsArray = @($findings | ForEach-Object { $_ })
$sortedEvents = @($events | Sort-Object timestamp -Descending)
$recentIssues = @(
    $sortedEvents |
        Select-Object -First 80 |
        ForEach-Object { Convert-EventToRecentIssue -EventRecord $_ }
)

$consistencyChecks = @()
if ($nvidiaSmiGpus.Count -gt 0 -and (($displayPnpDevices | Where-Object { $_.friendly_name -match '(?i)NVIDIA' }).Count -ne $nvidiaSmiGpus.Count)) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'high'
        confidence = 'medium'
        impact_area = 'GPU'
        check = 'PnP_vs_nvidia_smi_mismatch'
        description = 'Количество NVIDIA display-устройств в PnP не совпадает с количеством GPU, видимых через nvidia-smi.'
    }
}
if ($storageBadBlockEvents.Count -gt 0) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'high'
        confidence = 'high'
        impact_area = 'Disk'
        check = 'bad_block_red_flag'
        description = 'Обнаружены bad block события, это конфликтует с гипотезой о полностью здоровой подсистеме хранения.'
    }
}
if ($wheaEvents.Count -eq 0 -and (($crashSignalEvents.Count -gt 0) -or ($nvidia153Events.Count -gt 0) -or ($storageBadBlockEvents.Count -gt 0))) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'medium'
        confidence = 'medium'
        impact_area = 'Hardware'
        check = 'no_whea_but_other_failures'
        description = 'WHEA отсутствует, но присутствуют другие серьёзные сигналы по crash/GPU/storage; нельзя делать вывод "железо в порядке" только по пустому WHEA.'
    }
}
if ($bugcheckCorrelations.Count -gt 0 -and $dumpStatus.minidumps.Count -eq 0) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'medium'
        confidence = 'medium'
        impact_area = 'OS'
        check = 'bugcheck_without_visible_minidumps'
        description = 'Есть bugcheck history, но minidump не найден в стандартной папке; возможно, дампы очищены, перемещены или отключены.'
    }
}
if ($storageAnalysis.unhealthy_physical_disks.Count -gt 0 -or $storageAnalysis.predict_failure_count -gt 0) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'high'
        confidence = 'medium'
        impact_area = 'Disk'
        check = 'storage_telemetry_red_flag'
        description = 'Storage health telemetry указывает на неблагополучие диска, даже если часть SMART/NVMe данных ограничена.'
    }
}
if ($reliabilityData.records.Count -eq 0 -and $reliabilityData.metrics.Count -eq 0) {
    $consistencyChecks += [pscustomobject]@{
        severity = 'low'
        confidence = 'medium'
        impact_area = 'OS'
        check = 'reliability_monitor_not_available'
        description = 'Классы Reliability Monitor недоступны или вернули пустой результат; этот слой корреляции ограничен.'
    }
}

$topRisksNow = @(
    $findingsArray |
        Sort-Object @{ Expression = {
            switch ($_.severity) {
                'high' { 0 }
                'medium' { 1 }
                default { 2 }
            }
        } }, title |
        Select-Object -First 7 |
        ForEach-Object {
            [pscustomobject]@{
                severity = $_.severity
                title = $_.title
                summary = $_.summary
            }
        }
)

$recommendedNextActionsList = New-Object System.Collections.Generic.List[string]
if ($storageBadBlockEvents.Count -gt 0 -or $storageAnalysis.unhealthy_physical_disks.Count -gt 0) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Сделать резервную копию критичных данных и рассматривать диск как приоритетный риск до подтверждения его состояния.'
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Проверить SMART/NVMe health дополнительными источниками и подготовить замену накопителя при повторении bad block или media error сигналов.'
}
if ($nvidia153Events.Count -gt 0 -or $displayPnpAnomalies.Count -gt 0) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Сверить активные GPU по nvidia-smi с PnP Display, удалить ghost/error устройства и проверить чистоту NVIDIA-драйверного стека.'
}
if ($bugcheckCorrelations.Count -gt 0) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Сопоставить bugcheck stop code с minidump и недавними изменениями драйверов/диска.'
}
if ($deadlineContext.detected) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Проверить Deadline services/startup/tasks и отдельные Deadline-логи на совпадение по времени с инцидентами.'
}
if ($conflictingSoftware.Count -gt 0) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Просмотреть suspicious software context: remote agents, updater-агенты, monitoring/overlay утилиты и рендерные компоненты.'
}
if ($recommendedNextActionsList.Count -eq 0) {
    Add-UniqueText -Target $recommendedNextActionsList -Text 'Использовать recent_issues и findings как основной вход для следующего ручного forensic-разбора.'
}
$recommendedNextActions = @($recommendedNextActionsList)
$securitySummary = $securityAudit.security_summary
$topSecurityRisks = @($securityAudit.top_security_risks)
$recommendedSecurityActions = @($securityAudit.recommended_security_actions)

$aiSummary = @()
$aiSummary += ('Компьютер: {0}; ОС: {1} {2} (build {3}); модель: {4}.' -f $env:COMPUTERNAME, (ConvertTo-FlatText $os.Caption), (ConvertTo-FlatText $os.Version), (ConvertTo-FlatText $os.BuildNumber), (ConvertTo-FlatText $computerSystem.Model))
$aiSummary += ('Runtime: последний boot {0}; uptime {1}; RAM {2:N2} GB.' -f $runtimeData.boot_time, $runtimeData.uptime, $(if ($runtimeData.memory_total_bytes) { [double]$runtimeData.memory_total_bytes / 1GB } else { 0 }))
$aiSummary += ('Линия перезапусков: planned={0}, crash/unexpected={1}.' -f $plannedRestartEvents.Count, $crashSignalEvents.Count)
if ($bugcheckCorrelations.Count -gt 0) {
    $aiSummary += ('Есть история BSOD / bugcheck: {0} событий с корреляцией на minidump.' -f $bugcheckCorrelations.Count)
}
if ($nvidia153Events.Count -gt 0) {
    $aiSummary += ('Активная GPU/NVIDIA проблема: nvlddmkm 153 повторяется {0} раз.' -f $nvidia153Events.Count)
}
if ($storageBadBlockEvents.Count -gt 0) {
    $aiSummary += ('Storage red flag: bad block событий найдено {0}.' -f $storageBadBlockEvents.Count)
}
if ($displayPnpAnomalies.Count -gt 0) {
    $aiSummary += ('В PnP Display есть аномальные устройства Unknown/Error/Degraded: {0}.' -f $displayPnpAnomalies.Count)
}
if ($wheaEvents.Count -eq 0) {
    $aiSummary += 'WHEA не найден, но это не исключает реальную драйверную, дисковую или device-level проблему.'
}
$aiSummary += ('Inventory: software={0}, services={1}, tasks={2}, startup={3}, updates={4}.' -f $installedSoftware.Count, $serviceInventory.Count, $scheduledTaskInventory.Count, $startupInventory.Count, $windowsUpdateInventory.Count)
if ($driversInventory.Count -gt 0) {
    $aiSummary += ('Drivers inventory: собрано {0} записей по PnP signed drivers.' -f $driversInventory.Count)
}
if ($applicationCrashInventory.Count -gt 0) {
    $aiSummary += ('Application crash inventory: найдено {0} записей Application Error/.NET Runtime/Application Hang за выбранный период.' -f $applicationCrashInventory.Count)
}
if ($storageHealthInventory.Count -gt 0) {
    $aiSummary += ('Storage health telemetry: собрано {0} записей Get-PhysicalDisk / FailurePredictStatus.' -f $storageHealthInventory.Count)
}
if ($reliabilityData.records.Count -gt 0 -or $reliabilityData.metrics.Count -gt 0) {
    $aiSummary += ('Reliability Monitor: metrics={0}, records={1}.' -f $reliabilityData.metrics.Count, $reliabilityData.records.Count)
}
if ($deadlineContext.detected) {
    $aiSummary += ('В системе обнаружен Deadline/Thinkbox context: software={0}, services={1}, tasks={2}, startup={3}, log_paths={4}.' -f $deadlineContext.software.Count, $deadlineContext.services.Count, $deadlineContext.scheduled_tasks.Count, $deadlineContext.startup_items.Count, $deadlineContext.existing_paths.Count)
}
$aiSummary += ('Security: events={0}, failed_logons={1}, successful_remote_access={2}, blocked_connections={3}, config_changes={4}.' -f $securitySummary.total_security_events, $securitySummary.failed_logon_count, $securitySummary.successful_remote_access_count, $securitySummary.blocked_connection_count, $securitySummary.security_configuration_change_count)
$aiSummary += ('Top risks now: {0}.' -f ((@($topRisksNow | ForEach-Object { $_.title }) | Select-Object -First 3) -join '; '))
if ($topSecurityRisks.Count -gt 0) {
    $aiSummary += ('Top security risks: {0}.' -f ((@($topSecurityRisks | ForEach-Object { $_.title }) | Select-Object -First 3) -join '; '))
}

$readiness = [ordered]@{}
$readiness.suited_for_ai_analysis = $true
$readiness.strengths = @(
    'События дедуплицированы и содержат привязку к нескольким диагностическим категориям.',
    'Добавлены краткие вероятные причины и диагностические теги для части событий.',
    'Пустые данные представлены пустыми массивами или отдельным списком пустых категорий вместо null.',
    'Есть отдельные срезы по crash vs planned restart, bugcheck/minidump, GPU PnP и storage bad block.'
)
$readiness.limitations = @(
    'Вероятные причины являются эвристикой и не заменяют полный анализ дампов, vendor SMART/NVMe telemetry и аппаратных тестов.',
    'Отсутствие событий в категории означает, что за выбранный период подходящие записи не найдены, а не что проблема невозможна.',
    'Некоторые системные источники могут быть недоступны без повышенных прав или из-за особенностей среды.'
)

$osProfile = [ordered]@{}
$osProfile.caption = (ConvertTo-FlatText $os.Caption)
$osProfile.version = (ConvertTo-FlatText $os.Version)
$osProfile.build = (ConvertTo-FlatText $os.BuildNumber)
$osProfile.install_date = (Invoke-Safely -Fallback $null -ScriptBlock { $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss') })
$osProfile.computer_name = (ConvertTo-FlatText $os.CSName)
$osProfile.last_boot = $runtimeData.boot_time

$firmwareProfile = [ordered]@{}
$firmwareProfile.manufacturer = (ConvertTo-FlatText $computerSystem.Manufacturer)
$firmwareProfile.model = (ConvertTo-FlatText $computerSystem.Model)
$firmwareProfile.board_product = (ConvertTo-FlatText $board.Product)
$firmwareProfile.board_manufacturer = (ConvertTo-FlatText $board.Manufacturer)
$firmwareProfile.bios_version = (ConvertTo-FlatText $bios.SMBIOSBIOSVersion)
$firmwareProfile.bios_vendor = (ConvertTo-FlatText $bios.Manufacturer)
$firmwareProfile.bios_release_date = (Invoke-Safely -Fallback $null -ScriptBlock { $bios.ReleaseDate.ToString('yyyy-MM-dd HH:mm:ss') })

$systemProfile = [ordered]@{}
$systemProfile.os = $osProfile
$systemProfile.firmware = $firmwareProfile
$systemProfile.cpu = @($cpuProfile)
$systemProfile.memory_modules = @($memoryProfile)
$systemProfile.gpu = @($gpuProfile)
$systemProfile.disks = @($diskProfile)
$systemProfile.partitions = @($partitionProfile)
$systemProfile.network = @($networkProfile)
$systemProfile.network_adapters = @($networkAdapterInventory)
$systemProfile.drivers_sample = @($driversSample)
$systemProfile.drivers_inventory = @($driversInventory | Select-Object -First 1200)
$systemProfile.virtualization_features = @($featureStates)
$systemProfile.display_pnp_devices = @($displayPnpDevices)
$systemProfile.nvidia_smi_gpus = @($nvidiaSmiGpus)
$systemProfile.storage_health = @($storageHealthInventory)

$eventSummary = [ordered]@{}
$eventSummary.by_level = @($eventSummaryByLevel)
$eventSummary.by_provider = @($eventSummaryByProvider)

$diagnostics = [ordered]@{}
$diagnostics.runtime = $runtimeData
$diagnostics.disk_usage = @($diskUsage)
$diagnostics.event_summary = $eventSummary
$diagnostics.reliability_metrics = @($reliabilityData.metrics)
$diagnostics.reliability_records = @($reliabilityData.records)
$diagnostics.dump_status = $dumpStatus
$diagnostics.restart_analysis = $restartAnalysis
$diagnostics.bugcheck_analysis = @($bugcheckCorrelations)
$diagnostics.gpu_instability_analysis = $gpuInstabilityAnalysis
$diagnostics.storage_analysis = $storageAnalysis
$diagnostics.gpu_topology = $gpuTopology
$diagnostics.whea_context = $wheaContext
$diagnostics.config_audit = $configAudit
$diagnostics.consistency_checks = @($consistencyChecks)
$diagnostics.recent_issues = @($recentIssues)
$diagnostics.application_crashes = @($applicationCrashInventory)
$diagnostics.driver_update_history = @($driverUpdateHistory)
$diagnostics.software_conflict_analysis = [ordered]@{
    count = $conflictingSoftware.Count
    by_category = @(
        $conflictingSoftware |
            Group-Object category |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    category = $_.Name
                    count = $_.Count
                }
            }
    )
    items = @($conflictingSoftware)
}
$diagnostics.top_risks_now = @($topRisksNow)
$diagnostics.recommended_next_actions = @($recommendedNextActions)
$diagnostics.security_summary = $securitySummary
$diagnostics.top_security_risks = @($topSecurityRisks)
$diagnostics.recommended_security_actions = @($recommendedSecurityActions)
$diagnostics.pci_event_classification = [ordered]@{
    driver_installation = @($pcieEventClassification.driver_installation)
    network_adapter_resets = @($pcieEventClassification.network_adapter_resets)
    hardware_like = @($pcieEventClassification.hardware_like)
}
$diagnostics.empty_categories = @($emptyCategories)

$inventory = [ordered]@{}
$inventory.installed_software = @($installedSoftware | Sort-Object name | Select-Object -First 400)
$inventory.services = @($serviceInventory | Sort-Object Name)
$inventory.scheduled_tasks = @($scheduledTaskInventory | Sort-Object TaskPath, TaskName | Select-Object -First 400)
$inventory.startup_items = @($startupInventory | Sort-Object Name)
$inventory.windows_updates = @($windowsUpdateInventory)
$inventory.network_adapters = @($networkAdapterInventory | Sort-Object Name)
$inventory.drivers_inventory = @($driversInventory | Select-Object -First 1200)
$inventory.storage_health = @($storageHealthInventory)
$inventory.application_crashes = @($applicationCrashInventory)
$inventory.driver_update_history = @($driverUpdateHistory)
$inventory.potentially_conflicting_software = @($conflictingSoftware)
$inventory.deadline_context = $deadlineContext
$inventory.security_recent = @($securityAudit.recent_security_events)
$inventory.security_failed_logons = @($securityAudit.failed_logons)
$inventory.security_remote_access = @($securityAudit.successful_remote_access)

$rawEvidence = [ordered]@{}
$rawEvidence.raw_events_recent = @($sortedEvents | Select-Object -First 120)
$rawEvidence.raw_events_crash = @($crashSignalEvents)
$rawEvidence.raw_events_gpu = @($events | Where-Object { (Get-EventImpactArea -EventRecord $_) -eq 'GPU' })
$rawEvidence.raw_events_storage = @($events | Where-Object { (Get-EventImpactArea -EventRecord $_) -eq 'Disk' })
$rawEvidence.raw_pnp_devices = @($displayPnpDevices)
$rawEvidence.raw_installed_software = @($installedSoftware | Sort-Object name | Select-Object -First 400)
$rawEvidence.raw_services = @($serviceInventory | Sort-Object Name)
$rawEvidence.raw_tasks = @($scheduledTaskInventory | Sort-Object TaskPath, TaskName | Select-Object -First 400)
$rawEvidence.raw_updates = @($windowsUpdateInventory)
$rawEvidence.raw_network = @($networkProfile)
$rawEvidence.raw_network_adapters = @($networkAdapterInventory)
$rawEvidence.raw_drivers_inventory = @($driversInventory | Select-Object -First 1200)
$rawEvidence.raw_storage_health = @($storageHealthInventory)
$rawEvidence.raw_application_crashes = @($applicationCrashInventory)
$rawEvidence.raw_driver_update_history = @($driverUpdateHistory)
$rawEvidence.raw_deadline_context = $deadlineContext
$rawEvidence.raw_security_events = @($securityAudit.raw_security_events)

$analysis = [ordered]@{}
$analysis.schema_version = '6.0'
$analysis.generated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
$analysis.machine = $env:COMPUTERNAME
$analysis.selected_period = $selection.Label
$analysis.period_start = $selection.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
$analysis.report_file_name = $reportMetadata.report_file_name
$analysis.report_basename = $reportMetadata.report_basename
$analysis.output_path = $reportMetadata.report_path
$analysis.output_metadata = [ordered]@{
    report_file_name = $reportMetadata.report_file_name
    report_basename = $reportMetadata.report_basename
    machine = $env:COMPUTERNAME
    generated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
    selected_period = $selection.Label
    schema_version = '6.0'
    output_path = $reportMetadata.report_path
    reports_root = $reportMetadata.reports_root
    latest_report_path = $reportMetadata.latest_report_path
}
$analysis.report_identity = [ordered]@{
    report_file_name = $reportMetadata.report_file_name
    report_basename = $reportMetadata.report_basename
    machine = $env:COMPUTERNAME
    generated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
    selected_period = $selection.Label
    schema_version = '6.0'
}
$analysis.purpose = 'Forensic + inventory + configuration audit + security audit JSON v6 для чтения и анализа нейросетью по состоянию юнита, ошибкам, конфигурации, удаленному доступу и вероятным причинам.'
$analysis.readiness = $readiness
$analysis.ai_summary = @($aiSummary)
$analysis.top_risks_now = @($topRisksNow)
$analysis.recommended_next_actions = @($recommendedNextActions)
$analysis.security_summary = $securitySummary
$analysis.recent_security_events = @($securityAudit.recent_security_events)
$analysis.rdp_logon_activity = @($securityAudit.rdp_logon_activity)
$analysis.failed_logons = @($securityAudit.failed_logons)
$analysis.successful_remote_access = @($securityAudit.successful_remote_access)
$analysis.firewall_and_port_activity = @($securityAudit.firewall_and_port_activity)
$analysis.security_configuration_audit = @($securityAudit.security_configuration_audit)
$analysis.account_and_privilege_events = @($securityAudit.account_and_privilege_events)
$analysis.security_findings = @($securityAudit.security_findings)
$analysis.top_security_risks = @($topSecurityRisks)
$analysis.recommended_security_actions = @($recommendedSecurityActions)
$analysis.machine_overview = $machineOverview
$analysis.system_profile = $systemProfile
$analysis.diagnostics = $diagnostics
$analysis.security_audit = [ordered]@{
    security_summary = $securitySummary
    recent_security_events = @($securityAudit.recent_security_events)
    rdp_logon_activity = @($securityAudit.rdp_logon_activity)
    failed_logons = @($securityAudit.failed_logons)
    successful_remote_access = @($securityAudit.successful_remote_access)
    firewall_and_port_activity = @($securityAudit.firewall_and_port_activity)
    security_configuration_audit = @($securityAudit.security_configuration_audit)
    account_and_privilege_events = @($securityAudit.account_and_privilege_events)
    security_findings = @($securityAudit.security_findings)
    top_security_risks = @($topSecurityRisks)
    recommended_security_actions = @($recommendedSecurityActions)
}
$analysis.inventory = $inventory
$analysis.findings = $findingsArray
$analysis.raw_evidence = $rawEvidence
$analysis.events = $sortedEvents

$analysis |
    ConvertTo-Json -Depth 12 |
    Set-Content -Path $outputPath -Encoding UTF8

Copy-Item -Path $outputPath -Destination $reportMetadata.latest_report_path -Force

Write-Host ''
Write-Host ('Файл анализа V6 создан: {0}' -f $outputPath)
Write-Host ('Latest-копия обновлена: {0}' -f $reportMetadata.latest_report_path)
Write-Host ('Количество уникальных событий: {0}' -f $events.Count)
Write-Host ('Количество findings: {0}' -f $findings.Count)
Write-Host ('Количество security-событий: {0}' -f $securitySummary.total_security_events)
