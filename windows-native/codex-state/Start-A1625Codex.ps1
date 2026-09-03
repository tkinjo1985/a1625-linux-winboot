[CmdletBinding()]
param(
    [string]$WorkDirectory = '/run/work',
    [string]$AppleTvAddress = '172.16.42.1',
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\known_hosts_minimal_boot_20260902')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($path in $SshKeyPath, $KnownHostsPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required SSH file was not found: $path"
    }
}
if ($WorkDirectory -notmatch '^/run/[A-Za-z0-9._/-]+$' -or $WorkDirectory.Contains('..')) {
    throw 'WorkDirectory must be a simple absolute path below /run without parent traversal.'
}

$sshArguments = @(
    '-tt',
    '-i', [IO.Path]::GetFullPath($SshKeyPath),
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', ('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath))
)
& ssh.exe @sshArguments "root@$AppleTvAddress" "mkdir -p $WorkDirectory && exec codex -C $WorkDirectory"
$sshExitCode = $LASTEXITCODE
if ($sshExitCode -ne 0) {
    throw "Interactive Codex session ended with ssh exit code $sshExitCode; state was not saved."
}

& (Join-Path $PSScriptRoot 'Save-A1625CodexState.ps1') `
    -AppleTvAddress $AppleTvAddress `
    -SshKeyPath $SshKeyPath `
    -KnownHostsPath $KnownHostsPath
Write-Host 'Interactive session ended and the latest Codex authentication state was saved.'
