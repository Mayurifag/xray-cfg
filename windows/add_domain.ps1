#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Add a domain to a proxy in proxies.conf, restart proxy.
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

if (-not (Test-Path $ProxiesConf)) { Write-Error "$ProxiesConf not found"; exit 1 }
Invoke-GitPullIfClean

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host 'Enter domain (e.g. example.com)'
}
$Domain = Format-Domain $Domain

$tagsArgs = @((Join-Path $RepoRoot 'shared\proxies_conf.py'), 'tags', $ProxiesConf)
$tags = @(Invoke-Python -Arguments $tagsArgs | Where-Object { $_ })
if ($LASTEXITCODE -ne 0 -or $tags.Count -eq 0) { Write-Error 'No proxy tags found'; exit 1 }

if ([string]::IsNullOrWhiteSpace($Proxy)) {
    Write-Host 'Available proxy tags:'
    for ($i = 0; $i -lt $tags.Count; $i++) { Write-Host "  $($i+1)) $($tags[$i])" }
    do {
        $choice = Read-Host "Select proxy by number (1-$($tags.Count))"
    } until ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $tags.Count)
    $Proxy = $tags[[int]$choice - 1]
} elseif ($Proxy -match '^\d+$') {
    $idx = [int]$Proxy
    if ($idx -lt 1 -or $idx -gt $tags.Count) { Write-Error "Invalid number $Proxy"; exit 1 }
    $Proxy = $tags[$idx - 1]
} elseif ($tags -notcontains $Proxy) {
    Write-Error "Invalid proxy tag: $Proxy. Valid: $($tags -join ', ')"
    exit 1
}

$addArgs = @(
    (Join-Path $RepoRoot 'shared\proxies_conf.py'),
    'add-domain', $Proxy, $Domain, $ProxiesConf
)
Invoke-Python -Arguments $addArgs
if ($LASTEXITCODE -ne 0) { Write-Error 'add-domain failed'; exit 1 }

Invoke-GitCommitAndPush "chore(routing): add $Domain to $Proxy"

Write-Host 'Restarting proxy...'
Restart-Proxy
