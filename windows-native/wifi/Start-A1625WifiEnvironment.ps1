#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('none', 'minimal', 'development')]
    [string]$DevelopmentProfile = 'development',

    [bool]$EnableZram = $true,

    [switch]$RestoreRamState,

    [string]$RamStateDirectory = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state'),

    [ValidatePattern('^[0-9A-Fa-f]{16}$')]
    [string]$ExpectedEcid,

    [ValidateRange(30, 300)]
    [int]$StageTimeoutSeconds = 120,

    [ValidateRange(0, 5)]
    [int]$DfuIdentityRetryCount = 2,

    [ValidateRange(15, 300)]
    [int]$DfuReentryTimeoutSeconds = 120,

    [ValidateRange(10, 300)]
    [int]$WifiTimeoutSeconds = 90,

    [switch]$SkipRamBoot,

    [switch]$EnterShell,

    [string]$KnownHostsPath,

    [string]$SshKeyPath,

    [string]$WifiProfilePath = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\japan.wifi.dpapi'),

    [string]$WifiModulePath,

    [string]$ProbeRunnerPath,

    [string]$FirmwarePath,

    [string]$RegulatoryDbPath,

    [string]$RegulatoryDbSignaturePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wifiDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $wifiDirectory '..\..'))
$artifactRoot = Join-Path $repoRoot 'artifacts'

$restoreScript = Join-Path $repoRoot 'windows-native\Restore-A1625RamEnvironment.ps1'
$connectScript = Join-Path $wifiDirectory 'Connect-A1625Wifi.ps1'
$profileScript = Join-Path $wifiDirectory 'Set-A1625WifiProfile.ps1'
$buildUserlandScript = Join-Path $wifiDirectory 'build_userland.py'
$holdScript = Join-Path $wifiDirectory 'hold-wifi-session.sh'
$stateModule = Join-Path $repoRoot 'windows-native\codex-state\A1625CodexState.psm1'
$atvModule = Join-Path $repoRoot 'windows-native\AtvNative.psm1'

$wpaArchive = Join-Path $artifactRoot 'wifi-userland\reproduced\wpa-runtime.tar'
$iwArchive = Join-Path $artifactRoot 'wifi-userland\reproduced\iw-runtime.tar'

if (-not $SshKeyPath) {
    $SshKeyPath = Join-Path $artifactRoot 'ssh\a1625_ram_ed25519'
}

$expectedWifiModuleSha256 = 'D8E545E0AF7CD7ADE10E2AC9157A1E0C8983B4563B28B9709BD3DC2A89DC2109'
$expectedFirmwareSha256 = '5691D1E0CEB70BAF18EFB7A0EC6CB84FEB9EDD2D0700C525B42930C4E7E4B845'
$usbAddress = '172.16.42.1'

function Write-Stage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n== $Message ==" -ForegroundColor Cyan
}

function Assert-File {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw @"
SHA-256 mismatch.

Path:     $Path
Expected: $Expected
Actual:   $actual
"@
    }
}

function Resolve-ArtifactByName {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory)][string]$FileName,
        [string]$ExpectedSha256
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolved = Assert-File $ExplicitPath
        if ($ExpectedSha256) {
            Assert-Sha256 -Path $resolved -Expected $ExpectedSha256
        }
        return $resolved
    }

    if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) {
        throw "Artifact directory was not found: $artifactRoot"
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $artifactRoot -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue
    )

    if ($ExpectedSha256) {
        $candidates = @(
            $candidates | Where-Object {
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $ExpectedSha256.ToUpperInvariant()
            }
        )
    }

    if ($candidates.Count -eq 0) {
        $hint = if ($ExpectedSha256) { " with SHA-256 $ExpectedSha256" } else { '' }
        throw "Could not find $FileName$hint under $artifactRoot. Pass its explicit path to this script."
    }

    if ($candidates.Count -ne 1) {
        $paths = ($candidates.FullName | ForEach-Object { "  $_" }) -join "`n"
        throw "More than one matching $FileName was found. Pass an explicit path.`n$paths"
    }

    return $candidates[0].FullName
}

