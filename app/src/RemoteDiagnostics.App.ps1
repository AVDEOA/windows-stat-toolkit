param(
    [ValidateSet('Menu', 'Init', 'ListHosts', 'AddHost', 'RemoveHost', 'Collect', 'PrepareAnalysis')]
    [string]$Command = 'Menu',
    [string]$HostName,
    [string]$Address,
    [string]$UserName,
    [int]$Port = 22,
    [string]$KeyPath = '',
    [string]$Shell = 'powershell.exe',
    [string[]]$Tags = @(),
    [string]$Notes = '',
    [int]$Days = 7
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\RemoteDiagnostics.Common.ps1"

function Show-RemoteDiagnosticsMenu {
    Write-Host ''
    Write-Host 'Remote Diagnostics MVP'
    Write-Host '1. Init state/config'
    Write-Host '2. List hosts'
    Write-Host '3. Add or update host'
    Write-Host '4. Remove host'
    Write-Host '5. Collect diagnostics over SSH'
    Write-Host '6. Prepare AI analysis bundle from latest collection'
    Write-Host '0. Exit'
    Write-Host ''
}

function Read-MenuValue {
    param([string]$Prompt)
    Read-Host $Prompt
}

function Invoke-AddHostInteractive {
    $name = Read-MenuValue -Prompt 'Host name'
    $address = Read-MenuValue -Prompt 'Address or IP'
    $userName = Read-MenuValue -Prompt 'SSH user name'
    $portInput = Read-MenuValue -Prompt 'Port (default 22)'
    $keyPath = Read-MenuValue -Prompt 'SSH key path (optional)'
    $notes = Read-MenuValue -Prompt 'Notes (optional)'
    $tagsInput = Read-MenuValue -Prompt 'Tags comma-separated (optional)'

    $resolvedPort = 22
    if (-not [string]::IsNullOrWhiteSpace($portInput)) {
        $resolvedPort = [int]$portInput
    }

    $resolvedTags = @()
    if (-not [string]::IsNullOrWhiteSpace($tagsInput)) {
        $resolvedTags = @($tagsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    Save-RemoteHost -Name $name -Address $address -UserName $userName -Port $resolvedPort -KeyPath $keyPath -Shell $Shell -Tags $resolvedTags -Notes $notes
    Write-Host "Saved host '$name'."
}

function Invoke-CollectForHost {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$ResolvedDays
    )

    $hostEntry = Get-RemoteHost -Name $Name
    if ($null -eq $hostEntry) {
        throw "Host '$Name' was not found in remote diagnostics config."
    }

    Write-Host "Collecting diagnostics from $($hostEntry.name) over SSH..."
    $collection = Invoke-RemoteCollection -Host $hostEntry -Days $ResolvedDays
    $bundle = Save-RemoteCollectionBundle -Host $hostEntry -Days $ResolvedDays -Collection $collection

    Write-Host ''
    Write-Host 'Collection complete.'
    Write-Host "Bundle directory: $($bundle.directory)"
    Write-Host "Collection JSON : $($bundle.collection_path)"
    Write-Host "Summary file    : $($bundle.summary_path)"
}

function Invoke-PrepareAnalysisForHost {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$ResolvedDays
    )

    $hostEntry = Get-RemoteHost -Name $Name
    if ($null -eq $hostEntry) {
        throw "Host '$Name' was not found in remote diagnostics config."
    }

    $latestDir = Get-LatestCollectionDirectory -HostName $hostEntry.name -Days $ResolvedDays
    if ($null -eq $latestDir) {
        throw "No collection bundle found for '$Name' and $ResolvedDays days."
    }

    $collectionPath = Join-Path -Path $latestDir.FullName -ChildPath 'collection.json'
    $collection = Read-JsonFile -Path $collectionPath
    if ($null -eq $collection) {
        throw "Collection JSON not found or empty: $collectionPath"
    }

    $bundle = Save-RemoteCollectionBundle -Host $hostEntry -Days $ResolvedDays -Collection $collection -IncludePrompt
    Write-Host ''
    Write-Host 'AI-ready bundle prepared.'
    Write-Host "Bundle directory : $($bundle.directory)"
    Write-Host "Prompt file      : $($bundle.analysis_prompt_path)"
    Write-Host "Collection JSON  : $($bundle.collection_path)"
    Write-Host "Summary file     : $($bundle.summary_path)"
}

$resolvedDays = Resolve-RemoteDays -Days $Days

switch ($Command) {
    'Init' {
        $path = Initialize-RemoteDiagnosticsState
        Write-Host "Remote diagnostics state initialized: $path"
    }
    'ListHosts' {
        $config = Get-RemoteHostsConfig
        if (@($config.hosts).Count -eq 0) {
            Write-Host 'No hosts configured yet. Run Init and AddHost first.'
            break
        }

        @($config.hosts) |
            Sort-Object name |
            Format-Table name, address, user_name, port, shell, @{Label='tags'; Expression={ @($_.tags) -join ',' }}
    }
    'AddHost' {
        if ([string]::IsNullOrWhiteSpace($HostName) -or [string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($UserName)) {
            throw 'AddHost requires -HostName, -Address, and -UserName.'
        }

        Save-RemoteHost -Name $HostName -Address $Address -UserName $UserName -Port $Port -KeyPath $KeyPath -Shell $Shell -Tags $Tags -Notes $Notes
        Write-Host "Saved host '$HostName'."
    }
    'RemoveHost' {
        if ([string]::IsNullOrWhiteSpace($HostName)) {
            throw 'RemoveHost requires -HostName.'
        }

        Remove-RemoteHost -Name $HostName
        Write-Host "Removed host '$HostName'."
    }
    'Collect' {
        if ([string]::IsNullOrWhiteSpace($HostName)) {
            throw 'Collect requires -HostName.'
        }

        Invoke-CollectForHost -Name $HostName -ResolvedDays $resolvedDays
    }
    'PrepareAnalysis' {
        if ([string]::IsNullOrWhiteSpace($HostName)) {
            throw 'PrepareAnalysis requires -HostName.'
        }

        Invoke-PrepareAnalysisForHost -Name $HostName -ResolvedDays $resolvedDays
    }
    default {
        while ($true) {
            Show-RemoteDiagnosticsMenu
            $choice = Read-MenuValue -Prompt 'Select action'
            switch ($choice) {
                '1' {
                    $path = Initialize-RemoteDiagnosticsState
                    Write-Host "Initialized: $path"
                }
                '2' {
                    & $PSCommandPath -Command ListHosts -Days $resolvedDays
                }
                '3' {
                    Invoke-AddHostInteractive
                }
                '4' {
                    $name = Read-MenuValue -Prompt 'Host name to remove'
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        Remove-RemoteHost -Name $name
                        Write-Host "Removed host '$name'."
                    }
                }
                '5' {
                    $name = Read-MenuValue -Prompt 'Host name'
                    $daysInput = Read-MenuValue -Prompt 'Days (3, 7, 14, 30)'
                    Invoke-CollectForHost -Name $name -ResolvedDays (Resolve-RemoteDays -Days ([int]$daysInput))
                }
                '6' {
                    $name = Read-MenuValue -Prompt 'Host name'
                    $daysInput = Read-MenuValue -Prompt 'Days (3, 7, 14, 30)'
                    Invoke-PrepareAnalysisForHost -Name $name -ResolvedDays (Resolve-RemoteDays -Days ([int]$daysInput))
                }
                '0' { break }
                default { Write-Host 'Unknown choice.' }
            }
        }
    }
}

