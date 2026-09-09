#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Address,
    [Parameter(Mandatory)][string]$KnownHostsPath,
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '../../artifacts/ssh/a1625_ram_ed25519'),
    [switch]$RequireUsbDisconnected
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../codex-state/A1625CodexState.psm1') -Force
$parsedAddress = $null
if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -or
    $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    $parsedAddress.ToString() -ne $Address) {
    throw 'Address must be the canonical IPv4 DHCP address of the owned A1625.'
}
function Assert-UsbAbsent {
    # Conservative: another Apple/Linux gadget also prevents a passing result.
    $present = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
        $_.InstanceId -like 'USB\VID_05AC*' -or $_.InstanceId -like 'USB\VID_1D6B*' -or
        $_.FriendlyName -match 'NCM|COM5'
    })
    if ($present.Count) { throw 'A matching USB device is still present; USB-independent acceptance cannot pass.' }
}
if ($RequireUsbDisconnected) { Assert-UsbAbsent }
$arguments = @(Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath)
# Reuse the exact host key already verified via ACM during this RAM boot.
$remote = @'
set -eu
state=/run/a1625-wifi
kill -0 "$(cat "$state/runner.pid")"
kill -0 "$(cat "$state/network.pid")"
kill -0 "$(cat "$state/dhcp.pid")"
test -d /sys/class/net/wlan0
LD_LIBRARY_PATH=/run/a1625-wpa/usr/lib:/run/a1625-wpa/lib /run/a1625-wpa/sbin/wpa_cli -p "$state/control" status | sed -n '/^wpa_state=/p; /^pairwise_cipher=/p; /^group_cipher=/p; /^key_mgmt=/p'
LD_LIBRARY_PATH=/run/a1625-iw/usr/lib /run/a1625-iw/usr/sbin/iw dev wlan0 get power_save
nslookup example.com > "$state/dns-check.log" 2>&1
echo dns_status=0
LD_LIBRARY_PATH=/run/a1625-curl/usr/lib:/run/a1625-curl/lib /run/a1625-curl/usr/bin/curl --interface wlan0 --cacert /etc/ssl/certs/ca-certificates.crt --max-time 20 --fail --silent --show-error --output /dev/null --write-out 'http_status=%{http_code} tls_verify=%{ssl_verify_result}\n' https://example.com
echo wifi_ssh=passed
'@
$result = @(& ssh -F none @arguments -o HostKeyAlias=172.16.42.1 "root@$Address" $remote.Replace("`r`n", "`n"))
if ($LASTEXITCODE -ne 0) { throw 'Wi-Fi acceptance command failed; do not infer success from partial output.' }
foreach ($required in @('wpa_state=COMPLETED', 'pairwise_cipher=CCMP', 'group_cipher=CCMP',
    'key_mgmt=WPA2-PSK', 'Power save: off', 'dns_status=0', 'http_status=200 tls_verify=0', 'wifi_ssh=passed')) {
    if ($required -notin $result) { throw "Missing acceptance result: $required" }
}
if ($RequireUsbDisconnected) { Assert-UsbAbsent }
$result
if ($RequireUsbDisconnected) { 'windows_usb_absent=passed' }
