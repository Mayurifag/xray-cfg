#Requires -Version 5.1
. "$PSScriptRoot\common.ps1"

$tasks   = Get-ScheduledTask -TaskName $TaskNameSingbox, $TaskNameGeodata -ErrorAction SilentlyContinue
$procs   = Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue
$adapter = Get-NetAdapter -Name $TunAdapterName -ErrorAction SilentlyContinue

if ($tasks)   { $tasks   | Select-Object TaskName, State                    | Format-Table -AutoSize }
if ($procs)   { $procs   | Select-Object Name, Id, CPU                      | Format-Table -AutoSize }
if ($adapter) { $adapter | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize }
if (-not $tasks -and -not $procs -and -not $adapter) { Write-Host 'Not running.' }
