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
