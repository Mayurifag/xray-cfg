#Requires -Version 5.1
<#
.SYNOPSIS
    Integration test for sing-box-extended TUN proxy on Windows.
.DESCRIPTION
    Verifies outbound routing, process health, and TCP connectivity.
    Use -Mode to select scope: direct | proxy_ru | proxy_it | all
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('direct', 'proxy_ru', 'proxy_it', 'all')]
    [string]$Mode
)
. "$PSScriptRoot\common.ps1"
. (Join-Path $PSScriptRoot '..\shared\constants.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:pass = 0
$script:fail = 0

function Write-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    if ($Passed) {
        Write-Host "[test] PASS: $Name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[test] FAIL: $Name $(if ($Detail) {"- $Detail"})" -ForegroundColor Red
        $script:fail++
    }
}

if ($Mode -ne 'direct') {
    Write-Host '[test] Pre-flight state checks...' -ForegroundColor Cyan
    Write-Result 'pre-flight: sing-box process running' (Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue) -ne $null
    Write-Result "pre-flight: $TunAdapterName adapter present" (Get-NetAdapter -Name $TunAdapterName -ErrorAction SilentlyContinue) -ne $null
}

if ($Mode -eq 'all') {
    Write-Host '[test] Outbound IP tests...' -ForegroundColor Cyan
    $directIp = Test-Outbound $DirectTestUrl
    $itIp     = Test-Outbound $ProxyItTestUrl
    $ruIp     = Test-Outbound $ProxyRuTestUrl
    Write-Result 'direct IP non-empty'   ($directIp -ne $null -and $directIp -ne '')
    Write-Result 'proxy_it IP non-empty' ($itIp     -ne $null -and $itIp     -ne '')
    Write-Result 'proxy_ru IP non-empty' ($ruIp     -ne $null -and $ruIp     -ne '')
    if ($directIp -and $itIp -and $ruIp) {
        Write-Host "[test] IPs: direct=$directIp it=$itIp ru=$ruIp" -ForegroundColor DarkGray
        Write-Result 'direct != proxy_it'   ($directIp -ne $itIp) -Detail "both=$directIp"
        Write-Result 'direct != proxy_ru'   ($directIp -ne $ruIp) -Detail "both=$directIp"
        Write-Result 'proxy_it != proxy_ru' ($itIp     -ne $ruIp) -Detail "both=$itIp"
    }
}

if ($Mode -eq 'proxy_ru') {
    $ip = Test-Outbound $ProxyRuTestUrl
    Write-Result 'proxy_ru IP non-empty' ($ip -ne $null -and $ip -ne '')
    if ($ip) { Write-Host "[test] proxy_ru: $ip" -ForegroundColor DarkGray }
}
if ($Mode -eq 'proxy_it') {
    $ip = Test-Outbound $ProxyItTestUrl
    Write-Result 'proxy_it IP non-empty' ($ip -ne $null -and $ip -ne '')
    if ($ip) { Write-Host "[test] proxy_it: $ip" -ForegroundColor DarkGray }
}

if ($Mode -eq 'direct') {
    Write-Host '[test] Stopping proxy via teardown.ps1...' -ForegroundColor Cyan
    & "$PSScriptRoot\teardown.ps1"

    foreach ($uri in $AllTestUrls) {
        $null = [System.Net.ServicePointManager]::FindServicePoint($uri).CloseConnectionGroup('')
    }

    $d = Test-Outbound $DirectTestUrl
    $i = Test-Outbound $ProxyItTestUrl
    $r = Test-Outbound $ProxyRuTestUrl
    Write-Result 'direct-verify: checkip non-empty' ($d -ne $null -and $d -ne '')
    if ($d -and $i) { Write-Result 'direct-verify: eth0 == checkip'   ($i -eq $d) -Detail "eth0=$i checkip=$d" }
    if ($d -and $r) { Write-Result 'direct-verify: ident == checkip'  ($r -eq $d) -Detail "ident=$r checkip=$d" }
}

Write-Output "=== Results: $($script:pass) passed, $($script:fail) failed ==="
if ($script:fail -gt 0) { Write-Output '=== FAIL ==='; exit 1 }
Write-Output '=== PASS ==='
exit 0
