[CmdletBinding()]
param(
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'),
    [string]$AppleTvAddress = '172.16.42.1',
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\known_hosts_minimal_boot_20260902')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'A1625CodexState.psm1') -Force

$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
Set-A1625StateDirectoryAcl -Path $StateDirectory
$sshArguments = Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath
$plain = $null
$cipher = $null
try {
    $plain = Invoke-A1625SshDownload -SshArguments $sshArguments `
        -AppleTvAddress $AppleTvAddress `
        -RemoteCommand 'set -e; test -s /run/codex-home/auth.json; cat /run/codex-home/auth.json'
    if ($plain.Length -lt 32 -or $plain.Length -gt 1024 * 1024) {
        throw "Unexpected Codex auth size: $($plain.Length) bytes"
    }
    $jsonText = [Text.Encoding]::UTF8.GetString($plain)
    [void]($jsonText | ConvertFrom-Json -ErrorAction Stop)
    $jsonText = $null

    $cipher = [Security.Cryptography.ProtectedData]::Protect(
        $plain,
        (Get-A1625DpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $statePath = Join-Path $StateDirectory 'codex-auth.dpapi'
    Write-A1625AtomicBytes -Path $statePath -Bytes $cipher
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($cipher))
    $manifest = [ordered]@{
        format = 'a1625-codex-auth-dpapi-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        protection = 'DPAPI CurrentUser'
        ciphertextBytes = $cipher.Length
        ciphertextSha256 = $hash
    } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $StateDirectory 'manifest.json') -Value $manifest -Encoding utf8
    Write-Host "Codex authentication state saved with DPAPI: $statePath"
}
finally {
    if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
    if ($cipher) { [Array]::Clear($cipher, 0, $cipher.Length) }
}
