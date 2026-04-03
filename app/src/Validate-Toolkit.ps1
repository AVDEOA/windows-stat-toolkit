param(
    [switch]$RunCollection
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToParse = @(
    'StatToolkit.Common.ps1',
    'Analize.ps1',
    'AnalizeV2.ps1',
    'AnalizeV3.ps1',
    'AnalizeV4.ps1',
    'AnalizeV5.ps1',
    'AnalizeV6.ps1',
    'AnalizeV7.ps1',
    'AnalizeV8.ps1',
    'AnalizeV9.ps1',
    'Block1_SystemInfo.ps1',
    'Block2_SystemStats.ps1',
    'Block3_DriverErrors.ps1',
    'Block4_GPUDriverErrors.ps1',
    'Block5_WHEA_PCI_Errors.ps1',
    'Block6_BSOD_CrashErrors.ps1',
    'Block7_AdditionalCriticalErrors.ps1',
    'Run-All-Stat-Collection.ps1',
    'Validate-Toolkit.ps1'
)

Write-Output '=== Проверка: синтаксический разбор ==='
$parseFailures = @()
foreach ($file in $filesToParse) {
    $path = Join-Path -Path $root -ChildPath $file
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors -and $errors.Count -gt 0) {
        foreach ($errorRecord in $errors) {
            $parseFailures += ('{0}: {1}' -f $file, $errorRecord.Message)
        }
    }
    else {
        Write-Output ('OK  - {0}' -f $file)
    }
}

if ($parseFailures.Count -gt 0) {
    Write-Output 'НАЙДЕНЫ_ОШИБКИ_СИНТАКСИСА'
    $parseFailures | ForEach-Object { Write-Output $_ }
}
else {
    Write-Output 'ОШИБОК_СИНТАКСИСА_НЕТ'
}

Write-Output ''
Write-Output '=== Проверка: аудит безопасности ==='
$forbiddenPatterns = @(
    '(?im)^\s*Restart-Computer\b',
    '(?im)^\s*Stop-Computer\b',
    '(?im)^\s*shutdown\b',
    '(?im)^\s*Set-Service\b',
    '(?im)^\s*Start-Service\b',
    '(?im)^\s*Stop-Service\b',
    '(?im)^\s*Restart-Service\b',
    '(?im)^\s*Set-ItemProperty\b',
    '(?im)^\s*New-ItemProperty\b',
    '(?im)^\s*Remove-ItemProperty\b',
    '(?im)^\s*reg\s+add\b',
    '(?im)^\s*reg\s+delete\b'
)

$safetyFindings = @()
foreach ($file in $filesToParse) {
    $path = Join-Path -Path $root -ChildPath $file
    $content = Get-Content -Path $path -Raw
    foreach ($pattern in $forbiddenPatterns) {
        if ($content -match $pattern) {
            $safetyFindings += ('{0}: matched pattern {1}' -f $file, $pattern)
        }
    }
}

if ($safetyFindings.Count -gt 0) {
    Write-Output 'НАЙДЕНЫ_СОВПАДЕНИЯ_ПО_БЕЗОПАСНОСТИ'
    $safetyFindings | ForEach-Object { Write-Output $_ }
}
else {
    Write-Output 'ЗАПРЕЩЁННЫХ_КОМАНД_НЕ_НАЙДЕНО'
}

if ($RunCollection) {
    Write-Output ''
    Write-Output '=== Проверка: полный запуск сбора ==='
    & (Join-Path -Path $root -ChildPath 'Run-All-Stat-Collection.ps1')
}
