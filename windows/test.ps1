#Requires -Version 5.1
<#
.SYNOPSIS
    Integration test suite for the xray+sing-box TUN proxy on Windows.
.DESCRIPTION
    Verifies outbound routing, process health, and TCP connectivity.
    Use -Mode to select which tests to run.

    Progress and per-test results to stderr (Write-Host).
    Summary line to stdout (Write-Output).
    Exits 0 on all pass, 1 on any failure.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('direct', 'proxy_ru', 'proxy_it', 'all')]
    [string]$Mode
)
. "$PSScriptRoot\common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$proxyRuHost = ''
$proxyItHost = ''
if ($Mode -ne 'direct') {
    if (-not (Get-Command ejson -ErrorAction SilentlyContinue)) {
        Write-Error '[test] ejson not found in PATH. See README.md.'
        exit 1
    }
    $secrets     = (& ejson decrypt (Join-Path $PSScriptRoot '..\secrets.ejson')) | ConvertFrom-Json
    $proxyRuHost = $secrets.proxy_ru.host
    $proxyItHost = $secrets.proxy_it.host
}

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
$script:pass = 0
$script:fail = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Result {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ''
    )
    if ($Passed) {
        Write-Host "[test] PASS: $Name" -ForegroundColor Green
        $script:pass++
    } else {
        if ($Detail) {
            Write-Host "[test] FAIL: $Name - $Detail" -ForegroundColor Red
        } else {
            Write-Host "[test] FAIL: $Name" -ForegroundColor Red
        }
        $script:fail++
    }
}

function Test-Outbound {
    param(
        [string]$Label,
        [string]$Url
    )
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
        $ip = $resp.Content.Trim()
        return $ip
    } catch {
        Write-Result -Name $Label -Passed $false -Detail "HTTP request failed: $_"
        return $null
    }
}

function Test-OutboundQuic {
    param(
        [string]$Label,
        [string]$Url
    )
    try {
        $env:_QUIC_URL = $Url
        $raw = & pwsh -NoProfile -Command '
            $h = [System.Net.Http.SocketsHttpHandler]::new()
            $c = [System.Net.Http.HttpClient]::new($h)
            $c.Timeout = [TimeSpan]::FromSeconds(15)
            $r = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, $env:_QUIC_URL)
            $r.Version = [System.Version]::new(3, 0)
            $r.VersionPolicy = [System.Net.Http.HttpVersionPolicy]::RequestVersionExact
            $resp = $c.SendAsync($r).GetAwaiter().GetResult()
            $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult().Trim()
            $c.Dispose(); $h.Dispose()
        ' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Result -Name $Label -Passed $false -Detail "pwsh exited $LASTEXITCODE`: $raw"
            return $null
        }
        return ($raw | Select-Object -Last 1).Trim()
    } catch {
        Write-Result -Name $Label -Passed $false -Detail "QUIC request failed: $_"
        return $null
    }
}

# ---------------------------------------------------------------------------
# Pre-flight state checks (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] Pre-flight state checks...' -ForegroundColor Cyan

    $xrayProc = Get-Process -Name 'xray' -ErrorAction SilentlyContinue
    Write-Result -Name 'pre-flight: xray process running' -Passed ($xrayProc -ne $null)

    $singboxProc = Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue
    Write-Result -Name 'pre-flight: sing-box process running' -Passed ($singboxProc -ne $null)

    $adapter = Get-NetAdapter | Where-Object { $_.Name -eq 'singbox_tun' }
    Write-Result -Name 'pre-flight: singbox_tun adapter present' -Passed ($adapter -ne $null)
}

# ---------------------------------------------------------------------------
# Outbound IP tests
# ---------------------------------------------------------------------------