function Resolve-RegulatoryPair {
    if ($RegulatoryDbPath -or $RegulatoryDbSignaturePath) {
        if (-not $RegulatoryDbPath -or -not $RegulatoryDbSignaturePath) {
            throw 'Pass both -RegulatoryDbPath and -RegulatoryDbSignaturePath together.'
        }

        return [pscustomobject]@{
            Database  = Assert-File $RegulatoryDbPath
            Signature = Assert-File $RegulatoryDbSignaturePath
        }
    }

    $databases = @(
        Get-ChildItem -LiteralPath $artifactRoot -Recurse -File -Filter 'regulatory.db' -ErrorAction SilentlyContinue
    )

    $pairs = @(
        foreach ($database in $databases) {
            $signature = Join-Path $database.DirectoryName 'regulatory.db.p7s'
            if (Test-Path -LiteralPath $signature -PathType Leaf) {
                [pscustomobject]@{
                    Database  = $database.FullName
                    Signature = (Resolve-Path -LiteralPath $signature).ProviderPath
                }
            }
        }
    )

    if ($pairs.Count -eq 0) {
        throw @"
Could not find a regulatory.db + regulatory.db.p7s pair under:
  $artifactRoot

Pass:
  -RegulatoryDbPath '<path-to-regulatory.db>'
  -RegulatoryDbSignaturePath '<path-to-regulatory.db.p7s>'
"@
    }

    if ($pairs.Count -ne 1) {
        $paths = ($pairs | ForEach-Object { "  $($_.Database)" }) -join "`n"
        throw "More than one signed regulatory database was found. Pass explicit paths.`n$paths"
    }

    return $pairs[0]
}

function Resolve-KnownHosts {
    if (-not [string]::IsNullOrWhiteSpace($KnownHostsPath)) {
        return Assert-File $KnownHostsPath
    }

    $stateRoot = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
    $latest = Get-ChildItem -LiteralPath $stateRoot -Filter 'known_hosts_ram_*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No per-boot known_hosts file was found after RAM boot.'
    }

    return $latest.FullName
}

function Invoke-UsbCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$AllowFailure
    )

    $normalized = $Command -replace "`r`n", "`n" -replace "`r", "`n"
    $output = @(& ssh.exe -F none @script:SshArguments "root@$usbAddress" $normalized)
    $code = $LASTEXITCODE

    if (-not $AllowFailure -and $code -ne 0) {
        throw "USB SSH command failed with exit code $code.`n$($output -join "`n")"
    }

    [pscustomobject]@{
        ExitCode = $code
        Output   = $output
    }
}

function Send-Bytes {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Sha256,
        [ValidateSet('600', '700')]
        [string]$Mode = '600'
    )

    $remoteDirectory = [IO.Path]::GetDirectoryName($RemotePath.Replace('/', '\')).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($remoteDirectory)) {
        throw "Could not determine remote directory for $RemotePath"
    }

    $remote = "set -eu; umask 077; mkdir -p '$remoteDirectory'; cat > '$RemotePath'; chmod $Mode '$RemotePath'; echo '$($Sha256.ToLowerInvariant())  $RemotePath' | sha256sum -c -"

    [void](Invoke-A1625SshUpload `
        -SshArguments $script:SshArguments `
        -AppleTvAddress $usbAddress `
        -RemoteCommand $remote `
        -Payload $Bytes `
        -TimeoutSeconds $StageTimeoutSeconds)
}

function Send-File {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath,
        [ValidateSet('600', '700')]
        [string]$Mode = '600',
        [switch]$NormalizeLf
    )

    if ($NormalizeLf) {
        $text = [IO.File]::ReadAllText($LocalPath, [Text.Encoding]::UTF8)
        $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    }
    else {
        $bytes = [IO.File]::ReadAllBytes($LocalPath)
    }

    try {
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        Send-Bytes -Bytes $bytes -RemotePath $RemotePath -Sha256 $hash -Mode $Mode
    }
    finally {
        if ($bytes) {
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
    }
}

