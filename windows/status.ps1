#Requires -Version 5.1

$tasks = Get-ScheduledTask -TaskName xray-proxy,xray-geodata -ErrorAction SilentlyContinue
$procs = Get-Process xray,sing-box -ErrorAction SilentlyContinue

if ($tasks) { $tasks | Select-Object TaskName,State | Format-Table -AutoSize }
if ($procs) { $procs | Select-Object Name,Id,CPU | Format-Table -AutoSize }
if (-not $tasks -and -not $procs) { Write-Host 'Not running.' }
