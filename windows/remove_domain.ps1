#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remove a domain from config_base.json routing rules, restart proxy.
#>
[CmdletBinding()]
param([string]$Domain = '')
. "$PSScriptRoot\common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Assert-Admin

if (-not (Test-Path $ConfigBase)) { Write-Error "$ConfigBase not found"; exit 1 }
Invoke-GitPullIfClean

$cfg = Get-Content $ConfigBase -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host 'Enter domain to remove'
}
$Domain = Format-Domain $Domain

$found = $cfg.route.rules |
    Where-Object { $_.PSObject.Properties['domain'] -and $_.domain -contains $Domain }

if (-not $found) { Write-Host "$Domain not found."; exit 0 }

foreach ($rule in $cfg.route.rules) {
    if ($rule.PSObject.Properties['domain'] -and $rule.domain -contains $Domain) {
        $rule.domain = @($rule.domain | Where-Object { $_ -ne $Domain })
    }
}

$json = (($cfg | ConvertTo-Json -Depth 30 | & jq '.') -join "`n") + "`n"
[System.IO.File]::WriteAllText($ConfigBase, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Success: removed $Domain."
Invoke-GitCommitAndPush "chore(routing): remove $Domain"

Write-Host 'Restarting proxy...'
Restart-Proxy