function Wait-CleanDfuReentry {
    param(
        [ValidateRange(15, 300)]
        [int]$TimeoutSeconds = 120,

        [ValidateRange(2, 10)]
        [int]$StablePolls = 5
    )

    Import-Module $atvModule -Force

    # Do not accept the 05AC:1227 instance that was already present when
    # openra1n reported the descriptor-read failure.  That device may be the
    # failed/post-exploit enumeration.  A real manual DFU re-entry must first
    # produce a USB disappearance and then a new clean-DFU presence.
    $deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds)
    $sawAbsent = $false

    Write-Host 'Waiting for the current failed DFU enumeration to disappear...' -ForegroundColor Yellow

    while ([DateTimeOffset]::Now -lt $deadline) {
        $presentDfu = @(
            Get-AtvUsbState | Where-Object { $_.ProductId -eq '1227' }
        )

        if ($presentDfu.Count -eq 0) {
            $sawAbsent = $true
            Write-Host 'DFU disappearance detected. Waiting for a fresh clean DFU enumeration...' -ForegroundColor Cyan
            break
        }

        # Poll quickly so a short USB re-enumeration gap is not missed.
        Start-Sleep -Milliseconds 100
    }

    if (-not $sawAbsent) {
        throw @"
The existing 05AC:1227 DFU enumeration never disappeared.

The retry was intentionally NOT started, because reusing the same failed DFU
instance can reproduce the serial-descriptor error.

Physically re-enter CLEAN DFU so Windows observes a disconnect/re-enumeration,
then run the one-command Wi-Fi wrapper again.
"@
    }

    $stable = 0
    $lastInstance = ''

    while ([DateTimeOffset]::Now -lt $deadline) {
        $dfu = @(
            Get-AtvUsbState | Where-Object {
                $_.ProductId -eq '1227' -and
                $_.Status -eq 'OK' -and
                [string]$_.InstanceId -notmatch '(?i)YOLO:'
            }
        )

        if ($dfu.Count -eq 1) {
            $instance = [string]$dfu[0].InstanceId

            if ($instance -eq $lastInstance) {
                $stable++
            }
            else {
                $lastInstance = $instance
                $stable = 1
            }

            if ($stable -ge $StablePolls) {
                Write-Host 'Fresh clean DFU is stably present: 05AC:1227' -ForegroundColor Green

                # PnP presence can become visible slightly before libusb string
                # descriptor reads become reliable.  Keep this bounded and do
                # not weaken CPID/BDID/ECID verification.
                Start-Sleep -Seconds 3
                return
            }
        }
        else {
            $stable = 0
            $lastInstance = ''
        }

        Start-Sleep -Milliseconds 250
    }

    throw "A fresh clean DFU did not become stably available within $TimeoutSeconds seconds."
}

function Invoke-WifiRamRestoreWithDfuRetry {
    param([hashtable]$RestoreParameters)

    $attempt = 0
    while ($true) {
        try {
            & $restoreScript @RestoreParameters
            return
        }
        catch {
            $message = [string]$_.Exception.Message
            $isSettlingFailure =
                $message -match 'DFU identity could not be verified during checkm8' -or
                $message -match 'Failed to read DFU USB serial string descriptor' -or
                $message -match 'check callback rejected it'

            if (-not $isSettlingFailure -or $attempt -ge $DfuIdentityRetryCount) {
                throw
            }

            $attempt++

            Write-Warning @"
The checkm8 stage reached the device, but Windows/libusb could not read the
DFU serial identity reliably after re-enumeration.

The A1625 identity gate has NOT been bypassed.

Re-enter the Apple TV into CLEAN DFU mode now.

This wrapper will NOT accept the currently-present failed DFU enumeration.
It must observe 05AC:1227 disappear and then reappear as a fresh clean DFU
before it retries.

No new PowerShell command is required.

Retry $attempt of $DfuIdentityRetryCount.
"@

            Wait-CleanDfuReentry -TimeoutSeconds $DfuReentryTimeoutSeconds
            Write-Host "Retrying the complete verified RAM restore..." -ForegroundColor Cyan
        }
    }
}

