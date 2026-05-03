#Requires -Version 7.0
#Requires -PSEdition Core
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Full integration test for sing-box-extended TUN proxy on Windows.
    Mirrors shared/test_core.sh: teardown -> verify direct -> setup -> verify all.
#>
. "$PSScriptRoot\common.ps1"
. (Join-Path $PSScriptRoot '..\shared\constants.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Assert-Admin

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

function Reset-ConnectionPool {
    foreach ($uri in $AllTestUrls) {
        $null = [System.Net.ServicePointManager]::FindServicePoint($uri).CloseConnectionGroup('')
    }
}

Write-Host '=== Phase: teardown ===' -ForegroundColor Cyan
& "$PSScriptRoot\teardown.ps1"
Reset-ConnectionPool

Write-Host '=== Verify: proxy down ===' -ForegroundColor Cyan
$d = Test-Outbound $DirectTestUrl
$i = Test-Outbound $ProxyItTestUrl
$r = Test-Outbound $ProxyRuTestUrl
Write-Result 'direct (checkip) non-empty' ([bool]$d)
if ($d -and $i) { Write-Result 'eth0 == checkip (proxy down)'  ($i -eq $d) -Detail "eth0=$i checkip=$d" }
if ($d -and $r) { Write-Result 'ident == checkip (proxy down)' ($r -eq $d) -Detail "ident=$r checkip=$d" }

Write-Host '=== Phase: setup ===' -ForegroundColor Cyan
& "$PSScriptRoot\setup.ps1"
Reset-ConnectionPool

Write-Host '=== Verify: pre-flight ===' -ForegroundColor Cyan
Write-Result 'sing-box process running' ([bool](Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue))
Write-Result "$TunAdapterName adapter present" ([bool](Get-NetAdapter -Name $TunAdapterName -ErrorAction SilentlyContinue))

Write-Host '=== Verify: outbounds distinct ===' -ForegroundColor Cyan
$directIp = Test-Outbound $DirectTestUrl
$itIp     = Test-Outbound $ProxyItTestUrl
$ruIp     = Test-Outbound $ProxyRuTestUrl
Write-Result 'direct IP non-empty'   ([bool]$directIp)
Write-Result 'proxy_it IP non-empty' ([bool]$itIp)
Write-Result 'proxy_ru IP non-empty' ([bool]$ruIp)
if ($directIp -and $itIp -and $ruIp) {
    Write-Host "[test] IPs: direct=$directIp it=$itIp ru=$ruIp" -ForegroundColor DarkGray
    Write-Result 'direct != proxy_it'   ($directIp -ne $itIp) -Detail "both=$directIp"
    Write-Result 'direct != proxy_ru'   ($directIp -ne $ruIp) -Detail "both=$directIp"
    Write-Result 'proxy_it != proxy_ru' ($itIp     -ne $ruIp) -Detail "both=$itIp"
}

Write-Host '=== Verify: rule-set integrity ===' -ForegroundColor Cyan
$expected = @()
try {
    $py = Get-PythonExe
    $expected = & $py.Exe @($py.PrefixArgs + @(
        '-c', @"
import sys; sys.path.insert(0, 'shared')
from proxies_conf import all_of_kind, load
d = load('proxies.conf')
for c in all_of_kind(d, 'geosites'): print(f'geosite-{c}.json')
for c in all_of_kind(d, 'geoips'):   print(f'geoip-{c}.json')
"@
    )) | Where-Object { $_ }
} catch { Write-Result 'rule-set: list expected' $false -Detail $_ }
if ($expected) {
    $actual = @(Get-ChildItem -Path $RuleSetDir -Filter '*.json' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name })
    $extra   = $actual   | Where-Object { $_ -notin $expected }
    $missing = $expected | Where-Object { $_ -notin $actual }
    Write-Result 'rule-set: no stale files'        (-not $extra)   -Detail "extra=$($extra -join ',')"
    Write-Result 'rule-set: all expected present'  (-not $missing) -Detail "missing=$($missing -join ',')"
    $emptyFiles = $expected | Where-Object {
        $p = Join-Path $RuleSetDir $_; (-not (Test-Path $p)) -or (Get-Item $p).Length -eq 0
    }
    Write-Result 'rule-set: all non-empty' (-not $emptyFiles) -Detail "empty=$($emptyFiles -join ',')"
}

Write-Host '=== Verify: no IPv6 leak ===' -ForegroundColor Cyan
$v6 = $null
try {
    $v6resp = Invoke-WebRequest -Uri 'https://api64.ipify.org' -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    if ($v6resp.Content -match ':') { $v6 = $v6resp.Content.Trim() }
} catch { }
Write-Result 'no IPv6 egress' (-not $v6) -Detail "v6=$v6"

Write-Host '=== Verify: add-domain round-trip ===' -ForegroundColor Cyan
$rtDomain = 'httpbin.org'
$rtBefore = $null
try {
    $resp = Invoke-WebRequest -Uri "https://$rtDomain/ip" -TimeoutSec 10 -UseBasicParsing
    $rtBefore = ($resp.Content | ConvertFrom-Json).origin
} catch { }
if (-not $rtBefore) {
    Write-Result "round-trip: $rtDomain reachable pre-add" $false
} else {
    $env:NO_GIT = '1'
    try {
        & "$PSScriptRoot\add_domain.ps1" -Domain $rtDomain -Proxy proxy_it
        Start-Sleep -Seconds 3
        $null = [System.Net.ServicePointManager]::FindServicePoint("https://$rtDomain/ip").CloseConnectionGroup('')
        $rtAfter = $null
        try {
            $resp = Invoke-WebRequest -Uri "https://$rtDomain/ip" -TimeoutSec 10 -UseBasicParsing
            $rtAfter = ($resp.Content | ConvertFrom-Json).origin
        } catch { }
        Write-Result "round-trip: $rtDomain routed via proxy_it" ($rtAfter -eq $itIp) -Detail "after=$rtAfter it=$itIp"
    } finally {
        & "$PSScriptRoot\remove_domain.ps1" -Domain $rtDomain
        Remove-Item Env:NO_GIT -ErrorAction SilentlyContinue
    }
}

Write-Host '=== Verify: log scan ===' -ForegroundColor Cyan
if (Test-Path $SingboxLog) {
    $suspicious = @(Select-String -Path $SingboxLog -Pattern 'WARN|FATAL|panic' -CaseSensitive:$false -ErrorAction SilentlyContinue)
    Write-Result 'log: no WARN/FATAL/panic' ($suspicious.Count -eq 0) -Detail "lines=$($suspicious.Count)"
    if ($suspicious.Count -gt 0) { $suspicious | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow } }
} else {
    Write-Result "log: $SingboxLog exists" $false
}

Write-Output "=== Results: $($script:pass) passed, $($script:fail) failed ==="
if ($script:fail -gt 0) { Write-Output '=== FAIL ==='; exit 1 }
Write-Output '=== PASS ==='
exit 0
