#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Add a domain to a proxy outbound rule in config.json, then restart the proxy.
.DESCRIPTION
    Edits config.json in the repo root (one level above windows/), adds the given
    domain to the specified proxy outbound rule, and calls setup.ps1 to regenerate
    the deployed xray config and restart xray + sing-box.

    Both arguments are optional; the script prompts interactively when omitted.

.PARAMETER Domain
    Domain to add (e.g. example.com, domain:example.com, geosite:discord).
    http(s):// prefix and trailing paths are stripped automatically.

.PARAMETER Proxy
    Proxy outbound tag (e.g. proxy_ru, proxy_it) or its 1-based menu number.

.EXAMPLE
    .\add_domain.ps1 example.com proxy_ru
    .\add_domain.ps1 example.com 1
    .\add_domain.ps1
#>
[CmdletBinding()]
param(
    [string]$Domain = '',
    [string]$Proxy  = ''
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
    $Domain = Read-Host 'Enter domain (e.g. example.com)'
}

$Domain = Format-Domain $Domain

# --- collect proxy tags that have domain arrays ---
$tags = @(
    $cfg.routing.rules |
        Where-Object { $_.PSObject.Properties['domain'] -and $_.domain -ne $null } |
        ForEach-Object { $_.outboundTag } |
        Select-Object -Unique | Sort-Object
)

if ($tags.Count -eq 0) {
    Write-Error 'No outbound rules with domain arrays found in config.json.'
    exit 1
}

# --- proxy selection ---
if ([string]::IsNullOrWhiteSpace($Proxy)) {
    Write-Host 'Available proxy tags:'
    for ($i = 0; $i -lt $tags.Count; $i++) {
        Write-Host "  $($i+1)) $($tags[$i])"
    }
    do {
        $choice = Read-Host "Select proxy by number (1-$($tags.Count))"
    } until ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $tags.Count)
    $Proxy = $tags[[int]$choice - 1]
} elseif ($Proxy -match '^\d+$') {
    $idx = [int]$Proxy
    if ($idx -lt 1 -or $idx -gt $tags.Count) {
        Write-Error "Invalid proxy number: $Proxy (valid: 1-$($tags.Count))"
        exit 1
    }
    $Proxy = $tags[$idx - 1]
} elseif ($tags -notcontains $Proxy) {
    Write-Error "Invalid proxy tag: $Proxy. Valid tags: $($tags -join ', ')"
    exit 1
}

# --- idempotency check ---
$rule = $cfg.routing.rules | Where-Object { $_.outboundTag -eq $Proxy -and $_.PSObject.Properties['domain'] }
if ($rule.domain -contains $Domain) {
    Write-Host "No-op: $Domain is already in $Proxy. No changes made."
    exit 0
}

# --- add domain (unique, sorted to keep config tidy) ---
$rule = $cfg.routing.rules | Where-Object { $_.outboundTag -eq $Proxy -and $_.PSObject.Properties['domain'] }
$rule.domain = @(($rule.domain + $Domain) | Select-Object -Unique | Sort-Object)

# Write back without BOM, 2-space indent via jq
$json = (($cfg | ConvertTo-Json -Depth 20 | & jq '.') -join "`n") + "`n"
[System.IO.File]::WriteAllText($ConfigFile, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Success: Added $Domain to $Proxy outbound rule."
Invoke-GitCommitAndPush (Split-Path $PSScriptRoot -Parent) "chore(routing): add $Domain to $Proxy"

# Regenerate deployed config + restart proxy
Write-Host 'Restarting proxy to apply changes...'
& "$PSScriptRoot\setup.ps1"
