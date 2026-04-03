param(
    [switch]$RunCollection
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToParse = Get-ChildItem -Path $root -Recurse -File -Filter '*.ps1' |
    Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj|artifacts|state)[\\/]'
    } |
    Sort-Object FullName |
    ForEach-Object {
        $_.FullName.Substring($root.Length + 1)
    }

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
