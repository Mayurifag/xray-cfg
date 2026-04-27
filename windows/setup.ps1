#Requires -Version 5.1
#Requires -RunAsAdministrator
param(
    [switch]$Boot  # Set when invoked by Scheduled Task; adds pre-flight delay + internet check
)
. "$PSScriptRoot\common.ps1"
. (Join-Path $PSScriptRoot '..\shared\test_urls.ps1')
<#
.SYNOPSIS
    Set up xray + sing-box TUN proxy on Windows using v2rayN binaries.
.DESCRIPTION
    Downloads v2rayN, extracts xray.exe + sing-box.exe + wintun.dll,
    places configs and geodata, starts both as hidden background processes, and
    registers a Scheduled Task for reboot persistence. Idempotent: safe to re-run.

    Progress to stderr (Write-Host). Results and status to stdout (Write-Output).
    Exits 1 with a phase-named error on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Phase 0: Privilege check
# ---------------------------------------------------------------------------
Assert-Admin

Write-Host '[setup] Starting xray+sing-box proxy setup...' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Phase 1: Path variables
# ---------------------------------------------------------------------------
$SetupScript   = $PSCommandPath
$V2RayNDir     = Join-Path $PSScriptRoot 'v2rayn'
$XrayDir       = Join-Path $V2RayNDir    'bin\xray'
$XrayExe       = Join-Path $XrayDir      'xray.exe'
$SingBoxExe    = Join-Path $V2RayNDir    'bin\sing_box\sing-box.exe'
$XrayConfig    = Join-Path $XrayDir      'config.json'
$SingBoxConfig = Join-Path $V2RayNDir    'singbox-tun.json'
$PidFile       = Join-Path $V2RayNDir    'proxy.pid'

$V2rayNVersion = '7.20.4'
$ZipUrl  = "https://github.com/2dust/v2rayN/releases/download/$V2rayNVersion/v2rayN-windows-64.zip"
$ZipPath = Join-Path $V2RayNDir 'v2rayN-windows-64.zip'

# Start transcript early so every phase (including boot failures) is captured
if (-not (Test-Path $V2RayNDir)) { New-Item -ItemType Directory -Path $V2RayNDir | Out-Null }
Start-Transcript -Path (Join-Path $V2RayNDir 'setup.log') -Append | Out-Null

if ($Boot) {
    Write-Host '[setup] Boot mode: sleeping 15s for network stack...' -ForegroundColor DarkGray
    Start-Sleep -Seconds 15
    Write-Host '[setup] Waiting for internet (up to 60s)...' -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds(60)
    $online = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            $online = $true; break
        }
        Start-Sleep -Seconds 3
    }
    if ($online) {
        Write-Host '[setup] Internet OK.' -ForegroundColor DarkGray
    } else {
        Write-Host '[setup] WARNING: internet not reachable after 60s, proceeding anyway' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Phase 2: Download + extract (idempotent - skip if xray.exe already present)
# ---------------------------------------------------------------------------
Write-Phase 'setup' 'Phase: download+extract'

if (Test-Path $XrayExe) {
    Write-Host "[setup] xray.exe already present at $XrayExe - skipping download." -ForegroundColor DarkGray
} else {
    if (-not (Test-Path $V2RayNDir)) {
        New-Item -ItemType Directory -Path $V2RayNDir | Out-Null
    }

    $zipValid = (Test-Path $ZipPath) -and (Get-Item $ZipPath).Length -gt 100MB
    if ($zipValid) {
        Write-Host "[setup] Using cached zip: $ZipPath ($((Get-Item $ZipPath).Length) bytes)" -ForegroundColor DarkGray
    } else {
        Write-Host "[setup] Downloading v2rayN $V2rayNVersion from GitHub..." -ForegroundColor DarkGray
        try {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
        } catch {
            Write-Error "[setup] PHASE FAILED: download - $_"
            exit 1
        }

        if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -eq 0) {
            Write-Error '[setup] PHASE FAILED: download - zip is missing or empty'
            exit 1
        }
        Write-Host "[setup] Download complete: $ZipPath ($((Get-Item $ZipPath).Length) bytes)" -ForegroundColor DarkGray
    }

    Write-Host "[setup] Extracting zip to $V2RayNDir..." -ForegroundColor DarkGray
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $V2RayNDir -Force
    } catch {
        Write-Error "[setup] PHASE FAILED: extract - $_"
        exit 1
    }

    # Flatten nested top-level directory if present (zip contains v2rayN-windows-64/ folder)
    $nestedDir = Join-Path $V2RayNDir 'v2rayN-windows-64'
    if (Test-Path (Join-Path $nestedDir 'bin\xray\xray.exe')) {
        Write-Host '[setup] Flattening nested v2rayN-windows-64/ directory...' -ForegroundColor DarkGray
        Get-ChildItem $nestedDir | Move-Item -Destination $V2RayNDir -Force
        Remove-Item $nestedDir -Recurse -Force
    }

    if (-not (Test-Path $XrayExe)) {
        Write-Error "[setup] PHASE FAILED: extract - xray.exe not found at $XrayExe after extraction"
        exit 1
    }
    if (-not (Test-Path $SingBoxExe)) {
        Write-Error "[setup] PHASE FAILED: extract - sing-box.exe not found at $SingBoxExe after extraction"
        exit 1
    }
    Write-Host '[setup] Extraction complete.' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Phase 3: Config + geodata placement
