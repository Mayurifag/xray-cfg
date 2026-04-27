#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for Windows PS1 scripts (Assert-Admin, Write-Phase).
    Dot-source this file; do NOT run it directly.
    Callers own Set-StrictMode and $ErrorActionPreference.
#>

function Assert-Admin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error 'This script must be run as Administrator. Re-run from an elevated prompt.'
        exit 1
    }
}

function Write-Phase {
    param(
        [string]$Script,
        [string]$Message,
        [string]$Color = 'DarkGray'
    )
    Write-Host "[$Script] $Message" -ForegroundColor $Color
}

function Invoke-GitPullIfClean {
    param([string]$RepoRoot)
    Push-Location $RepoRoot
    try {
        $branch  = git rev-parse --abbrev-ref HEAD 2>$null
        $default = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($default) { $default = $default -replace 'refs/remotes/origin/', '' }
        if ($branch -and $default -and $branch -eq $default) {
            $unpushed = git log "origin/${branch}..HEAD" --oneline 2>$null
            if (-not $unpushed) {
                Write-Host 'Pulling latest changes...'
                git pull --ff-only
            }
        }
    } finally {
        Pop-Location
    }
}

function Remove-SockoptMark {
    param([Parameter(Mandatory)]$Outbound)
    if ($null -eq $Outbound.streamSettings -or $null -eq $Outbound.streamSettings.sockopt) { return }
    $Outbound.streamSettings.sockopt.PSObject.Properties.Remove('mark')
    if (@($Outbound.streamSettings.sockopt.PSObject.Properties).Count -eq 0) {
        $Outbound.streamSettings.PSObject.Properties.Remove('sockopt')
    }
    if (@($Outbound.streamSettings.PSObject.Properties).Count -eq 0) {
        $Outbound.PSObject.Properties.Remove('streamSettings')
    }
}

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
        return $resp.Content.Trim()
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

function Format-Domain {
    param([string]$Domain)
    $prefix = 'domain:'
    if ($Domain -match '^geosite:' -or $Domain -match '^geoip:') {
        return $Domain
    }
    if ($Domain -match '^domain:') {
        $Domain = $Domain -replace '^domain:', ''
    }
    $Domain = $Domain -replace '^https?://', ''
    $Domain = ($Domain -split '/')[0]
    return "${prefix}${Domain}"
}

function Invoke-GitCommitAndPush {
    param([string]$RepoRoot, [string]$CommitMessage)
    Push-Location $RepoRoot
    try {
        git add config.json
        if (git status --porcelain config.json) {
            git commit -m $CommitMessage
            git push
            Write-Host 'Changes committed and pushed.'
        }
    } finally {
        Pop-Location
    }
}
