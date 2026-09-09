#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}$')]
    [string]$Address,

    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\a1625_ram_ed25519'),

    [string]$KnownHostsPath,

    [string]$AddressStatePath = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\last-address.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WifiAddress {
    param(
        [string]$ExplicitAddress,
        [string]$StatePath
    )

    $candidate = $ExplicitAddress

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
            throw @"
No saved Wi-Fi address was found.

Pass the current A1625 Wi-Fi IPv4 address once, for example:

  & .\windows-native\wifi\Enter-A1625WifiShell.ps1 -Address 192.168.1.123

After a successful connection, that address will be saved to:
  $StatePath
"@
        }

        $candidate = (Get-Content -LiteralPath $StatePath -Raw).Trim()
    }

    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($candidate, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        $parsed.ToString() -ne $candidate) {
        throw "Invalid canonical IPv4 address: $candidate"
    }

    return $candidate
}

function Resolve-KnownHostsPath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "Known-hosts file was not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).ProviderPath
    }

    $stateDirectory = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
    $latest = Get-ChildItem -LiteralPath $stateDirectory -Filter 'known_hosts_ram_*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No per-boot known_hosts file was found. Run Restore-A1625RamEnvironment.ps1 first.'
    }

    return $latest.FullName
}

if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    throw 'ssh.exe was not found in PATH.'
}

if (-not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
    throw "SSH private key was not found: $SshKeyPath"
}

$wifiAddress = Resolve-WifiAddress -ExplicitAddress $Address -StatePath $AddressStatePath
$knownHosts = Resolve-KnownHostsPath -ExplicitPath $KnownHostsPath
$resolvedKey = (Resolve-Path -LiteralPath $SshKeyPath).ProviderPath

$sshArguments = @(
    '-tt',
    '-i', $resolvedKey,
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=5',
    '-o', 'ServerAliveInterval=5',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', ('UserKnownHostsFile=' + $knownHosts),
    '-o', 'HostKeyAlias=172.16.42.1'
)

Write-Host "Opening Wi-Fi PTY shell on root@$wifiAddress."
Write-Host "Host key alias: 172.16.42.1"
Write-Host "Known hosts: $knownHosts"
Write-Host "Type 'codex-ram' to start Codex; use 'exit' to disconnect."

& ssh.exe -F none @sshArguments "root@$wifiAddress" `
    'export TERM=xterm-256color HOME=/run/codex-home CODEX_HOME=/run/codex-home PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin; cd /run/work; exec /bin/sh -i'

$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "A1625 Wi-Fi interactive SSH session ended with exit code $exitCode."
}

# Save only after a successful SSH session. This stores an IP address, not a credential.
$stateDirectory = Split-Path -Parent $AddressStatePath
New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($AddressStatePath),
    $wifiAddress + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

Write-Host "Saved Wi-Fi address: $wifiAddress"
