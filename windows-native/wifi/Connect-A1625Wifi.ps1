#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$AppleTvUsbAddress = '172.16.42.1',
    [string]$WifiProfilePath = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\japan.wifi.dpapi'),
    [string]$SshKeyPath,
    [string]$KnownHostsPath,
    [ValidateRange(10, 300)]
    [int]$TimeoutSeconds = 90,
    [switch]$EnterShell
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $SshKeyPath) {
    $SshKeyPath = Join-Path $repoRoot 'artifacts\ssh\a1625_ram_ed25519'
}

$wifiModule = Join-Path $PSScriptRoot 'A1625WifiProfile.psm1'
$stateModule = Join-Path $PSScriptRoot '..\codex-state\A1625CodexState.psm1'
$networkScript = Join-Path $PSScriptRoot 'network-session.sh'
$dhcpScript = Join-Path $PSScriptRoot 'wifi-dhcp.sh'
$wpaArchive = Join-Path $repoRoot 'artifacts\wifi-userland\reproduced\wpa-runtime.tar'
$iwArchive = Join-Path $repoRoot 'artifacts\wifi-userland\reproduced\iw-runtime.tar'

Import-Module $stateModule -Force
Import-Module $wifiModule -Force

function Resolve-CurrentKnownHosts {
    if ($KnownHostsPath) {
        return (Resolve-Path -LiteralPath $KnownHostsPath).ProviderPath
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

function Assert-LocalFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required local file was not found: $Path"
    }
}

function Invoke-UsbSsh {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$AllowFailure
    )

    $output = @(& ssh.exe -F none @script:UsbSshArguments "root@$AppleTvUsbAddress" $Command)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "USB SSH command failed with exit code $exitCode."
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Test-Remote {
    param([Parameter(Mandatory)][string]$Command)
    $result = Invoke-UsbSsh -Command $Command -AllowFailure
    return $result.ExitCode -eq 0
}

