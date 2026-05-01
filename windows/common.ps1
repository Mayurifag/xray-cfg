#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for Windows PS1 scripts (sing-box-extended TUN proxy).
    Dot-source this file; do NOT run it directly.
#>

$Script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Script:RuntimeDir = Join-Path $PSScriptRoot 'runtime'
$Script:SingboxDir = Join-Path $RuntimeDir 'bin'
$Script:SingboxExe = Join-Path $SingboxDir 'sing-box.exe'
$Script:SingboxConfig = Join-Path $RuntimeDir 'config.json'
$Script:RuleSetDir = Join-Path $RuntimeDir 'rule-sets'
$Script:GeodataDir = Join-Path $RuntimeDir 'geodata'
$Script:ConfigBase = Join-Path $RepoRoot 'config_base.json'
$Script:SecretsFile = Join-Path $RepoRoot 'secrets.ejson'
$Script:TaskNameSingbox = 'proxies-cfg-singbox'
$Script:TaskNameGeodata = 'proxies-cfg-geodata'
$Script:TunAdapterName = 'singbox_tun'

function Assert-Admin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error 'Run as Administrator.'
        exit 1
    }
}

function Write-Phase {
    param([string]$Script, [string]$Message, [string]$Color = 'DarkGray')
    Write-Host "[$Script] $Message" -ForegroundColor $Color
}

function Get-PythonExe {
    foreach ($name in @('python3', 'python', 'py')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            if ($cmd.Name -eq 'py') {
                # py launcher: prefer Python 3
                return @{ Exe = $cmd.Source; PrefixArgs = @('-3') }
            }
            return @{ Exe = $cmd.Source; PrefixArgs = @() }
        }
    }
    Write-Error 'Python 3 not found. Install Python 3.9+.'
    exit 1
}

function Invoke-Python {
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $py = Get-PythonExe
    return & $py.Exe @($py.PrefixArgs + $Arguments)
}

function Build-SingboxConfig {
    if (-not (Get-Command ejson -ErrorAction SilentlyContinue)) {
        Write-Error 'ejson not found in PATH.'
        exit 1
    }
    # PowerShell splits external stdout into an array of lines; collapse to single string.
    $secrets = (& ejson decrypt $SecretsFile | Out-String).Trim()
    if (-not $secrets) { Write-Error 'ejson decrypt produced empty output.'; exit 1 }
    if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir | Out-Null }
    $pyArgs = @(
        (Join-Path $RepoRoot 'shared\build_config.py'),
        $ConfigBase,
        $secrets,
        $RuleSetDir
    )
    $json = (Invoke-Python -Arguments $pyArgs) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'build_config.py failed.'
        exit 1
    }
    [System.IO.File]::WriteAllText($SingboxConfig, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Restart-Proxy {
    Build-SingboxConfig
    Stop-ScheduledTask -TaskName $TaskNameSingbox -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName $TaskNameSingbox
}

function Format-Domain {
    param([string]$Domain)
    if ($Domain -match '^domain:') { $Domain = $Domain -replace '^domain:', '' }
    $Domain = $Domain -replace '^https?://', ''
    $Domain = ($Domain -split '/')[0]
    return $Domain
}

function Invoke-GitPullIfClean {
    param([string]$Path = $RepoRoot)
    Push-Location $Path
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
    } finally { Pop-Location }
}

function Invoke-GitCommitAndPush {
    param([string]$CommitMessage, [string]$Path = $RepoRoot)
    Push-Location $Path
    try {
        git add config_base.json
        if (git status --porcelain config_base.json) {
            git commit -m $CommitMessage
            git push
            Write-Host 'Changes committed and pushed.'
        }
    } finally { Pop-Location }
}

function Test-Outbound {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
        return $resp.Content.Trim()
    } catch {
        return $null
    }
}
