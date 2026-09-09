#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '../../artifacts/ssh/a1625_ram_ed25519'),
    [Parameter(Mandatory)][string]$KnownHostsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../codex-state/A1625CodexState.psm1') -Force
$arguments = @(Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath)
# Never inspect internal flash. Only read the explicitly labelled RAM-backed ADT.
$command = @'
set -eu
[ "$(tr -d '\000' </proc/device-tree/model)" = 'Apple TV HD' ]
tr '\000' '\n' </proc/device-tree/compatible | grep -qx 'apple,j42d'
tr '\000' '\n' </proc/device-tree/compatible | grep -qx 'apple,t7000'
found=
for entry in /sys/class/mtd/mtd*; do
    [ -f "$entry/name" ] || continue
    [ "$(cat "$entry/name")" = adt ] || continue
    [ "$(cat "$entry/type")" = ram ] || exit 20
    size=$(cat "$entry/size")
    [ "$size" -gt 0 ] && [ "$size" -le 16777216 ] || exit 21
    [ -z "$found" ] || exit 22
    found=${entry##*/}
done
[ -n "$found" ] || exit 23
cat "/dev/${found}ro"
'@
[byte[]]$bytes = Invoke-A1625SshDownload -SshArguments $arguments -AppleTvAddress '172.16.42.1' `
    -RemoteCommand $command -TimeoutSeconds 30 -MaxBytes 16777216
$directory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../artifacts/wifi-research'))
Set-A1625StateDirectoryAcl -Path $directory
$path = Join-Path $directory 'a1625.adt.bin'
if (Test-Path -LiteralPath $path) { throw 'ADT capture already exists; preserve or move it before another capture.' }
[IO.File]::WriteAllBytes($path, $bytes)
Write-Host "Captured RAM ADT ($($bytes.Length) bytes) to ignored private file: $path"
Write-Host 'Inspect with: python windows-native/wifi/inspect_adt.py artifacts/wifi-research/a1625.adt.bin'
