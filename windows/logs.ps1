#Requires -Version 7.0
#Requires -PSEdition Core
. "$PSScriptRoot\common.ps1"

$log = Join-Path $RuntimeDir 'singbox.log'
if (-not (Test-Path $log)) { Write-Host "No log yet at $log"; exit 0 }
Get-Content $log -Tail 50 -Wait