# ---------------------------------------------------------------------------
# Host-side preflight. Do this before a DFU boot so missing private artifacts
# fail before the Apple TV session is changed.
# ---------------------------------------------------------------------------

Write-Stage 'Host Wi-Fi preflight'

foreach ($required in @($restoreScript, $connectScript, $holdScript, $stateModule, $atvModule, $SshKeyPath)) {
    [void](Assert-File $required)
}

foreach ($tool in @('ssh.exe', 'python.exe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required host tool was not found in PATH: $tool"
    }
}

if ($DevelopmentProfile -eq 'none' -and $EnableZram) {
    throw '-EnableZram requires DevelopmentProfile minimal or development. Use -EnableZram:$false with -DevelopmentProfile none.'
}

$WifiModulePath = Resolve-ArtifactByName `
    -ExplicitPath $WifiModulePath `
    -FileName 'a1625_pcie_domains.ko' `
    -ExpectedSha256 $expectedWifiModuleSha256

$ProbeRunnerPath = Resolve-ArtifactByName `
    -ExplicitPath $ProbeRunnerPath `
    -FileName 'run_probe_once'

$FirmwarePath = Resolve-ArtifactByName `
    -ExplicitPath $FirmwarePath `
    -FileName 'brcmfmac4350-pcie.bin' `
    -ExpectedSha256 $expectedFirmwareSha256

$regulatory = Resolve-RegulatoryPair
$RegulatoryDbPath = $regulatory.Database
$RegulatoryDbSignaturePath = $regulatory.Signature

Write-Host "Wi-Fi module:       $WifiModulePath"
Write-Host "Probe runner:       $ProbeRunnerPath"
Write-Host "BCM4350 firmware:   $FirmwarePath"
Write-Host "Regulatory DB:      $RegulatoryDbPath"
Write-Host "Regulatory DB sig:  $RegulatoryDbSignaturePath"

if (-not (Test-Path -LiteralPath $WifiProfilePath -PathType Leaf)) {
    $defaultProfile = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\japan.wifi.dpapi'
    if ([IO.Path]::GetFullPath($WifiProfilePath) -ne [IO.Path]::GetFullPath($defaultProfile)) {
        throw "Custom Wi-Fi profile does not exist: $WifiProfilePath"
    }

    Write-Host 'Wi-Fi profile does not exist yet. Creating the protected DPAPI profile now.'
    & $profileScript
    if (-not (Test-Path -LiteralPath $WifiProfilePath -PathType Leaf)) {
        throw 'Wi-Fi profile creation did not complete.'
    }
}

if (-not (Test-Path -LiteralPath $wpaArchive -PathType Leaf) -or
    -not (Test-Path -LiteralPath $iwArchive -PathType Leaf)) {
    Write-Host 'Pinned Wi-Fi userland archives are missing. Building them now...'
    & python.exe $buildUserlandScript
    if ($LASTEXITCODE -ne 0) {
        throw 'build_userland.py failed.'
    }
}

foreach ($archive in @($wpaArchive, $iwArchive)) {
    [void](Assert-File $archive)
}

# ---------------------------------------------------------------------------
# Fresh RAM boot unless explicitly told to attach to an already-running
# wifi-t7000-leaf session.
# ---------------------------------------------------------------------------

if (-not $SkipRamBoot) {
    Write-Stage 'RAM boot: wifi-t7000-leaf'

    $restoreParameters = @{
        ConfirmRamBoot      = $true
        BootProfile         = 'wifi-t7000-leaf'
        DevelopmentProfile  = $DevelopmentProfile
        StageTimeoutSeconds = $StageTimeoutSeconds
    }

    if ($EnableZram) {
        $restoreParameters.EnableZram = $true
    }
    if ($RestoreRamState) {
        $restoreParameters.RestoreRamState = $true
        $restoreParameters.RamStateDirectory = $RamStateDirectory
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedEcid)) {
        $restoreParameters.ExpectedEcid = $ExpectedEcid
    }

    Invoke-WifiRamRestoreWithDfuRetry -RestoreParameters $restoreParameters
}
else {
    Write-Stage 'Using the already-running RAM Linux session'
}

