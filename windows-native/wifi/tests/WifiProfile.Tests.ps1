#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../A1625WifiProfile.psm1') -Force
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Secret($Value) { ConvertTo-SecureString $Value -AsPlainText -Force }
# Public WPA PSK test vector, not a user's credentials.
$profile = New-A1625WifiProfile -Ssid (Secret 'IEEE') -Passphrase (Secret 'password')
Assert ($profile.pskHex -eq 'f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e') 'PBKDF2 vector mismatch'
$config = [Text.Encoding]::UTF8.GetString((ConvertTo-A1625WpaConfig $profile))
Assert ($config.Contains('ssid=49454545')) 'SSID is not hex encoded'
Assert ($config.Contains('country=JP') -and $config.Contains('proto=RSN') -and $config.Contains('group=CCMP')) 'Wrong authentication settings'
Assert (-not $config.Contains('password')) 'Passphrase leaked into config'
foreach ($bad in @('', 'short', (('a' * 63) + 'b'), "password`n")) {
    $threw = $false
    try { $null = New-A1625WifiProfile -Ssid (Secret 'IEEE') -Passphrase (Secret $bad) } catch { $threw = $true }
    Assert $threw 'Invalid passphrase accepted'
}
$threw = $false
try { $null = New-A1625WifiProfile -Ssid (Secret ('あ' * 11)) -Passphrase (Secret 'password') } catch { $threw = $true }
Assert $threw 'Overlength UTF-8 SSID accepted'
$profile.country = 'US'
$threw = $false
try { $null = ConvertTo-A1625WpaConfig $profile } catch { $threw = $true }
Assert $threw 'Wrong country accepted'
$profile.country = 'JP'
$testDirectory = Join-Path $PSScriptRoot ('../../../artifacts/wifi-profile-tests/' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $testDirectory 'test.wifi.dpapi'
Save-A1625WifiProfile $profile $path
$restored = Read-A1625WifiProfile $path
Assert ($restored.pskHex -eq $profile.pskHex -and $restored.ssidHex -eq $profile.ssidHex) 'DPAPI round trip failed'
$cipher = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($path))
Assert (-not [Text.Encoding]::UTF8.GetString($cipher).Contains($profile.pskHex)) 'PSK stored unencrypted'
$cipher[0] = $cipher[0] -bxor 255
[IO.File]::WriteAllBytes([IO.Path]::GetFullPath($path), $cipher)
$threw = $false
try { $null = Read-A1625WifiProfile $path } catch { $threw = $true }
Assert $threw 'Corrupted DPAPI data accepted'
Write-Host 'PASS: PSK vector, validation, config encoding, DPAPI round trip and tamper rejection'