# ---------------------------------------------------------------------------
Write-Phase 'setup' 'Phase: config+geodata'

try {
    & "$PSScriptRoot\update_geodata.ps1" -TargetDir $XrayDir
} catch {
    Write-Error "[setup] PHASE FAILED: geodata - $_"
    exit 1
}

# Generate xray routing config from config.json via three mechanical transforms
$srcPath = (Join-Path (Join-Path $PSScriptRoot '..') 'config.json')
$secretsPath = (Join-Path (Join-Path $PSScriptRoot '..') 'secrets.ejson')
Write-Host "[setup] Decrypting secrets from $secretsPath..." -ForegroundColor DarkGray
try {
    if (-not (Get-Command ejson -ErrorAction SilentlyContinue)) {
        throw 'ejson not found in PATH. See README.md.'
    }
    $secrets = (& ejson decrypt $secretsPath) | ConvertFrom-Json
} catch {
    Write-Error "[setup] PHASE FAILED: secrets - $_"
    exit 1
}

Write-Host "[setup] Generating xray config from $srcPath..." -ForegroundColor DarkGray
try {
    $raw = Get-Content $srcPath -Raw
    $raw = $raw.Replace('PLACEHOLDER_PROXY_RU_HOST',       $secrets.proxy_ru.host)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_RU_UUID',       $secrets.proxy_ru.uuid)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_RU_SHORT_ID',   $secrets.proxy_ru.short_id)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_RU_PUBLIC_KEY', $secrets.proxy_ru.public_key)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_IT_HOST',       $secrets.proxy_it.host)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_IT_UUID',       $secrets.proxy_it.uuid)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_IT_SHORT_ID',   $secrets.proxy_it.short_id)
    $raw = $raw.Replace('PLACEHOLDER_PROXY_IT_PUBLIC_KEY', $secrets.proxy_it.public_key)
    $srcConfig = $raw | ConvertFrom-Json
} catch {
    Write-Error "[setup] PHASE FAILED: config+geodata - failed to read/parse config.json: $_"
    exit 1
}

# Transform 1: replace inbounds with a single SOCKS inbound for sing-box handoff
$srcConfig.inbounds = @(
    [pscustomobject]@{
        tag      = 'socks-in'
        port     = 10808
        listen   = '127.0.0.1'
        protocol = 'socks'
        settings = [pscustomobject]@{ auth = 'noauth'; udp = $true }
        sniffing = [pscustomobject]@{
            enabled     = $true
            routeOnly   = $true
            destOverride = @('http', 'tls', 'quic')
        }
    }
)

# Transform 2: strip mark from every sockopt; drop empty sockopt/streamSettings
foreach ($ob in $srcConfig.outbounds) { Remove-SockoptMark -Outbound $ob }