$KnownHostsPath = Resolve-KnownHosts

Import-Module $stateModule -Force
$script:SshArguments = @(
    Get-A1625SshArguments `
        -SshKeyPath $SshKeyPath `
        -KnownHostsPath $KnownHostsPath
)

Write-Host "Per-boot known_hosts: $KnownHostsPath"

# Confirm that the strict current-boot USB SSH path is alive before staging
# firmware or executing the hardware runner.
Write-Stage 'USB RAM Linux verification'

$usbHealth = Invoke-UsbCommand @'
set -eu
test "$(uname -m)" = aarch64
grep -q '^KernelPageSize:[[:space:]]*4 kB$' /proc/self/smaps
grep -q ' / rootfs ' /proc/mounts
test -x /usr/sbin/dropbear
test -s /run/dropbear_ed25519_host_key
printf 'usb_ram_ready\n'
'@

if ('usb_ram_ready' -notin $usbHealth.Output) {
    throw 'Strict USB SSH succeeded but the RAM Linux health marker was not returned.'
}

# ---------------------------------------------------------------------------
# Hardware session
# ---------------------------------------------------------------------------

Write-Stage 'Wi-Fi hardware session'

$existingHardware = Invoke-UsbCommand -AllowFailure @'
state=/run/a1625-wifi
test -s "$state/runner.pid" &&
kill -0 "$(cat "$state/runner.pid")" 2>/dev/null &&
test -d /sys/class/net/wlan0
'@

