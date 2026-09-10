#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$AppleTvAddress = '172.16.42.1',
    [ValidateRange(20, 500)]
    [int]$KernelLogLines = 160,
    [ValidateRange(20, 500)]
    [int]$HoldLogLines = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$SshKeyPath = Join-Path $RepoRoot 'artifacts\ssh\a1625_ram_ed25519'
$StateModule = Join-Path $RepoRoot 'windows-native\codex-state\A1625CodexState.psm1'

Import-Module $StateModule -Force

$StateDirectory = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
$KnownHosts = Get-ChildItem `
    -LiteralPath $StateDirectory `
    -Filter 'known_hosts_ram_*' `
    -File `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $KnownHosts) {
    throw 'No current-boot known_hosts file found. Run Restore-A1625RamEnvironment.ps1 first.'
}

$SshArguments = @(
    Get-A1625SshArguments `
        -SshKeyPath $SshKeyPath `
        -KnownHostsPath $KnownHosts.FullName
)

$remoteCommand = @'
set -eu

state=/run/a1625-wifi

echo "=== runner ==="
test -s "$state/runner.pid"
pid="$(cat "$state/runner.pid")"
echo "$pid"
kill -0 "$pid"
echo "runner=alive"

echo
echo "=== wlan0 ==="
test -d /sys/class/net/wlan0
ip link show wlan0

echo
echo "=== PCI parent ==="
readlink -f /sys/class/net/wlan0/device

echo
echo "=== hold log ==="
tail -n __HOLD_LINES__ "$state/hold.log"

echo
echo "=== recent kernel log ==="
dmesg | tail -n __KERNEL_LINES__

echo
echo "=== quick fault scan ==="
if dmesg | tail -n __KERNEL_LINES__ | grep -Ei 'DART.*fault|IOMMU.*fault|brcmfmac.*(fail|error)|firmware.*(fail|error)'; then
    echo
    echo "WARNING: suspicious fault/error lines were found above."
else
    echo "No obvious DART/IOMMU/brcmfmac/firmware fault lines found in the recent kernel log."
fi
'@

$remoteCommand = $remoteCommand.Replace('__HOLD_LINES__', [string]$HoldLogLines)
$remoteCommand = $remoteCommand.Replace('__KERNEL_LINES__', [string]$KernelLogLines)

& ssh.exe -F none @SshArguments "root@$AppleTvAddress" $remoteCommand

if ($LASTEXITCODE -ne 0) {
    throw 'Wi-Fi hardware verification failed.'
}

Write-Host ''
Write-Host 'Basic runner/wlan0 checks passed.'
Write-Host 'Review PCI parent, hold.log, and dmesg before running Connect-A1625Wifi.ps1.'
