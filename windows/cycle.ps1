#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Full integration cycle: setup → test all → teardown → test direct.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run as Administrator.'; exit 1
}

$steps = @(
    @{ Name = 'setup';        Args = @('setup.ps1') },
    @{ Name = 'test all';     Args = @('test.ps1', '-Mode', 'all') },
    @{ Name = 'teardown';     Args = @('teardown.ps1') },
    @{ Name = 'test direct';  Args = @('test.ps1', '-Mode', 'direct') }
)

foreach ($s in $steps) {
    Write-Host "[cycle] >>> $($s.Name)" -ForegroundColor Cyan
    & "$PSScriptRoot\$($s.Args[0])" @($s.Args[1..($s.Args.Length - 1)])
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[cycle] FAILED at $($s.Name)" -ForegroundColor Red
        exit 1
    }
}

Write-Output '[cycle] all steps passed'
