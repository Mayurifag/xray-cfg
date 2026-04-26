#Requires -Version 5.1
<#
.SYNOPSIS
    Truncate xray + sing-box log files when they exceed a size cap.
.DESCRIPTION
    Runs daily via the xray-logrotate Scheduled Task. Truncates (Clear-Content)
    each log if larger than -MaxMB. Skips missing files. Idempotent.
#>
param(
    [string]$LogDir = (Join-Path $PSScriptRoot 'v2rayn'),
    [int]$MaxMB = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$paths = @(
    (Join-Path $LogDir 'singbox.log'),
    (Join-Path $LogDir 'setup.log'),
    (Join-Path $LogDir 'bin\xray\xray-error.log')
)

foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }
    $sizeMB = (Get-Item $p).Length / 1MB
    if ($sizeMB -gt $MaxMB) {
        Clear-Content $p -ErrorAction SilentlyContinue
        Write-Output "rotated $p (was $([math]::Round($sizeMB,1)) MB)"
    }
}