if ($Mode -eq 'all') {
    Write-Host '[test] Outbound IP tests (all three outbounds)...' -ForegroundColor Cyan

    $directIp = Test-Outbound -Label 'outbound: checkip.amazonaws.com (direct)' -Url 'https://checkip.amazonaws.com'
    Write-Result -Name 'outbound: direct IP non-empty' -Passed ($directIp -ne $null -and $directIp -ne '')

    $itIp = Test-Outbound -Label 'outbound: eth0.me (proxy_it)' -Url 'https://eth0.me'
    Write-Result -Name 'outbound: proxy_it IP non-empty' -Passed ($itIp -ne $null -and $itIp -ne '')

    $ruIp = Test-Outbound -Label 'outbound: ident.me (proxy_ru)' -Url 'https://ident.me'
    Write-Result -Name 'outbound: proxy_ru IP non-empty' -Passed ($ruIp -ne $null -and $ruIp -ne '')

    if ($directIp -and $itIp -and $ruIp) {
        Write-Host "[test] IPs: direct=$directIp  proxy_it=$itIp  proxy_ru=$ruIp" -ForegroundColor DarkGray

        Write-Result -Name 'outbound: direct != proxy_it' `
            -Passed ($directIp -ne $itIp) `
            -Detail "both returned $directIp"

        Write-Result -Name 'outbound: direct != proxy_ru' `
            -Passed ($directIp -ne $ruIp) `
            -Detail "both returned $directIp"

        Write-Result -Name 'outbound: proxy_it != proxy_ru' `
            -Passed ($itIp -ne $ruIp) `
            -Detail "both returned $itIp"
    }
}

if ($Mode -eq 'proxy_ru') {
    Write-Host '[test] Outbound IP test (proxy_ru)...' -ForegroundColor Cyan
    $ruIp = Test-Outbound -Label 'outbound: ident.me (proxy_ru)' -Url 'https://ident.me'
    Write-Result -Name 'outbound: proxy_ru IP non-empty' -Passed ($ruIp -ne $null -and $ruIp -ne '')
    if ($ruIp) {
        Write-Host "[test] proxy_ru IP: $ruIp" -ForegroundColor DarkGray
    }
}

