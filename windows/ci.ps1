#Requires -Version 5.1
<#
.SYNOPSIS
    Lightweight CI for Windows: PowerShell parser + JSON lint.
.DESCRIPTION
    Heavy e2e lives in `make test` and requires admin + network.
    Mirrors macos/ci.sh.
#>
. "$PSScriptRoot\common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failed = 0

foreach ($f in Get-ChildItem -Path (Join-Path $RepoRoot 'windows'), (Join-Path $RepoRoot 'shared') -Filter '*.ps1' -File) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "PARSE FAIL: $($f.FullName)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        $failed++
    }
}

foreach ($j in Get-ChildItem -Path $RepoRoot -Filter '*.json' -File -Recurse |
        Where-Object { $_.FullName -notmatch '\\(\.git|v2rayn|runtime|node_modules)\\' }) {
    try {
        Get-Content $j.FullName -Raw | ConvertFrom-Json | Out-Null
    } catch {
        Write-Host "JSON FAIL: $($j.FullName) - $_" -ForegroundColor Red
        $failed++
    }
}

$tagsArgs = @((Join-Path $RepoRoot 'shared\proxies_conf.py'), 'tags', $ProxiesConf)
try {
    Invoke-Python -Arguments $tagsArgs | Out-Null
} catch {
    Write-Host "PROXIES.CONF FAIL: $_" -ForegroundColor Red
    $failed++
}

if ($failed -gt 0) {
    Write-Error "windows ci: $failed file(s) failed"
    exit 1
}

Write-Output 'windows ci: PowerShell parse + JSON + proxies.conf pass (run `make test` for full e2e)'
