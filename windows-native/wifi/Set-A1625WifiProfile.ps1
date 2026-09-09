#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'A1625WifiProfile.psm1') -Force
$ssid = Read-Host 'SSID (hidden input)' -AsSecureString
$passphrase = Read-Host 'WPA2-PSK AES passphrase (hidden input)' -AsSecureString
try {
    $profile = New-A1625WifiProfile -Ssid $ssid -Passphrase $passphrase
    $path = Join-Path $env:LOCALAPPDATA 'AppleTvA1625/wifi/japan.wifi.dpapi'
    Save-A1625WifiProfile -Profile $profile -Path $path
    Write-Host 'Japan WPA2-CCMP profile saved with Windows CurrentUser DPAPI. No device changes were made.'
}
finally {
    $ssid.Dispose()
    $passphrase.Dispose()
    $profile = $null
}
