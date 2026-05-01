#Requires -Version 5.1
#Requires -RunAsAdministrator
. "$PSScriptRoot\common.ps1"
<#
.SYNOPSIS
    Tear down sing-box-extended TUN proxy on Windows.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Assert-Admin
Write-Phase 'teardown' 'Phase 1: stop sing-box processes'
Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'xray'     -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Phase 'teardown' 'Phase 2: delete Scheduled Tasks'
$tasksToRemove = @(
    $TaskNameSingbox, $TaskNameGeodata,
    'xray-cfg-singbox', 'xray-cfg-geodata',          # legacy (previous repo name)
    'xray-proxy', 'xray-geodata', 'xray-logrotate'   # legacy (xray stack)
)
foreach ($name in $tasksToRemove) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Phase 'teardown' "  removed task $name"
    }
}

Write-Phase 'teardown' 'Phase 3: wait for TUN adapter to disappear'
for ($i = 0; $i -lt 5; $i++) {
    $a = Get-NetAdapter -Name $TunAdapterName -ErrorAction SilentlyContinue
    if (-not $a) { break }
    Start-Sleep -Seconds 1
}

Write-Phase 'teardown' 'Phase 4: verify clean'
$dirty = @()
if (Get-Process -Name 'sing-box', 'xray' -ErrorAction SilentlyContinue) { $dirty += 'process(es) still running' }
if (Get-NetAdapter -Name $TunAdapterName -ErrorAction SilentlyContinue) { $dirty += "$TunAdapterName adapter still present" }
foreach ($name in $tasksToRemove) {
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        $dirty += "Scheduled Task $name still registered"
    }
}

if ($dirty.Count -eq 0) {
    Write-Output 'Teardown complete. System clean.'
    exit 0
}
Write-Host '[teardown] Teardown incomplete:' -ForegroundColor Red
foreach ($d in $dirty) { Write-Host "  - $d" -ForegroundColor Red }
exit 1
