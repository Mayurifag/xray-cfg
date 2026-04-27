#Requires -Version 5.1
<#
.SYNOPSIS
    Download fresh geoip.dat and geosite.dat.
.DESCRIPTION
    Saves files to $TargetDir (defaults to $PSScriptRoot\v2rayn\), creating the
    directory if needed. Pass -TargetDir to place geodata next to xray.exe instead.
    Prints downloaded paths and sizes to stdout. Progress and errors go to stderr.
    Exits non-zero on any download failure or if a file ends up empty.
#>
param(
    [string]$TargetDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $TargetDir) { $TargetDir = Join-Path $PSScriptRoot 'v2rayn' }
. (Join-Path $PSScriptRoot '..\shared\geodata_urls.ps1')
$GeoipPath  = Join-Path $TargetDir 'geoip.dat'
$GeositePath = Join-Path $TargetDir 'geosite.dat'

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

$MaxAgeDays  = 1
$now         = Get-Date
$geoipFresh  = (Test-Path $GeoipPath) -and ($now - (Get-Item $GeoipPath).LastWriteTime).TotalDays -lt $MaxAgeDays
$geositeFresh = (Test-Path $GeositePath) -and ($now - (Get-Item $GeositePath).LastWriteTime).TotalDays -lt $MaxAgeDays

if ($geoipFresh -and $geositeFresh) {
    Write-Host "Geodata fresh (< $MaxAgeDays days), skipping download." -ForegroundColor DarkGray
} else {
    if (-not $geoipFresh) {
        Write-Host 'Downloading geoip.dat...' -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $GeoipUrl -OutFile $GeoipPath -UseBasicParsing
    }
    if (-not $geositeFresh) {
        Write-Host 'Downloading geosite.dat...' -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $GeositeUrl -OutFile $GeositePath -UseBasicParsing
    }
}

$GeoipInfo   = Get-Item $GeoipPath
$GeositeInfo = Get-Item $GeositePath

if ($GeoipInfo.Length -eq 0) {
    Write-Error "Error: $GeoipPath is empty or missing"
    exit 1
}

if ($GeositeInfo.Length -eq 0) {
    Write-Error "Error: $GeositePath is empty or missing"
    exit 1
}

Write-Output "$GeoipPath ($($GeoipInfo.Length) bytes)"
Write-Output "$GeositePath ($($GeositeInfo.Length) bytes)"
