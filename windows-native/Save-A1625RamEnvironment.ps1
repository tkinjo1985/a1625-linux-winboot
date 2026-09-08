#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('minimal', 'development')][string]$DevelopmentProfile = 'development',
    [string]$PayloadPath = (Join-Path $PSScriptRoot '..\artifacts\hoolock\payload\m1n1-linux-a1625-minimal-ssh.bin'),
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath,
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($KnownHostsPath)) {
    $knownHostsDirectory = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
    if (Test-Path -LiteralPath $knownHostsDirectory -PathType Container) {
        $KnownHostsPath = Get-ChildItem -LiteralPath $knownHostsDirectory -Filter 'known_hosts_ram_*' -File |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if ([string]::IsNullOrWhiteSpace($KnownHostsPath)) {
        throw 'No RAM-boot known_hosts file was found. Establish a verified RAM SSH connection first, or pass -KnownHostsPath.'
    }
}
foreach ($path in @($PayloadPath, $SshKeyPath, $KnownHostsPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file was not found: $path"
    }
}

Write-Host "Using verified-hosts file: $KnownHostsPath"
$layer = & (Join-Path $PSScriptRoot 'development-tools\Install-A1625DevelopmentTools.ps1') -Profile $DevelopmentProfile -PrepareOnly
if ($null -eq $layer -or [string]::IsNullOrWhiteSpace($layer.BundlePath) -or
    -not (Test-Path -LiteralPath $layer.BundlePath -PathType Leaf)) {
    throw 'Development tools preparation did not return an existing bundle.'
}

$saveParameters = @{
    PayloadPath = $PayloadPath
    RuntimePath = $layer.BundlePath
    SshKeyPath = $SshKeyPath
    KnownHostsPath = $KnownHostsPath
    StateDirectory = $StateDirectory
}
& (Join-Path $PSScriptRoot 'ram-state\Save-A1625RamState.ps1') @saveParameters
