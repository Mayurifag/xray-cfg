#Requires -Version 5.1
<#
.SYNOPSIS
    Print the sing-box config (built from proxies.conf + subscriptions) to stdout.
#>
. "$PSScriptRoot\common.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command ejson -ErrorAction SilentlyContinue)) {
    Write-Error 'ejson not found in PATH.'
    exit 1
}
$secrets = (& ejson decrypt $SecretsFile | Out-String).Trim()
if (-not $secrets) { Write-Error 'ejson decrypt produced empty output.'; exit 1 }

$pyArgs = @(
    (Join-Path $RepoRoot 'shared\build_config.py'),
    $ProxiesConf,
    $secrets,
    $RuleSetDir,
    '--interface-name', $TunAdapterName
)
Invoke-Python -Arguments $pyArgs
