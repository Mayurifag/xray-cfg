#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remove a domain from config.json routing rules, then restart the proxy.
.DESCRIPTION
    Edits config.json in the repo root (one level above windows/), removes the
    given domain from any routing rule that contains it, and calls setup.ps1 to
    regenerate the deployed xray config and restart xray + sing-box.

    The Domain argument is optional; the script prompts interactively when omitted.

.PARAMETER Domain
    Domain to remove (e.g. example.com, domain:example.com, geosite:discord).
    http(s):// prefix and trailing paths are stripped automatically.

.EXAMPLE
    .\remove_domain.ps1 example.com
    .\remove_domain.ps1
#>
[CmdletBinding()]
param(
    [string]$Domain = ''
)
. "$PSScriptRoot\common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Assert-Admin

$ConfigFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.json'

if (-not (Test-Path $ConfigFile)) {
    Write-Error "config.json not found at $ConfigFile"
    exit 1
}

Invoke-GitPullIfClean (Split-Path $PSScriptRoot -Parent)

$raw = Get-Content $ConfigFile -Raw
try {
    $cfg = $raw | ConvertFrom-Json
} catch {
    Write-Error "config.json is not valid JSON: $_"
    exit 1
}

# --- domain input ---
if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host 'Enter entry to remove (e.g. example.com, geoip:google, geosite:youtube)'
}

function Format-Domain([string]$d) {
    $prefix = 'domain:'
    if ($d -match '^geosite:' -or $d -match '^geoip:') {
        return $d
    }
    if ($d -match '^domain:') {
        $d = $d -replace '^domain:', ''
    }
    $d = $d -replace '^https?://', ''
    $d = ($d -split '/')[0]
    return "${prefix}${d}"
}

$Domain = Format-Domain $Domain
$prop = if ($Domain -match '^geoip:') { 'ip' } else { 'domain' }

# --- existence check ---
$found = $cfg.routing.rules |
    Where-Object { $_.PSObject.Properties[$prop] -and $_.$prop -contains $Domain }

if (-not $found) {
    Write-Host "$Domain not found in any routing rules. Exiting."
    exit 0
}

# --- remove from all rules that contain it ---
foreach ($rule in $cfg.routing.rules) {
    if ($rule.PSObject.Properties[$prop] -and $rule.$prop -contains $Domain) {
        $rule.$prop = @($rule.$prop | Where-Object { $_ -ne $Domain })
    }
}

# Write back without BOM, 2-space indent via jq
$json = (($cfg | ConvertTo-Json -Depth 20 | & jq '.') -join "`n") + "`n"
[System.IO.File]::WriteAllText($ConfigFile, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Success: Removed $Domain from routing rules."
Invoke-GitCommitAndPush (Split-Path $PSScriptRoot -Parent) "chore(routing): remove $Domain from routing rules"

# Regenerate deployed config + restart proxy
Write-Host 'Restarting proxy to apply changes...'
& "$PSScriptRoot\setup.ps1"
