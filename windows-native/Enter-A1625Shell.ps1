[CmdletBinding()]
param(
    [string]$AppleTvAddress = '172.16.42.1',
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $KnownHostsPath) {
    $stateDirectory = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
    $latest = Get-ChildItem -LiteralPath $stateDirectory -Filter 'known_hosts_ram_*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw 'No per-boot known_hosts file was found. Run Restore-A1625RamEnvironment.ps1 first.'
    }
    $KnownHostsPath = $latest.FullName
}

foreach ($path in $SshKeyPath, $KnownHostsPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required SSH file was not found: $path"
    }
}

$sshArguments = @(
    '-tt',
    '-i', [IO.Path]::GetFullPath($SshKeyPath),
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', ('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath))
)

Write-Host "Opening PTY shell on root@$AppleTvAddress. Type 'codex' to start Codex; use 'exit' to disconnect."
& ssh.exe @sshArguments "root@$AppleTvAddress" 'export TERM=xterm-256color HOME=/run/codex-home PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin; cd /run/work; exec /bin/sh -i'
if ($LASTEXITCODE -ne 0) {
    throw "A1625 interactive SSH session ended with exit code $LASTEXITCODE."
}
