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
$statePath = Join-Path $StateDirectory 'codex-auth.dpapi'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Encrypted Codex state was not found: $statePath"
}
$sshArguments = Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath
$cipher = $null
$plain = $null
try {
    $cipher = [IO.File]::ReadAllBytes($statePath)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
        $cipher,
        (Get-A1625DpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    if ($plain.Length -lt 32 -or $plain.Length -gt 1024 * 1024) {
        throw "Unexpected decrypted Codex auth size: $($plain.Length) bytes"
    }
    $jsonText = [Text.Encoding]::UTF8.GetString($plain)
    [void]($jsonText | ConvertFrom-Json -ErrorAction Stop)
    $jsonText = $null

    $remote = 'set -e; umask 077; mkdir -p /run/codex-home; chmod 0700 /run/codex-home; cat > /run/codex-home/auth.json.next; chmod 0600 /run/codex-home/auth.json.next; mv /run/codex-home/auth.json.next /run/codex-home/auth.json; export HOME=/run/codex-home CODEX_HOME=/run/codex-home SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin; /opt/bin/codex login status >/dev/null 2>&1; echo restored_and_verified'
    $status = Invoke-A1625SshUpload -SshArguments $sshArguments `
        -AppleTvAddress $AppleTvAddress -RemoteCommand $remote -Payload $plain
    if ($status -ne 'restored_and_verified') {
        throw "Codex did not confirm ChatGPT authentication: $status"
    }
    Write-Host 'Codex authentication restored from DPAPI state and verified on the Apple TV.'
}
finally {
    if ($plain) { [Array]::Clear($plain, 0, $plain.Length) }
    if ($cipher) { [Array]::Clear($cipher, 0, $cipher.Length) }
}