# Transform 3: drop the port-53 routing rule (has inboundTag; Windows uses SOCKS, not TUN)
$srcConfig.routing.rules = $srcConfig.routing.rules |
    Where-Object { -not $_.PSObject.Properties['inboundTag'] }

# Transform 4: add error log file path (Windows-only; Linux logs to stdout via systemd)
$srcConfig.log | Add-Member -NotePropertyName 'error' -NotePropertyValue (Join-Path $XrayDir 'xray-error.log') -Force

$json = $srcConfig | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($XrayConfig, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "[setup] Generated xray config -> $XrayConfig" -ForegroundColor DarkGray

# Generate sing-box TUN config from shared base + Windows-specific transforms.
# shared/singbox-tun.json is the macOS variant (no interface_name, bare process names).
# Windows needs:
#   1. inbounds[0].interface_name = "singbox_tun"  (macOS lets sing-box auto-pick utunN)
#   2. .exe suffix on every entry of route.rules[*].process_name (macOS uses bare names)
$SharedSingboxPath = Join-Path (Join-Path $PSScriptRoot '..') 'shared\singbox-tun.json'
$SingboxCfg = Get-Content $SharedSingboxPath -Raw | ConvertFrom-Json
$SingboxCfg.inbounds[0] | Add-Member -NotePropertyName 'interface_name' -NotePropertyValue 'singbox_tun' -Force
foreach ($rule in $SingboxCfg.route.rules) {
    if ($rule.PSObject.Properties.Name -contains 'process_name') {
        $rule.process_name = @($rule.process_name | ForEach-Object { "$_.exe" })
    }
}
$SingboxJson = $SingboxCfg | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($SingBoxConfig, $SingboxJson, (New-Object System.Text.UTF8Encoding $false))
Write-Host "[setup] Generated singbox-tun.json (from shared/) -> $SingBoxConfig" -ForegroundColor DarkGray

# Validate xray config
Write-Host '[setup] Validating xray config...' -ForegroundColor DarkGray
try {
    & $XrayExe run -test -c $XrayConfig
} catch {
    Write-Error "[setup] PHASE FAILED: config-validate - xray run -test threw: $_"
    exit 1
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "[setup] PHASE FAILED: config-validate - xray run -test exited $LASTEXITCODE"
    exit 1
}
Write-Host '[setup] xray config valid.' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Phase 4: Start processes (idempotent - kill existing first)
# ---------------------------------------------------------------------------
Write-Phase 'setup' 'Phase: start-processes'

$existing = Get-Process -Name 'xray','sing-box' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[setup] Stopping existing xray/sing-box processes: $($existing.Id -join ', ')" -ForegroundColor DarkGray
    $existing | Stop-Process -Force
    Start-Sleep -Seconds 1
}

Write-Host '[setup] Starting xray.exe (hidden)...' -ForegroundColor DarkGray
$xrayProc = Start-Process -FilePath $XrayExe `
    -ArgumentList 'run', '-c', $XrayConfig `
    -WindowStyle Hidden `
    -PassThru

Write-Phase 'setup' "xray.exe started with PID $($xrayProc.Id)."

Write-Host '[setup] Starting sing-box.exe (hidden)...' -ForegroundColor DarkGray
$singboxProc = Start-Process -FilePath $SingBoxExe `
    -ArgumentList 'run', '-c', $SingBoxConfig `
    -WorkingDirectory $V2RayNDir `
    -WindowStyle Hidden `
    -PassThru

Write-Host "[setup] sing-box.exe started with PID $($singboxProc.Id)." -ForegroundColor DarkGray

# Save PIDs for teardown
"$($xrayProc.Id)`n$($singboxProc.Id)" | Set-Content $PidFile
Write-Host "[setup] PIDs saved to $PidFile" -ForegroundColor DarkGray

