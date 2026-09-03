#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{16}$')]
    [string]$ExpectedEcid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateRoot = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
$configPath = Join-Path $stateRoot 'device.json'
$nextPath = "$configPath.next"

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
[ordered]@{
    schemaVersion = 1
    target = 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000'
    expectedEcid = $ExpectedEcid.ToUpperInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath $nextPath -Encoding utf8
Move-Item -LiteralPath $nextPath -Destination $configPath -Force

Write-Host "Saved the owned A1625 identity outside the repository: $configPath"
Write-Host 'The ECID is a device identifier, not a credential, but this file should remain private.'
