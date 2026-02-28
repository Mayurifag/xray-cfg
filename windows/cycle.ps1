#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Integration wrapper: runs the full setup->test->teardown->direct cycle in sequence.
.DESCRIPTION
    Proves the milestone DoD: setup.ps1, test.ps1 -Mode all,
    teardown.ps1, and test.ps1 -Mode direct all pass end-to-end.

    Each step is run in order. If any step exits non-zero the wrapper prints
    which step failed and exits 1 immediately. Exits 0 only when all four pass.

    Progress to console (Write-Host). Final verdict to stdout (Write-Output).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Privilege check
# ---------------------------------------------------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'cycle.ps1 must be run as Administrator. Re-run from an elevated prompt.'
    exit 1
}

Write-Host '[cycle] Starting full setup->test->teardown->direct cycle...' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Step 1: setup.ps1
# ---------------------------------------------------------------------------
Write-Host '[cycle] Step 1: setup.ps1 (start proxy)' -ForegroundColor DarkGray
& "$PSScriptRoot\setup.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host '[cycle] FAILED at step 1: setup.ps1' -ForegroundColor Red
    exit 1
}
Write-Host '[cycle] Step 1 passed.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: test.ps1 -Mode all
# ---------------------------------------------------------------------------
Write-Host '[cycle] Step 2: test.ps1 -Mode all (verify all three outbounds)' -ForegroundColor DarkGray
& "$PSScriptRoot\test.ps1" -Mode all
if ($LASTEXITCODE -ne 0) {
    Write-Host '[cycle] FAILED at step 2: test.ps1 -Mode all' -ForegroundColor Red
    exit 1
}
Write-Host '[cycle] Step 2 passed.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 3: teardown.ps1
# ---------------------------------------------------------------------------
Write-Host '[cycle] Step 3: teardown.ps1 (stop and clean up)' -ForegroundColor DarkGray
& "$PSScriptRoot\teardown.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host '[cycle] FAILED at step 3: teardown.ps1' -ForegroundColor Red
    exit 1
}
Write-Host '[cycle] Step 3 passed.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 4: test.ps1 -Mode direct
# ---------------------------------------------------------------------------
Write-Host '[cycle] Step 4: test.ps1 -Mode direct (verify proxy down, direct works)' -ForegroundColor DarkGray
& "$PSScriptRoot\test.ps1" -Mode direct
if ($LASTEXITCODE -ne 0) {
    Write-Host '[cycle] FAILED at step 4: test.ps1 -Mode direct' -ForegroundColor Red
    exit 1
}
Write-Host '[cycle] Step 4 passed.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# All steps passed
# ---------------------------------------------------------------------------
Write-Output '[cycle] All steps passed. Full cycle complete.'
exit 0
