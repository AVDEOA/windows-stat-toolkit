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

    @($items)
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

function Get-EventMessageForAnalysis {
    param([object]$Event)

    $directMessage = Invoke-Safely -Fallback $null -ScriptBlock { [string]$Event.Message }
    if (-not [string]::IsNullOrWhiteSpace($directMessage)) {
        return [pscustomobject]@{
            text = ((($directMessage -replace '\s+', ' ').Trim()))
            source = 'message'
        }
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

    $patterns = '(?i)(nvidia|amd|geforce|radeon|msi afterburner|rivatuner|rtss|rgb|aura|armoury|armory|icue|nzxt|remote|mesh|vpn|virtual display|parsec|teamviewer|anydesk|deadline|thinkbox|launcher|worker|monitor|cosmos|promdapter|ssh|openssh)'
    @(
        @($Software) |
            Where-Object { $_.name -match $patterns } |
            Sort-Object name -Unique
    )
}

function Get-DeadlineContext {
    param(
        [object[]]$Software,
        [object[]]$Services,
        [object[]]$Tasks,
        [object[]]$StartupItems
    )

    $patterns = '(?i)(deadline|thinkbox|launcher|worker|pulse|monitor|draft)'

    [ordered]@{
        software = @(@($Software) | Where-Object { $_.name -match $patterns } | Sort-Object name -Unique)
        services = @(@($Services) | Where-Object { $_.Name -match $patterns -or $_.DisplayName -match $patterns } | Sort-Object Name -Unique)
        scheduled_tasks = @(@($Tasks) | Where-Object { $_.TaskName -match $patterns -or $_.Description -match $patterns } | Sort-Object TaskPath, TaskName -Unique)
        startup_items = @(@($StartupItems) | Where-Object { $_.Name -match $patterns -or $_.Command -match $patterns } | Sort-Object Name -Unique)
    }
}

function Get-ConfigAudit {
    $crashDumpEnabled = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled'
    $tdrDelay = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'TdrDelay'
    $tdrDdiDelay = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'TdrDdiDelay'
    $hags = Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'

    [ordered]@{
        power_plan = $null
        fast_startup_enabled = $null
        hibernation_enabled = $null
        crash_dump_enabled = $crashDumpEnabled
        tdr_delay = $tdrDelay
        tdr_ddi_delay = $tdrDdiDelay
        hardware_accelerated_gpu_scheduling = $hags
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

$selection = Read-AnalysisRange -InitialChoice $PeriodChoice
$outputRoot = Ensure-StatOutputRoot
$outputPath = Join-Path -Path $outputRoot -ChildPath 'AnalizeV3.txt'
$now = Get-Date

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

$driversSample = @(
    $drivers |
        Sort-Object DriverDate -Descending |
        Select-Object -First 20 |
        ForEach-Object {
            [pscustomobject]@{
                device_name = $_.DeviceName
                driver_version = $_.DriverVersion
                provider = $_.DriverProviderName
                driver_date = $_.DriverDate
                inf_name = $_.InfName
            }
        }
)

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
$storageAnalysis.assessment = $(if ($storageBadBlockEvents.Count -gt 0) {
    'Обнаружены bad block события в System log, это высокий риск деградации накопителя или ошибок чтения.'
} else {
    'Bad block события в storage-секциях не найдены.'
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
if ($applicationCrashInventory.Count -gt 0) {
    $aiSummary += ('Application crash inventory: найдено {0} записей Application Error/.NET Runtime/Application Hang за выбранный период.' -f $applicationCrashInventory.Count)
}
if ($deadlineContext.software.Count -gt 0 -or $deadlineContext.services.Count -gt 0 -or $deadlineContext.scheduled_tasks.Count -gt 0 -or $deadlineContext.startup_items.Count -gt 0) {
    $aiSummary += 'В системе обнаружен Deadline/Thinkbox context, его можно анализировать отдельно от системных проблем.'
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
    'Вероятные причины являются эвристикой и не заменяют полный анализ дампов, SMART и аппаратных тестов.',
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
$systemProfile.virtualization_features = @($featureStates)
$systemProfile.display_pnp_devices = @($displayPnpDevices)
$systemProfile.nvidia_smi_gpus = @($nvidiaSmiGpus)

$eventSummary = [ordered]@{}
$eventSummary.by_level = @($eventSummaryByLevel)
$eventSummary.by_provider = @($eventSummaryByProvider)

$diagnostics = [ordered]@{}
$diagnostics.runtime = $runtimeData
$diagnostics.disk_usage = @($diskUsage)
$diagnostics.event_summary = $eventSummary
$diagnostics.reliability_metrics = @()
$diagnostics.reliability_records = @()
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
$inventory.application_crashes = @($applicationCrashInventory)
$inventory.driver_update_history = @($driverUpdateHistory)
$inventory.potentially_conflicting_software = @($conflictingSoftware)
$inventory.deadline_context = $deadlineContext

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
$rawEvidence.raw_application_crashes = @($applicationCrashInventory)
$rawEvidence.raw_driver_update_history = @($driverUpdateHistory)
$rawEvidence.raw_deadline_context = $deadlineContext

$analysis = [ordered]@{}
$analysis.schema_version = '3.0'
$analysis.generated_at = $now.ToString('yyyy-MM-dd HH:mm:ss')
$analysis.machine = $env:COMPUTERNAME
$analysis.selected_period = $selection.Label
$analysis.period_start = $selection.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
$analysis.purpose = 'Forensic + inventory + configuration audit JSON для чтения и анализа нейросетью по состоянию юнита, ошибкам, конфигурации и вероятным причинам.'
$analysis.readiness = $readiness
$analysis.ai_summary = @($aiSummary)
$analysis.machine_overview = $machineOverview
$analysis.system_profile = $systemProfile
$analysis.diagnostics = $diagnostics
$analysis.inventory = $inventory
$analysis.findings = $findingsArray
$analysis.raw_evidence = $rawEvidence
$analysis.events = $sortedEvents

$analysis |
    ConvertTo-Json -Depth 12 |
    Set-Content -Path $outputPath -Encoding UTF8

Write-Host ''
Write-Host ('Файл анализа V3 создан: {0}' -f $outputPath)
Write-Host ('Количество уникальных событий: {0}' -f $events.Count)
Write-Host ('Количество findings: {0}' -f $findings.Count)
