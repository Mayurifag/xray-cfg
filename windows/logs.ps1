#Requires -Version 5.1
. "$PSScriptRoot\common.ps1"

$log = Join-Path $RuntimeDir 'singbox.log'
if (-not (Test-Path $log)) { Write-Host "No log yet at $log"; exit 0 }
Get-Content $log -Tail 50 -Wait
