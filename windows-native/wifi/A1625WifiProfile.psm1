Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../codex-state/A1625CodexState.psm1')

function New-A1625WifiProfile {
    param(
        [Parameter(Mandatory)][Security.SecureString]$Ssid,
        [Parameter(Mandatory)][Security.SecureString]$Passphrase
    )
    # Secret strings exist only in process memory, never in argv or a temp file.
    $ssidText = [Net.NetworkCredential]::new('', $Ssid).Password
    $passText = [Net.NetworkCredential]::new('', $Passphrase).Password
    $ssidBytes = [Text.Encoding]::UTF8.GetBytes($ssidText)
    $passBytes = $null
    $pskBytes = $null
    try {
        if ($ssidBytes.Length -lt 1 -or $ssidBytes.Length -gt 32) {
            throw 'SSID must encode to 1-32 UTF-8 bytes.'
        }
        if ($passText -cnotmatch '\A[\x20-\x7e]{8,63}\z') {
            throw 'WPA2 passphrase must contain 8-63 printable ASCII characters.'
        }
        $passBytes = [Text.Encoding]::ASCII.GetBytes($passText)
        $pskBytes = [Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2(
            $passBytes, $ssidBytes, 4096, [Security.Cryptography.HashAlgorithmName]::SHA1, 32)
        [pscustomobject]@{
            schema = 1
            target = 'AppleTV5,3/J42d/T7000'
            country = 'JP'
            authentication = 'WPA2-PSK-CCMP'
            ssidHex = [Convert]::ToHexString($ssidBytes).ToLowerInvariant()
            pskHex = [Convert]::ToHexString($pskBytes).ToLowerInvariant()
        }
    }
    finally {
        [Array]::Clear($ssidBytes, 0, $ssidBytes.Length)
        if ($passBytes) { [Array]::Clear($passBytes, 0, $passBytes.Length) }
        if ($pskBytes) { [Array]::Clear($pskBytes, 0, $pskBytes.Length) }
        $ssidText = $null
        $passText = $null
    }
}

function Assert-A1625WifiProfile {
    param([Parameter(Mandatory)]$Profile)
    if ($Profile.schema -ne 1 -or $Profile.target -cne 'AppleTV5,3/J42d/T7000' -or
        $Profile.country -cne 'JP' -or $Profile.authentication -cne 'WPA2-PSK-CCMP' -or
        $Profile.ssidHex -cnotmatch '\A(?:[0-9a-f]{2}){1,32}\z' -or
        $Profile.pskHex -cnotmatch '\A[0-9a-f]{64}\z') {
        throw 'Invalid A1625 Japan WPA2-CCMP profile.'
    }
}

function Save-A1625WifiProfile {
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$Path)
    Assert-A1625WifiProfile $Profile
    if (-not $IsWindows) { throw 'Wi-Fi profiles require Windows CurrentUser DPAPI.' }
    $absolute = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not $absolute.EndsWith('.wifi.dpapi')) { throw 'Use a .wifi.dpapi file name.' }
    $directory = [IO.Path]::GetDirectoryName($absolute)
    Set-A1625StateDirectoryAcl -Path $directory
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Profile | ConvertTo-Json -Compress))
    try {
        $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        Write-A1625AtomicBytes -Path $absolute -Bytes $encrypted
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Read-A1625WifiProfile {
    param([Parameter(Mandatory)][string]$Path)
    $absolute = (Resolve-Path -LiteralPath $Path).ProviderPath
    if ((Get-Item -LiteralPath $absolute).Length -gt 16384) { throw 'Wi-Fi profile is too large.' }
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($absolute),
        $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        $profile = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        Assert-A1625WifiProfile $profile
        $profile
    }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function ConvertTo-A1625WpaConfig {
    param([Parameter(Mandatory)]$Profile)
    Assert-A1625WifiProfile $Profile
    # Return secret bytes only to a caller which will pipe them through SSH stdin.
    $config = @"
country=JP
ctrl_interface=/run/a1625-wifi/control
update_config=0
network={
    ssid=$($Profile.ssidHex)
    psk=$($Profile.pskHex)
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    group=CCMP
}
"@
    ,([Text.Encoding]::UTF8.GetBytes(($config -replace "`r`n", "`n") + "`n"))
}

Export-ModuleMember -Function New-A1625WifiProfile, Save-A1625WifiProfile,
    Read-A1625WifiProfile, ConvertTo-A1625WpaConfig