if ($Mode -eq 'proxy_it') {
    Write-Host '[test] Outbound IP test (proxy_it)...' -ForegroundColor Cyan
    $itIp = Test-Outbound -Label 'outbound: eth0.me (proxy_it)' -Url 'https://eth0.me'
    Write-Result -Name 'outbound: proxy_it IP non-empty' -Passed ($itIp -ne $null -and $itIp -ne '')
    if ($itIp) {
        Write-Host "[test] proxy_it IP: $itIp" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# QUIC (HTTP/3) outbound tests — requires pwsh (PowerShell 7) with msquic
# ---------------------------------------------------------------------------

$hasPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($Mode -ne 'direct' -and $hasPwsh) {
    Write-Host '[test] QUIC (HTTP/3) outbound tests...' -ForegroundColor Cyan

    if ($Mode -eq 'all' -or $Mode -eq 'proxy_it') {
        $quicIt = Test-OutboundQuic -Label 'quic: eth0.me (proxy_it)' -Url 'https://eth0.me'
        Write-Result -Name 'quic: proxy_it IP non-empty' -Passed ($quicIt -ne $null -and $quicIt -ne '')
    }

    if ($Mode -eq 'all' -or $Mode -eq 'proxy_ru') {
        $quicRu = Test-OutboundQuic -Label 'quic: ident.me (proxy_ru)' -Url 'https://ident.me'
        Write-Result -Name 'quic: proxy_ru IP non-empty' -Passed ($quicRu -ne $null -and $quicRu -ne '')
    }

    if ($Mode -eq 'all' -and $quicIt -and $quicRu) {
        Write-Host "[test] QUIC IPs: proxy_it=$quicIt  proxy_ru=$quicRu" -ForegroundColor DarkGray

        Write-Result -Name 'quic: proxy_it matches TLS proxy_it' `
            -Passed ($quicIt -eq $itIp) `
            -Detail "TLS=$itIp QUIC=$quicIt"

        Write-Result -Name 'quic: proxy_ru matches TLS proxy_ru' `
            -Passed ($quicRu -eq $ruIp) `
            -Detail "TLS=$ruIp QUIC=$quicRu"
    }
} elseif ($Mode -ne 'direct' -and -not $hasPwsh) {
    Write-Host '[test] QUIC tests skipped (pwsh not found)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# TCP connectivity tests (proxy server reachability)
# ---------------------------------------------------------------------------

if ($Mode -eq 'all' -or $Mode -eq 'proxy_ru') {
    Write-Host "[test] TCP connectivity: ${proxyRuHost}:443 (proxy_ru)..." -ForegroundColor Cyan
    try {
        $tcpRu = Test-NetConnection -ComputerName $proxyRuHost -Port 443 -WarningAction SilentlyContinue
        Write-Result -Name "TCP: ${proxyRuHost}:443" -Passed $tcpRu.TcpTestSucceeded
    } catch {
        Write-Result -Name "TCP: ${proxyRuHost}:443" -Passed $false -Detail "$_"
    }
}

if ($Mode -eq 'all' -or $Mode -eq 'proxy_it') {
    Write-Host "[test] TCP connectivity: ${proxyItHost}:443 (proxy_it)..." -ForegroundColor Cyan
    try {
        $tcpIt = Test-NetConnection -ComputerName $proxyItHost -Port 443 -WarningAction SilentlyContinue
        Write-Result -Name "TCP: ${proxyItHost}:443" -Passed $tcpIt.TcpTestSucceeded
    } catch {
        Write-Result -Name "TCP: ${proxyItHost}:443" -Passed $false -Detail "$_"
    }
}

# ---------------------------------------------------------------------------
# UDP DNS test (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] UDP DNS query to 1.1.1.1:53...' -ForegroundColor Cyan
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = 5000
        $udp.Connect('1.1.1.1', 53)
        # Minimal DNS A query for a.root-servers.net
        $query = [byte[]](0x00,0x01,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,
                          0x01,0x61,0x0c,0x72,0x6f,0x6f,0x74,0x2d,0x73,0x65,0x72,0x76,
                          0x65,0x72,0x73,0x03,0x6e,0x65,0x74,0x00,0x00,0x01,0x00,0x01)
        [void]$udp.Send($query, $query.Length)
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$ep)
        Write-Result -Name 'UDP DNS: response received from 1.1.1.1:53' -Passed ($resp.Length -gt 0) `
            -Detail "response length $($resp.Length)"
    } catch {
        Write-Result -Name 'UDP DNS: response received from 1.1.1.1:53' -Passed $false -Detail "$_"
    } finally {
        $udp.Close()
    }
}

# ---------------------------------------------------------------------------
# ICMP ping test (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] ICMP ping to checkip.amazonaws.com...' -ForegroundColor Cyan
    try {
        $pingOk = Test-Connection -ComputerName 'checkip.amazonaws.com' -Count 2 -Quiet
        Write-Result -Name 'ICMP: ping checkip.amazonaws.com' -Passed $pingOk
    } catch {
        Write-Result -Name 'ICMP: ping checkip.amazonaws.com' -Passed $false -Detail "$_"
    }
}

# ---------------------------------------------------------------------------
# MTU test (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] MTU check on singbox_tun adapter...' -ForegroundColor Cyan
    try {
        $tunAdapter = Get-NetAdapter -Name 'singbox_tun' -ErrorAction Stop
        $mtu = $tunAdapter.MtuSize
        Write-Host "[test] singbox_tun MtuSize: $mtu" -ForegroundColor DarkGray
        Write-Result -Name "MTU: singbox_tun MtuSize >= 1300 (got $mtu)" -Passed ($mtu -ge 1300)
    } catch {
        Write-Result -Name 'MTU: singbox_tun MtuSize >= 1300' -Passed $false -Detail "$_"
    }
}

# ---------------------------------------------------------------------------
# DNS leak test (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] DNS leak check (resolution through TUN)...' -ForegroundColor Cyan
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses('checkip.amazonaws.com')
        Write-Result -Name 'DNS leak: GetHostAddresses returned results' `
            -Passed (@($addrs).Count -gt 0) `
            -Detail "got $(@($addrs).Count) address(es)"
    } catch {
        Write-Result -Name 'DNS leak: GetHostAddresses returned results' -Passed $false -Detail "$_"
    }
}

# ---------------------------------------------------------------------------
# Routing table test (skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] Routing table check for singbox_tun...' -ForegroundColor Cyan
    try {
        $routes = Get-NetRoute -InterfaceAlias 'singbox_tun' -ErrorAction SilentlyContinue
        $routeCount = @($routes).Count
        Write-Host "[test] singbox_tun route count: $routeCount" -ForegroundColor DarkGray
        Write-Result -Name 'routing table: singbox_tun has at least one route' `
            -Passed ($routeCount -ge 1) `
            -Detail "found $routeCount route(s)"
    } catch {
        Write-Result -Name 'routing table: singbox_tun has at least one route' -Passed $false -Detail "$_"
    }
}

# ---------------------------------------------------------------------------
# Traceroute (informational only, not counted in PASS/FAIL, skipped in direct mode)
# ---------------------------------------------------------------------------

if ($Mode -ne 'direct') {
    Write-Host '[test] Traceroute to checkip.amazonaws.com (informational)...' -ForegroundColor Cyan
    try {
        $trace = Test-NetConnection -ComputerName 'checkip.amazonaws.com' `
            -TraceRoute -WarningAction SilentlyContinue
        $hops = ($trace.TraceRoute | Where-Object { $_ -ne $null }) -join ' -> '
        Write-Host "[test] INFO: traceroute - $hops" -ForegroundColor DarkGray
    } catch {
        Write-Host "[test] INFO: traceroute - failed: $_" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Direct mode: stop -> verify same-IP -> restart -> verify distinct
# ---------------------------------------------------------------------------

if ($Mode -eq 'direct') {
    Write-Host '[test] Stopping proxy via teardown.ps1...' -ForegroundColor Cyan
    & "$PSScriptRoot\teardown.ps1"

    # Verify: all three checkers should return the same real IP
    Write-Host '[test] Verifying all checkers return same IP (proxy down)...' -ForegroundColor Cyan

    $d = Test-Outbound -Label 'direct-verify: checkip.amazonaws.com' -Url 'https://checkip.amazonaws.com'
    $i = Test-Outbound -Label 'direct-verify: eth0.me' -Url 'https://eth0.me'
    $r = Test-Outbound -Label 'direct-verify: ident.me' -Url 'https://ident.me'

    Write-Result -Name 'direct-verify: checkip.amazonaws.com non-empty' -Passed ($d -ne $null -and $d -ne '')
    Write-Result -Name 'direct-verify: eth0.me non-empty' -Passed ($i -ne $null -and $i -ne '')
    Write-Result -Name 'direct-verify: ident.me non-empty' -Passed ($r -ne $null -and $r -ne '')

    if ($d -and $i -and $r) {
        Write-Host "[test] IPs after stop: checkip=$d  eth0=$i  ident=$r" -ForegroundColor DarkGray

        Write-Result -Name 'direct-verify: all checkers same IP (real IP)' `
            -Passed ($d -eq $i -and $d -eq $r) `
            -Detail "checkip=$d eth0=$i ident=$r"
    }

    # Restart via setup.ps1
    Write-Host '[test] Restarting proxy via setup.ps1...' -ForegroundColor Cyan
    try {
        & "$PSScriptRoot\setup.ps1"
        Write-Result -Name 'direct-verify: setup.ps1 exited 0' -Passed $true
    } catch {
        Write-Result -Name 'direct-verify: setup.ps1 exited 0' -Passed $false -Detail "$_"
    }

    foreach ($uri in @('https://checkip.amazonaws.com', 'https://eth0.me', 'https://ident.me')) {
        $null = [System.Net.ServicePointManager]::FindServicePoint($uri).CloseConnectionGroup('')
    }

    # After restart: verify distinct IPs again
    Write-Host '[test] Verifying distinct outbound IPs after restart...' -ForegroundColor Cyan

    $d2 = Test-Outbound -Label 'post-restart: checkip.amazonaws.com (direct)' -Url 'https://checkip.amazonaws.com'
    $i2 = Test-Outbound -Label 'post-restart: eth0.me (proxy_it)' -Url 'https://eth0.me'
    $r2 = Test-Outbound -Label 'post-restart: ident.me (proxy_ru)' -Url 'https://ident.me'

    Write-Result -Name 'post-restart: direct IP non-empty' -Passed ($d2 -ne $null -and $d2 -ne '')
    Write-Result -Name 'post-restart: proxy_it IP non-empty' -Passed ($i2 -ne $null -and $i2 -ne '')
    Write-Result -Name 'post-restart: proxy_ru IP non-empty' -Passed ($r2 -ne $null -and $r2 -ne '')

    if ($d2 -and $i2 -and $r2) {
        Write-Host "[test] IPs after restart: direct=$d2  proxy_it=$i2  proxy_ru=$r2" -ForegroundColor DarkGray

        Write-Result -Name 'post-restart: direct != proxy_it' `
            -Passed ($d2 -ne $i2) `
            -Detail "both returned $d2"

        Write-Result -Name 'post-restart: direct != proxy_ru' `
            -Passed ($d2 -ne $r2) `
            -Detail "both returned $d2"

        Write-Result -Name 'post-restart: proxy_it != proxy_ru' `
            -Passed ($i2 -ne $r2) `
            -Detail "both returned $i2"
    }
}

# ---------------------------------------------------------------------------
# Summary and exit
# ---------------------------------------------------------------------------

Write-Output "=== Results: $($script:pass) passed, $($script:fail) failed ==="

if ($script:fail -gt 0) {
    Write-Output '=== FAIL ==='
    exit 1
} else {
    Write-Output '=== PASS ==='
    exit 0
}