# Register Scheduled Task for reboot persistence (hidden = no window at logon)
Write-Host '[setup] Registering Scheduled Task xray-proxy...' -ForegroundColor DarkGray
$action    = New-ScheduledTaskAction -Execute 'pwsh.exe' `
                 -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SetupScript`" -Boot"
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$settings  = New-ScheduledTaskSettingsSet -Hidden
$principal = New-ScheduledTaskPrincipal `
                 -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
                 -RunLevel Highest
Register-ScheduledTask -TaskName 'xray-proxy' -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Host '[setup] Scheduled Task xray-proxy registered.' -ForegroundColor DarkGray

$geodataAction  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
                      -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\update_geodata.ps1`" -TargetDir `"$XrayDir`""
$geodataTrigger = New-ScheduledTaskTrigger -Daily -At '03:00'
Register-ScheduledTask -TaskName 'xray-geodata' -Action $geodataAction -Trigger $geodataTrigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Host '[setup] Scheduled Task xray-geodata registered (daily 03:00).' -ForegroundColor DarkGray

$rotateAction  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
                     -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\rotate_logs.ps1`""
$rotateTrigger = New-ScheduledTaskTrigger -Daily -At '03:30'
Register-ScheduledTask -TaskName 'xray-logrotate' -Action $rotateAction -Trigger $rotateTrigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Host '[setup] Scheduled Task xray-logrotate registered (daily 03:30).' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Phase 5: Verification - wait up to 15s for TUN adapter
# ---------------------------------------------------------------------------
Write-Phase 'setup' 'Phase: verify-tun-adapter'

$adapter = $null
$waited  = 0
while ($waited -lt 15) {
    $adapter = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -like '*WinTun*' -or $_.Name -like '*singbox*'
    }
    if ($adapter) { break }
    Start-Sleep -Seconds 1
    $waited++
}

if ($adapter) {
    # Wait for sing-box to install the default route via the TUN (appears after adapter is Up).
    # Flush DNS once the route is confirmed so pre-proxy cached entries don't bypass routing.
    $routeFound = $false
    for ($i = 0; $i -lt 50; $i++) {
        $route = Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix '0.0.0.0/0' `
                     -ErrorAction SilentlyContinue
        if ($route) { $routeFound = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $routeFound) {
        Write-Host '[setup] WARNING: default route via TUN not seen after 10s' -ForegroundColor Yellow
    }
    ipconfig /flushdns 2>&1 | Out-Null
    # Flush Windows IP destination cache so new connections use the updated route table
    netsh interface ip delete destinationcache 2>&1 | Out-Null

    # Prefetch: warm DNS cache + VLESS connections so first user request is fast.
    Write-Phase 'setup' 'Phase: prefetch'
    foreach ($url in $AllTestUrls) {
        try {
            $null = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing
            Write-Host "[setup] prefetch ok: $url" -ForegroundColor DarkGray
        } catch {
            Write-Host "[setup] prefetch warn: $url - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Output 'Setup complete.'
    Write-Output "  TUN adapter : $($adapter.Name) [$($adapter.InterfaceDescription)] - $($adapter.Status)"
    Write-Output "  xray PID    : $($xrayProc.Id)"
    Write-Output "  sing-box PID: $($singboxProc.Id)"
} else {
    # Emit full diagnostics before failing so a future agent can inspect the state
    Write-Host '[setup] TUN adapter not found. Diagnostic dump:' -ForegroundColor Red
    Write-Host '--- all network adapters ---' -ForegroundColor Yellow
    Get-NetAdapter | Select-Object Name, InterfaceDescription, Status | Format-Table | Out-String | Write-Host
    Write-Host '--- xray/sing-box processes ---' -ForegroundColor Yellow
    Get-Process -Name 'xray','sing-box' -ErrorAction SilentlyContinue |
        Select-Object Name, Id, CPU, WorkingSet | Format-Table | Out-String | Write-Host
    Write-Host '--- proxy.pid ---' -ForegroundColor Yellow
    Get-Content $PidFile -ErrorAction SilentlyContinue | Write-Host
    Write-Error '[setup] PHASE FAILED: verify-tun-adapter - TUN adapter did not appear within 15 seconds'
    exit 1
}
