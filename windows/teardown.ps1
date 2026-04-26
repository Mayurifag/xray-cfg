#Requires -Version 5.1
#Requires -RunAsAdministrator
. "$PSScriptRoot\common.ps1"
<#
.SYNOPSIS
    Tear down xray + sing-box TUN proxy on Windows, reversing all setup.ps1 side-effects.
.DESCRIPTION
    Kills xray.exe and sing-box.exe (by PID from proxy.pid, then by name as fallback),
    deletes the xray-proxy Scheduled Task, waits for the singbox_tun WinTun adapter to
    disappear, then verifies the system is clean. Safe to run at any time, including when
    nothing is set up.

    Progress to stderr (Write-Host). Final verdict to stdout (Write-Output).
    Exits 0 when clean; exits 1 with detail when something could not be removed.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Privilege check
# ---------------------------------------------------------------------------
Assert-Admin

Write-Host '[teardown] Starting teardown of xray+sing-box proxy...' -ForegroundColor Cyan

$PidFile = Join-Path $PSScriptRoot 'v2rayn\proxy.pid'

# ---------------------------------------------------------------------------
# Phase 1: Kill processes
# ---------------------------------------------------------------------------
Write-Phase 'teardown' 'Phase 1: kill processes'

$stoppedPids = @()

if (Test-Path $PidFile) {
    $pidLines = Get-Content $PidFile -ErrorAction SilentlyContinue
    foreach ($line in $pidLines) {
        $line = $line.Trim()
        if ($line -match '^\d+$') {
            $procId = [int]$line
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            $stoppedPids += $procId
        }
    }
    if ($stoppedPids.Count -gt 0) {
        Write-Host "[teardown] Stopped PIDs from proxy.pid: $($stoppedPids -join ', ')" -ForegroundColor DarkGray
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "[teardown] Deleted $PidFile" -ForegroundColor DarkGray
} else {
    Write-Host '[teardown] proxy.pid not found - no PID-based kill.' -ForegroundColor DarkGray
}

# Name-based fallback: catches stragglers not in proxy.pid or if proxy.pid was absent
$stragglers = Get-Process -Name 'xray','sing-box' -ErrorAction SilentlyContinue
if ($stragglers) {
    $stragglers | Stop-Process -Force
    Write-Host "[teardown] Stopped by name: $($stragglers.Name -join ', ') (PIDs: $($stragglers.Id -join ', '))" -ForegroundColor DarkGray
} else {
    Write-Host '[teardown] No xray/sing-box processes found by name - already stopped.' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Phase 2: Delete Scheduled Task
# ---------------------------------------------------------------------------
Write-Phase 'teardown' 'Phase 2: delete Scheduled Task xray-proxy'

$task = Get-ScheduledTask -TaskName 'xray-proxy' -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName 'xray-proxy' -Confirm:$false
    Write-Phase 'teardown' 'Scheduled Task xray-proxy deleted.'
} else {
    Write-Phase 'teardown' 'Scheduled Task xray-proxy not found - already clean.'
}

$geodataTask = Get-ScheduledTask -TaskName 'xray-geodata' -ErrorAction SilentlyContinue
if ($geodataTask) {
    Unregister-ScheduledTask -TaskName 'xray-geodata' -Confirm:$false
    Write-Phase 'teardown' 'Scheduled Task xray-geodata deleted.'
} else {
    Write-Phase 'teardown' 'Scheduled Task xray-geodata not found - already clean.'
}

$rotateTask = Get-ScheduledTask -TaskName 'xray-logrotate' -ErrorAction SilentlyContinue
if ($rotateTask) {
    Unregister-ScheduledTask -TaskName 'xray-logrotate' -Confirm:$false
    Write-Phase 'teardown' 'Scheduled Task xray-logrotate deleted.'
} else {
    Write-Phase 'teardown' 'Scheduled Task xray-logrotate not found - already clean.'
}

# ---------------------------------------------------------------------------
# Phase 3: Wait for singbox_tun adapter to disappear (up to 5s)
# ---------------------------------------------------------------------------
Write-Phase 'teardown' 'Phase 3: wait for singbox_tun adapter removal'

$waited  = 0
$adapter = $null
while ($waited -lt 5) {
    $adapter = Get-NetAdapter | Where-Object { $_.Name -eq 'singbox_tun' }
    if ($adapter -eq $null) { break }
    Start-Sleep -Seconds 1
    $waited++
}

$adapter = Get-NetAdapter | Where-Object { $_.Name -eq 'singbox_tun' }
if ($adapter -eq $null) {
    Write-Host '[teardown] singbox_tun adapter gone.' -ForegroundColor DarkGray
} else {
    Write-Host "[teardown] WARNING: singbox_tun adapter still present after ${waited}s: $($adapter.Status)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Phase 4: Verify clean state
# ---------------------------------------------------------------------------
Write-Phase 'teardown' 'Phase 4: verify clean state'

$dirty = @()

$leftoverProcs = Get-Process -Name 'xray','sing-box' -ErrorAction SilentlyContinue
if ($leftoverProcs) {
    $dirty += "processes still running: $($leftoverProcs.Name -join ', ') (PIDs: $($leftoverProcs.Id -join ', '))"
}

$leftoverAdapter = Get-NetAdapter | Where-Object { $_.Name -eq 'singbox_tun' }
if ($leftoverAdapter -ne $null) {
    $dirty += "singbox_tun adapter still present ($($leftoverAdapter.Status))"
}

$taskStillExists = Get-ScheduledTask -TaskName 'xray-proxy' -ErrorAction SilentlyContinue
if ($taskStillExists -ne $null) {
    $dirty += 'Scheduled Task xray-proxy still registered'
}

$geodataTaskStillExists = Get-ScheduledTask -TaskName 'xray-geodata' -ErrorAction SilentlyContinue
if ($geodataTaskStillExists -ne $null) {
    $dirty += 'Scheduled Task xray-geodata still registered'
}

$rotateTaskStillExists = Get-ScheduledTask -TaskName 'xray-logrotate' -ErrorAction SilentlyContinue
if ($rotateTaskStillExists -ne $null) {
    $dirty += 'Scheduled Task xray-logrotate still registered'
}

if ($dirty.Count -eq 0) {
    Write-Output 'Teardown complete. System clean.'
    exit 0
} else {
    Write-Host '[teardown] Teardown incomplete - the following items remain:' -ForegroundColor Red
    foreach ($item in $dirty) {
        Write-Host "  - $item" -ForegroundColor Red
    }
    Write-Output 'Teardown incomplete.'
    exit 1
}
