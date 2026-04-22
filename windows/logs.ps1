#Requires -Version 5.1

Get-Content "$PSScriptRoot\v2rayn\bin\xray\xray-error.log" -Tail 50 -Wait
