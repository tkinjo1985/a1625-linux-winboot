#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$AppleTvAddress = '172.16.42.1',
    [ValidateRange(5, 120)]
    [int]$ReadyTimeoutSeconds = 30
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

test -x "$state/hold.sh"
test -x /run/run_probe_once
test -f /run/a1625_hold.ko
test -f /lib/firmware/brcm/brcmfmac4350-pcie.bin
test -f /lib/firmware/regulatory.db

if test -e "$state/session-lock"; then
    echo "ERROR: Wi-Fi hardware session already exists"
    exit 20
fi

nohup sh "$state/hold.sh" \
    > "$state/hold.log" 2>&1 < /dev/null &

i=0
while test "$i" -lt __READY_TIMEOUT__; do
    if test -s "$state/runner.pid"; then
        pid="$(cat "$state/runner.pid")"

        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: runner exited"
            cat "$state/hold.log" || true
            exit 21
        fi

        if test -d /sys/class/net/wlan0; then
            echo "wifi_hardware=ready"
            echo "runner_pid=$pid"
            exit 0
        fi
    fi

    i=$((i + 1))
    sleep 1
done

echo "ERROR: wlan0 did not appear"
cat "$state/hold.log" || true
exit 22
'@

$remoteCommand = $remoteCommand.Replace('__READY_TIMEOUT__', [string]$ReadyTimeoutSeconds)

& ssh.exe -F none @SshArguments "root@$AppleTvAddress" $remoteCommand

if ($LASTEXITCODE -ne 0) {
    throw 'Wi-Fi hardware hold failed.'
}

Write-Host ''
Write-Host 'Wi-Fi hardware hold started. Run the verification script before Connect-A1625Wifi.ps1.'
