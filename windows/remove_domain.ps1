#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remove a domain from proxies.conf, restart proxy.
#>
[CmdletBinding()]
param([string]$Domain = '')
. "$PSScriptRoot\common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Assert-Admin

if (-not (Test-Path $ProxiesConf)) { Write-Error "$ProxiesConf not found"; exit 1 }
Invoke-GitPullIfClean

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host 'Enter domain to remove'
}
$Domain = Format-Domain $Domain

$rmArgs = @(
    (Join-Path $RepoRoot 'shared\proxies_conf.py'),
    'remove-domain', $Domain, $ProxiesConf
)
Invoke-Python -Arguments $rmArgs
if ($LASTEXITCODE -ne 0) { Write-Error 'remove-domain failed'; exit 1 }

Invoke-GitCommitAndPush "chore(routing): remove $Domain"

Write-Host 'Restarting proxy...'
Restart-Proxy