if ($existingHardware.ExitCode -eq 0) {
    Write-Host 'A healthy Wi-Fi hardware session is already running; reusing it.'
}
else {
    $staleLock = Invoke-UsbCommand -AllowFailure 'test -d /run/a1625-wifi/session-lock'
    if ($staleLock.ExitCode -eq 0) {
        throw @"
A Wi-Fi session lock exists but no healthy runner/wlan0 pair is active.

Do not delete the lock automatically. Inspect:
  /run/a1625-wifi/hold.log
  dmesg

or reboot into a fresh RAM session before retrying.
"@
    }

    Write-Host 'Staging verified BCM4350 firmware and regulatory database to RAM...'
    Send-File -LocalPath $FirmwarePath -RemotePath '/lib/firmware/brcm/brcmfmac4350-pcie.bin'
    Send-File -LocalPath $RegulatoryDbPath -RemotePath '/lib/firmware/regulatory.db'
    Send-File -LocalPath $RegulatoryDbSignaturePath -RemotePath '/lib/firmware/regulatory.db.p7s'

    Write-Host 'Staging the validated PCI/DART/MSI Wi-Fi module and single-call runner...'
    Send-File -LocalPath $WifiModulePath -RemotePath '/run/a1625_hold.ko'
    Send-File -LocalPath $ProbeRunnerPath -RemotePath '/run/run_probe_once' -Mode '700'
    Send-File -LocalPath $holdScript -RemotePath '/run/a1625-wifi/hold.sh' -Mode '700' -NormalizeLf

    [void](Invoke-UsbCommand "sh -n /run/a1625-wifi/hold.sh")

    Write-Host 'Starting the signal-held Wi-Fi hardware session...'
    [void](Invoke-UsbCommand @'
set -eu
state=/run/a1625-wifi
test ! -e "$state/session-lock"
nohup sh "$state/hold.sh" > "$state/hold.log" 2>&1 < /dev/null &
sleep 1
test -s "$state/runner.pid"
kill -0 "$(cat "$state/runner.pid")"
'@)

    $waitCommand = @"
state=/run/a1625-wifi
i=0
while test "`$i" -lt $WifiTimeoutSeconds; do
    if test -s "`$state/runner.pid" &&
       kill -0 "`$(cat "`$state/runner.pid")" 2>/dev/null &&
       test -d /sys/class/net/wlan0; then
        printf 'wifi_hardware_ready\n'
        exit 0
    fi

    if test -s "`$state/runner.pid" &&
       ! kill -0 "`$(cat "`$state/runner.pid")" 2>/dev/null; then
        echo 'Wi-Fi runner exited before wlan0 appeared.' >&2
        tail -n 80 "`$state/hold.log" >&2 || true
        exit 20
    fi

    i=`$((i + 1))
    sleep 1
done

echo 'Timed out waiting for wlan0.' >&2
tail -n 80 "`$state/hold.log" >&2 || true
exit 21
"@
    $hardwareReady = Invoke-UsbCommand $waitCommand

    if ('wifi_hardware_ready' -notin $hardwareReady.Output) {
        throw 'Wi-Fi hardware session did not return the ready marker.'
    }
}

# Verify the live PCI endpoint rather than relying on wlan0 alone.
$pciCheck = Invoke-UsbCommand @'
set -eu
dev=/sys/class/net/wlan0/device
test -e "$dev"
vendor=$(cat "$dev/vendor")
device=$(cat "$dev/device")
revision=$(cat "$dev/revision")
printf 'wifi_vendor=%s\n' "$vendor"
printf 'wifi_device=%s\n' "$device"
printf 'wifi_revision=%s\n' "$revision"
test "$vendor" = 0x14e4
test "$device" = 0x43a3
test "$revision" = 0x08
printf 'wifi_pci_verified\n'
'@

if ('wifi_pci_verified' -notin $pciCheck.Output) {
    throw 'wlan0 exists, but the expected BCM4350 revision-8 PCI identity was not verified.'
}

$pciCheck.Output | ForEach-Object { Write-Host $_ }

# ---------------------------------------------------------------------------
# WPA / DHCP / WLAN Dropbear
# ---------------------------------------------------------------------------

Write-Stage 'WPA2 / DHCP / Wi-Fi SSH'

$connectParameters = @{
    AppleTvUsbAddress = $usbAddress
    WifiProfilePath   = $WifiProfilePath
    SshKeyPath        = $SshKeyPath
    KnownHostsPath    = $KnownHostsPath
    TimeoutSeconds    = $WifiTimeoutSeconds
}

if ($EnterShell) {
    $connectParameters.EnterShell = $true
}

$connectionOutput = @(& $connectScript @connectParameters)
$connection = $connectionOutput |
    Where-Object {
        $_ -and
        $_.PSObject.Properties.Name -contains 'SshVerified' -and
        $_.PSObject.Properties.Name -contains 'Address'
    } |
    Select-Object -Last 1

if (-not $connection -or -not $connection.SshVerified) {
    throw 'Connect-A1625Wifi.ps1 did not return a verified Wi-Fi connection.'
}

Write-Stage 'A1625 Wi-Fi ready'

Write-Host "Wi-Fi IPv4:         $($connection.Address)" -ForegroundColor Green
Write-Host "Wi-Fi SSH:          root@$($connection.Address):22"
Write-Host "Known hosts:        $($connection.KnownHostsPath)"
Write-Host "Saved address:      $($connection.AddressStatePath)"
Write-Host ''
Write-Host 'USB data can now be disconnected if you want to continue over Wi-Fi.'
Write-Host 'Open a Wi-Fi shell later with:'
Write-Host '  & .\windows-native\wifi\Enter-A1625WifiShell.ps1'

[pscustomobject]@{
    Address            = $connection.Address
    User               = 'root'
    Port               = 22
    BootProfile        = 'wifi-t7000-leaf'
    DevelopmentProfile = $DevelopmentProfile
    ZramEnabled        = [bool]$EnableZram
    KnownHostsPath     = $connection.KnownHostsPath
    AddressStatePath   = $connection.AddressStatePath
    HardwareVerified   = $true
    WifiSshVerified    = $true
}
