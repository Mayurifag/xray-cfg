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
    $RuleSetDir,
    '--interface-name', $TunAdapterName,
    '--log-output', $SingboxLog
)
$py = Get-PythonExe
$global:LASTEXITCODE = 0
$secrets | & $py.Exe @($py.PrefixArgs + $pyArgs)
if ($LASTEXITCODE -ne 0) { throw "build_config.py exit $LASTEXITCODE" }