function Send-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$Executable
    )

    $text = [IO.File]::ReadAllText($LocalPath, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    try {
        $mode = if ($Executable) { '700' } else { '600' }
        $remoteCommand = "set -eu; umask 077; mkdir -p /run/a1625-wifi; cat > '$RemotePath'; chmod $mode '$RemotePath'; sh -n '$RemotePath'"
        [void](Invoke-A1625SshUpload `
            -SshArguments $script:UsbSshArguments `
            -AppleTvAddress $AppleTvUsbAddress `
            -RemoteCommand $remoteCommand `
            -Payload $bytes `
            -TimeoutSeconds $TimeoutSeconds)
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Send-RuntimeArchive {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemoteDirectory,
        [Parameter(Mandatory)][string]$RequiredExecutable
    )

    $bytes = [IO.File]::ReadAllBytes($LocalPath)
    try {
        $next = "$RemoteDirectory.next"
        $remoteCommand = @"
set -eu
umask 077
rm -rf '$next'
mkdir '$next'
tar -xf - -C '$next'
test -x '$next/$RequiredExecutable'
rm -rf '$RemoteDirectory'
mv '$next' '$RemoteDirectory'
"@ -replace "`r`n", "`n"

        [void](Invoke-A1625SshUpload `
            -SshArguments $script:UsbSshArguments `
            -AppleTvAddress $AppleTvUsbAddress `
            -RemoteCommand $remoteCommand `
            -Payload $bytes `
            -TimeoutSeconds $TimeoutSeconds)
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-WifiAddress {
    $remote = @"
set -eu
state=/run/a1625-wifi
i=0
while test "`$i" -lt $TimeoutSeconds; do
    if test -s "`$state/listen-address" &&
       test -s "`$state/lease-status" &&
       grep -q '^lease_acquired=1$' "`$state/lease-status"; then
        cat "`$state/listen-address"
        exit 0
    fi
    if test -s "`$state/network.pid" &&
       ! kill -0 "`$(cat "`$state/network.pid")" 2>/dev/null; then
        exit 20
    fi
    i=`$((i + 1))
    sleep 1
done
exit 21
"@ -replace "`r`n", "`n"

    $result = Invoke-UsbSsh -Command $remote -AllowFailure
    if ($result.ExitCode -eq 20) {
        throw 'Wi-Fi network supervisor exited before DHCP completed. Inspect /run/a1625-wifi/network.log and wpa.log over USB SSH.'
    }
    if ($result.ExitCode -eq 21) {
        throw "Timed out after $TimeoutSeconds seconds waiting for a Wi-Fi DHCP lease."
    }
    if ($result.ExitCode -ne 0 -or $result.Output.Count -ne 1) {
        throw 'Could not obtain a unique Wi-Fi IPv4 address.'
    }

    $address = [string]$result.Output[0]
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        $parsed.ToString() -ne $address) {
        throw "Invalid Wi-Fi IPv4 address returned by the device: $address"
    }
    return $address
}

Assert-LocalFile $wifiModule
Assert-LocalFile $stateModule
Assert-LocalFile $WifiProfilePath
Assert-LocalFile $SshKeyPath
Assert-LocalFile $networkScript
Assert-LocalFile $dhcpScript

$KnownHostsPath = Resolve-CurrentKnownHosts
Assert-LocalFile $KnownHostsPath

$script:UsbSshArguments = @(
    Get-A1625SshArguments `
        -SshKeyPath $SshKeyPath `
        -KnownHostsPath $KnownHostsPath
)

Write-Host 'Checking the current RAM Wi-Fi hardware session...'
$hardwareCheck = @'
set -eu
state=/run/a1625-wifi
test -s "$state/runner.pid"
kill -0 "$(cat "$state/runner.pid")"
test -d /sys/class/net/wlan0
test -x /usr/sbin/dropbear
test -s /run/dropbear_ed25519_host_key
'@
[void](Invoke-UsbSsh -Command $hardwareCheck)

# If the supervisor is already alive, do not replace its live WPA configuration.
$alreadyRunning = Test-Remote @'
state=/run/a1625-wifi
test -s "$state/network.pid" &&
kill -0 "$(cat "$state/network.pid")" 2>/dev/null
'@

if (-not $alreadyRunning) {
    if (Test-Remote 'test -d /run/a1625-wifi/network-lock') {
        throw 'A stale or conflicting Wi-Fi network lock exists. Diagnose the previous session over USB SSH before retrying.'
    }

    if (-not (Test-Remote 'test -x /run/a1625-wpa/sbin/wpa_supplicant && test -x /run/a1625-wpa/sbin/wpa_cli')) {
        Assert-LocalFile $wpaArchive
        Write-Host 'Staging pinned WPA runtime to RAM...'
        Send-RuntimeArchive `
            -LocalPath $wpaArchive `
            -RemoteDirectory '/run/a1625-wpa' `
            -RequiredExecutable 'sbin/wpa_supplicant'
    }

    if (-not (Test-Remote 'test -x /run/a1625-iw/usr/sbin/iw')) {
        Assert-LocalFile $iwArchive
        Write-Host 'Staging pinned iw runtime to RAM...'
        Send-RuntimeArchive `
            -LocalPath $iwArchive `
            -RemoteDirectory '/run/a1625-iw' `
            -RequiredExecutable 'usr/sbin/iw'
    }

    Write-Host 'Staging Wi-Fi supervisor scripts to RAM...'
    Send-RemoteFile -LocalPath $networkScript -RemotePath '/run/a1625-wifi/network-session.sh' -Executable
    Send-RemoteFile -LocalPath $dhcpScript -RemotePath '/run/a1625-wifi/dhcp.sh' -Executable

    Write-Host 'Loading the DPAPI-protected Wi-Fi profile and sending WPA config through SSH stdin...'
    $profile = Read-A1625WifiProfile -Path $WifiProfilePath
    $wpaConfig = ConvertTo-A1625WpaConfig -Profile $profile
    try {
        [void](Invoke-A1625SshUpload `
            -SshArguments $script:UsbSshArguments `
            -AppleTvAddress $AppleTvUsbAddress `
            -RemoteCommand 'set -eu; umask 077; mkdir -p /run/a1625-wifi; cat > /run/a1625-wifi/wpa.conf; chmod 600 /run/a1625-wifi/wpa.conf' `
            -Payload $wpaConfig `
            -TimeoutSeconds $TimeoutSeconds)
    }
    finally {
        if ($wpaConfig) { [Array]::Clear($wpaConfig, 0, $wpaConfig.Length) }
        $profile = $null
    }

    Write-Host 'Starting WPA/DHCP/Dropbear Wi-Fi supervisor...'
    $startCommand = @'
set -eu
state=/run/a1625-wifi
nohup sh "$state/network-session.sh" > "$state/network.log" 2>&1 < /dev/null &
sleep 1
test -s "$state/network.pid"
kill -0 "$(cat "$state/network.pid")"
'@
    [void](Invoke-UsbSsh -Command $startCommand)
}
else {
    Write-Host 'Wi-Fi network supervisor is already running; keeping its current WPA configuration.'
}

Write-Host 'Waiting for DHCP and the WLAN SSH listener...'
$wifiAddress = Get-WifiAddress

Write-Host "Verifying strict-host-key SSH over Wi-Fi at $wifiAddress..."
$wifiResult = @(
    & ssh.exe -F none @script:UsbSshArguments `
        -o HostKeyAlias=172.16.42.1 `
        "root@$wifiAddress" `
        'printf "wifi_ssh=passed\n"'
)
if ($LASTEXITCODE -ne 0 -or 'wifi_ssh=passed' -notin $wifiResult) {
    throw "Wi-Fi obtained $wifiAddress, but strict-host-key SSH verification failed."
}

$status = (Invoke-UsbSsh -Command @'
set -eu
state=/run/a1625-wifi
LD_LIBRARY_PATH=/run/a1625-wpa/usr/lib:/run/a1625-wpa/lib \
    /run/a1625-wpa/sbin/wpa_cli -p "$state/control" status |
    sed -n '/^wpa_state=/p; /^pairwise_cipher=/p; /^group_cipher=/p; /^key_mgmt=/p'
cat "$state/lease-status"
'@).Output

$addressStatePath = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\last-address.txt'
$addressStateDirectory = Split-Path -Parent $addressStatePath
New-Item -ItemType Directory -Force -Path $addressStateDirectory | Out-Null
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($addressStatePath),
    $wifiAddress + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

Write-Host ''
Write-Host "Wi-Fi connected: $wifiAddress"
$status | ForEach-Object { Write-Host $_ }
Write-Host 'Wi-Fi SSH verification: passed'
Write-Host "Saved Wi-Fi address: $addressStatePath"

$result = [pscustomobject]@{
    Address        = $wifiAddress
    User           = 'root'
    Port           = 22
    KnownHostsPath = $KnownHostsPath
    SshKeyPath     = (Resolve-Path -LiteralPath $SshKeyPath).ProviderPath
    AddressStatePath = $addressStatePath
    SshVerified    = $true
}

$result

if ($EnterShell) {
    $interactiveArguments = @(
        '-tt',
        '-i', (Resolve-Path -LiteralPath $SshKeyPath).ProviderPath,
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=5',
        '-o', 'ServerAliveInterval=5',
        '-o', 'ServerAliveCountMax=3',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', ('UserKnownHostsFile=' + (Resolve-Path -LiteralPath $KnownHostsPath).ProviderPath),
        '-o', 'HostKeyAlias=172.16.42.1'
    )

    & ssh.exe -F none @interactiveArguments "root@$wifiAddress" `
        'export TERM=xterm-256color HOME=/run/codex-home CODEX_HOME=/run/codex-home PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin; cd /run/work; exec /bin/sh -i'

    if ($LASTEXITCODE -ne 0) {
        throw "Interactive Wi-Fi SSH session ended with exit code $LASTEXITCODE."
    }
}
