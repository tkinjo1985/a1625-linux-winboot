#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$ConfirmRamBoot,

    [ValidateSet('baseline', 'wifi-experimental', 'wifi-fw-lifetime', 'wifi-fw-response', 'wifi-t7000-table', 'wifi-t7000-leaf')]
    [string]$BootProfile = 'baseline',

    [ValidatePattern('^[0-9A-Fa-f]{16}$')]
    [string]$ExpectedEcid,

    [ValidateRange(30, 300)]
    [int]$StageTimeoutSeconds = 120,

    [switch]$StartCodex,
    [switch]$EnterShell,
    [ValidateSet('none', 'minimal', 'development')]
    [string]$DevelopmentProfile = 'none',
    [switch]$EnableZram,
    [switch]$RestoreRamState,
    [string]$RamStateDirectory = (Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state'),
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$openra1n = Join-Path $repoRoot 'artifacts\openra1n-win\openra1n.exe'
$libusb = Join-Path $repoRoot 'artifacts\openra1n-win\libusb-1.0.dll'
$uploader = Join-Path $repoRoot 'windows-native\pongo-uploader\target\release\atv-pongo-uploader.exe'
$payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-minimal-ssh.bin'
$payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-minimal-ssh.manifest.json'
$kernelConfig = Join-Path $repoRoot 'third_party\HoolockLinux-linux-native\.config'
$expectedPayloadHash = '53DC73174456FB67951F60CA242DE04B8E1920C017829F7D8FF4E866B3769756'
if ($BootProfile -eq 'wifi-experimental') {
    $payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-experimental.bin'
    $payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-experimental.manifest.json'
    $kernelConfig = Join-Path $repoRoot 'artifacts\wifi-kernel-config\experimental-kernel\kernel.config'
    $expectedPayloadHash = '7886737B66DA0276FBA66A1FD3CA2EE69BB3AAB3DE8F6080B6832659CA67F9F3'
}
if ($BootProfile -eq 'wifi-fw-lifetime') {
    $payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-fw-lifetime.bin'
    $payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-fw-lifetime.manifest.json'
    $kernelConfig = Join-Path $repoRoot 'artifacts\wifi-kernel-config\fw-lifetime-kernel\kernel.config'
    $expectedPayloadHash = 'A2D151944C1FA813D59D60861354C3B5294D8931FFA91D3B16525716495AFDAE'
}
if ($BootProfile -eq 'wifi-fw-response') {
    $payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-fw-response.bin'
    $payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-fw-response.manifest.json'
    $kernelConfig = Join-Path $repoRoot 'artifacts\wifi-kernel-config\fw-response-kernel\kernel.config'
    $expectedPayloadHash = '18F1EB8512DE9E1B09227079534EAF1E1DACFB34DB7105B79901964DEFBDBC2C'
}
if ($BootProfile -eq 'wifi-t7000-table') {
    $payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-table.bin'
    $payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-table.manifest.json'
    $kernelConfig = Join-Path $repoRoot 'artifacts\wifi-kernel-config\t7000-table-kernel\kernel.config'
    $expectedPayloadHash = '923A737232CA063E989484986C60F966758BDAC3C9C38C256374E5A600AF693E'
}
if ($BootProfile -eq 'wifi-t7000-leaf') {
    $payload = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.bin'
    $payloadManifest = Join-Path $repoRoot 'artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.manifest.json'
    $kernelConfig = Join-Path $repoRoot 'artifacts\wifi-kernel-config\t7000-leaf-kernel\kernel.config'
    $expectedPayloadHash = 'BC775028ABA05573AB2155CA399C5EC6C7E6F1DC42E5F3A97F3E37FFEF7D6AF1'
}
$sshKey = Join-Path $repoRoot 'artifacts\ssh\a1625_ram_ed25519'
$atvModule = Join-Path $repoRoot 'windows-native\AtvNative.psm1'
$runtimeInstaller = Join-Path $repoRoot 'windows-native\codex-runtime\Install-CodexRamRuntime.ps1'
$codexStarter = Join-Path $repoRoot 'windows-native\codex-state\Start-A1625Codex.ps1'
$shellStarter = Join-Path $repoRoot 'windows-native\Enter-A1625Shell.ps1'
$developmentInstaller = Join-Path $repoRoot 'windows-native\development-tools\Install-A1625DevelopmentTools.ps1'
$ramStateRestorer = Join-Path $repoRoot 'windows-native\ram-state\Restore-A1625RamState.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
$deviceConfig = Join-Path $stateRoot 'device.json'
$logRoot = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\logs'

function Write-Stage {
    param([string]$Message)
    Write-Host "`n== $Message ==" -ForegroundColor Cyan
}

function Resolve-ExpectedEcid {
    if (-not [string]::IsNullOrWhiteSpace($ExpectedEcid)) {
        return $ExpectedEcid.ToUpperInvariant()
    }
    if (-not (Test-Path -LiteralPath $deviceConfig -PathType Leaf)) {
        throw "No device ECID was supplied. Run Set-A1625DeviceConfig.ps1 once, or pass -ExpectedEcid with the owned A1625's 16-hex-digit ECID."
    }
    $config = Get-Content -LiteralPath $deviceConfig -Raw | ConvertFrom-Json
    $configuredEcid = [string]$config.expectedEcid
    if ($configuredEcid -notmatch '^[0-9A-Fa-f]{16}$') {
        throw "Invalid expectedEcid in local device configuration: $deviceConfig"
    }
    return $configuredEcid.ToUpperInvariant()
}

function Assert-FileHash {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        throw "SHA-256 mismatch for $Path`nExpected: $Expected`nActual:   $actual"
    }
}

function Assert-LocalPreflight {
    Write-Stage 'Local RAM-only artifact verification'
    Assert-FileHash $openra1n 'ACB926409898C89DE9051268F5B1771C26F59E3A30FE25C34402EC3F880DF5AF'
    Assert-FileHash $libusb '39A8BE2A8C628C2A6146A3A1A85758A5F7FE44045FE425C9BF5897A11EA1B46C'
    Assert-FileHash $uploader 'CC015641D654339E8F93D4984A3165E43DA47681498004B333DE37720829CA6E'
    Assert-FileHash $payload $expectedPayloadHash

    foreach ($path in $payloadManifest, $kernelConfig, $sshKey, $atvModule, $runtimeInstaller, $codexStarter, $shellStarter) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required file was not found: $path"
        }
    }
    $manifest = Get-Content -LiteralPath $payloadManifest -Raw | ConvertFrom-Json
    if ($manifest.target -ne 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000' -or
        $manifest.mode -ne 'RAM-only PongoOS m1n1 Linux boot' -or
        $manifest.payload.sha256 -ne $expectedPayloadHash) {
        throw 'The Linux payload manifest is not the validated A1625/T7000 RAM-only manifest.'
    }
    if (-not (Select-String -LiteralPath $kernelConfig -SimpleMatch 'CONFIG_ARM64_4K_PAGES=y' -Quiet)) {
        throw 'The Hoolock kernel configuration does not contain CONFIG_ARM64_4K_PAGES=y.'
    }
    foreach ($tool in 'ssh.exe', 'ssh-keygen.exe', 'ssh-keyscan.exe', 'python.exe') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required host tool was not found: $tool"
        }
    }
    Write-Host 'Validated A1625/T7000 RAM-only payload, host tools, and 4 KiB kernel configuration.'
}

function Get-ProductDetails {
    param([string]$ProductId)
    @(Get-AtvUsbDetails | Where-Object { $_.UsbId -eq "05AC:$ProductId" })
}

function Wait-ProductDetails {
    param([string]$ProductId, [int]$TimeoutSeconds = $StageTimeoutSeconds)
    $deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds)
    while ([DateTimeOffset]::Now -lt $deadline) {
        $details = @(Get-ProductDetails $ProductId)
        if ($details.Count -gt 0) { return $details }
        Start-Sleep -Milliseconds 500
    }
    @()
}

function Assert-SingleDevice {
    param([object[]]$Details, [string]$Description)
    if ($Details.Count -ne 1) {
        throw "Expected exactly one $Description; found $($Details.Count)."
    }
    if ($Details[0].Status -ne 'OK' -or [string]$Details[0].ProblemCode -notin @('', '0')) {
        throw "$Description is not healthy: status=$($Details[0].Status), problem=$($Details[0].ProblemCode)"
    }
    $Details[0]
}

function Assert-DfuIdentity {
    param([object]$Device, [switch]$RequireYolo)
    $identity = [string]$Device.InstanceId
    if ($identity -notmatch '(?i)CPID:7000(?:_|\b)' -or
        $identity -notmatch '(?i)BDID:34(?:_|\b)' -or
        $identity -notmatch "(?i)ECID:$([regex]::Escape($ExpectedEcid))(?:_|\b)") {
        throw "DFU identity is not the authorized A1625/T7000/ECID: $identity"
    }
    if ($RequireYolo -and $identity -notmatch '(?i)YOLO:') {
        throw "The device is clean DFU, not YOLO. Re-enter DFU and restart recovery; upload-only was not run.`n$identity"
    }
}

function Confirm-LibusbK {
    param([string]$ProductId, [string]$Label, [switch]$RequireYolo)
    while ($true) {
        $items = @(Wait-ProductDetails $ProductId 20)
        $device = Assert-SingleDevice -Details $items -Description $Label
        if ($ProductId -eq '1227') { Assert-DfuIdentity $device -RequireYolo:$RequireYolo }
        if ($device.DriverService -eq 'libusbK') { return $device }

        Write-Host "`nZadig操作が必要です。次の1デバイスだけを選択してください。" -ForegroundColor Yellow
        $device | Format-List UsbId, FriendlyName, BusDescription, DriverService, InstanceId | Out-Host
        Write-Host 'Zadigを管理者として起動し、Options > List All Devices を有効化します。'
        Write-Host "変更前に現在のドライバーを記録し、復旧手順を確認してください: $(Join-Path $PSScriptRoot 'DRIVER-ROLLBACK.md')"
        Write-Host "上記の $($device.UsbId) を選び、libusbK に変更してください。ほかのApple USBデバイスは変更しないでください。"
        if ([Console]::IsInputRedirected) {
            throw "The verified $Label needs libusbK. Change only this instance, then rerun the restore command; its current stage will be detected."
        }
        [void](Read-Host '完了後、このPowerShellへ戻ってEnter')
    }
}

function Get-LogDelta {
    param([string]$Path, [ref]$Offset)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        try { $text = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
    if ($text.Length -le $Offset.Value) { return '' }
    $delta = $text.Substring($Offset.Value)
    $Offset.Value = $text.Length
    $delta
}

function Invoke-BoundedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds,
        [string]$StopOnPattern
    )
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $stamp = '{0}_{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')), ([guid]::NewGuid().ToString('N'))
    $stdoutPath = Join-Path $logRoot "$stamp.stdout.log"
    $stderrPath = Join-Path $logRoot "$stamp.stderr.log"
    $quotedArguments = @($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
    })
    $process = Start-Process -FilePath $FilePath -ArgumentList $quotedArguments -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $outOffset = 0
    $errOffset = 0
    $allText = ''
    $matched = $false
    $timedOut = $false
    try {
        $deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited) {
            $delta = Get-LogDelta -Path $stdoutPath -Offset ([ref]$outOffset)
            if ($delta) { Write-Host -NoNewline $delta; $allText += $delta }
            $delta = Get-LogDelta -Path $stderrPath -Offset ([ref]$errOffset)
            if ($delta) { Write-Host -NoNewline $delta; $allText += $delta }
            if ($StopOnPattern -and $allText -match $StopOnPattern) {
                $matched = $true
                Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
                if (-not $process.WaitForExit(5000)) {
                    $process.Kill($true)
                    [void]$process.WaitForExit(5000)
                }
                break
            }
            if ([DateTimeOffset]::Now -ge $deadline) {
                $timedOut = $true
                Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
                if (-not $process.WaitForExit(5000)) {
                    $process.Kill($true)
                    [void]$process.WaitForExit(5000)
                }
                break
            }
            Start-Sleep -Milliseconds 150
            $process.Refresh()
        }
    }
    finally {
        $delta = Get-LogDelta -Path $stdoutPath -Offset ([ref]$outOffset)
        if ($delta) { Write-Host -NoNewline $delta; $allText += $delta }
        $delta = Get-LogDelta -Path $stderrPath -Offset ([ref]$errOffset)
        if ($delta) { Write-Host -NoNewline $delta; $allText += $delta }
    }
    if (-not $process.HasExited) {
        $process.Dispose()
        throw "Tracked child process did not exit: $FilePath"
    }
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($timedOut) { throw "Process timed out after $TimeoutSeconds seconds: $FilePath" }
    [pscustomobject]@{
        ExitCode = $exitCode
        Matched = $matched
        Output = $allText
        StdoutLog = $stdoutPath
        StderrLog = $stderrPath
    }
}

function Test-TcpPort {
    param([string]$Address, [int]$Port, [int]$TimeoutMilliseconds = 1000)
    $client = [Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync($Address, $Port).Wait($TimeoutMilliseconds) -and $client.Connected }
    catch { $false }
    finally { $client.Dispose() }
}

function Wait-TcpPort {
    param([string]$Address, [int]$Port, [int]$TimeoutSeconds)
    $deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds)
    while ([DateTimeOffset]::Now -lt $deadline) {
        if (Test-TcpPort $Address $Port) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "TCP $Address`:$Port did not become available within $TimeoutSeconds seconds."
}

function Configure-UsbNetwork {
    Write-Stage 'USB NCM and Windows NAT'
    $ncmItems = @(Get-ProductDetails '4142' | Where-Object { $_.InstanceId -match '(?i)&MI_00\\' })
    $ncmDevice = Assert-SingleDevice -Details $ncmItems -Description 'A1625 USB NCM interface'
    if ($ncmDevice.DriverService -ne 'UsbNcm' -or $ncmDevice.BusDescription -ne 'CDC NCM') {
        throw "Unexpected NCM driver or descriptor: $($ncmDevice.DriverService) / $($ncmDevice.BusDescription)"
    }
    $adapters = @(Get-NetAdapter -IncludeHidden | Where-Object {
        $_.PnPDeviceID -eq $ncmDevice.InstanceId -and $_.InterfaceDescription -eq 'UsbNcm Host Device'
    })
    if ($adapters.Count -ne 1) { throw "Expected one matching UsbNcm adapter; found $($adapters.Count)." }
    $adapter = $adapters[0]
    $otherOwner = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -eq '172.16.42.2' -and $_.InterfaceIndex -ne $adapter.ifIndex
    })
    if ($otherOwner.Count -gt 0) { throw '172.16.42.2 is already assigned to another adapter.' }

    $hostIp = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq '172.16.42.2' -and $_.PrefixLength -eq 24 })
    $adapterIps = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $wrongHostIp = @($adapterIps | Where-Object { $_.IPAddress -eq '172.16.42.2' -and $_.PrefixLength -ne 24 })
    $competingIp = @($adapterIps | Where-Object {
        $_.IPAddress -ne '172.16.42.2' -and $_.IPAddress -notlike '169.254.*'
    })
    if ($wrongHostIp.Count -gt 0 -or $competingIp.Count -gt 0) {
        throw 'The A1625 USB NCM adapter has an unexpected IPv4 configuration; it was not modified.'
    }
    if ($hostIp.Count -eq 0) {
        Assert-NetworkAdministrator
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress '172.16.42.2' -PrefixLength 24 | Out-Null
    }
    $nat = Get-NetNat -Name 'AppleTvRamNat' -ErrorAction SilentlyContinue
    if ($nat -and $nat.InternalIPInterfaceAddressPrefix -ne '172.16.42.0/24') {
        throw 'AppleTvRamNat exists with an unexpected prefix; it was not modified.'
    }
    if (-not $nat) {
        Assert-NetworkAdministrator
        New-NetNat -Name 'AppleTvRamNat' -InternalIPInterfaceAddressPrefix '172.16.42.0/24' | Out-Null
    }
    Wait-TcpPort '172.16.42.1' 22 $StageTimeoutSeconds
    Write-Host 'USB NCM 172.16.42.2/24, NAT, and SSH port 22 are ready.'
}

function Assert-NetworkAdministrator {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run PowerShell as Administrator to create the missing USB NCM address or NAT. Existing network configuration can be reused without elevation.'
    }
}

function Assert-LinuxUsbIdentity {
    param([object[]]$Details)
    $composite = @($Details | Where-Object {
        $_.InstanceId -notmatch '(?i)&MI_\d{2}\\' -and $_.BusDescription -eq 'A1625 minimal Linux'
    })
    $ncm = @($Details | Where-Object {
        $_.InstanceId -match '(?i)&MI_00\\' -and $_.BusDescription -eq 'CDC NCM' -and $_.DriverService -eq 'UsbNcm'
    })
    $acm = @($Details | Where-Object {
        $_.InstanceId -match '(?i)&MI_02\\' -and $_.BusDescription -eq 'CDC Serial' -and $_.DriverService -eq 'usbser'
    })
    if ($composite.Count -ne 1 -or $ncm.Count -ne 1 -or $acm.Count -ne 1) {
        throw 'USB 05AC:4142 does not match the expected A1625 minimal Linux composite/NCM/ACM layout.'
    }
    $containers = @(@(
        $composite[0].ContainerId
        $ncm[0].ContainerId
        $acm[0].ContainerId
    ) | Select-Object -Unique)
    if ($containers.Count -ne 1 -or -not $containers[0]) {
        throw 'The Linux USB composite, NCM, and ACM interfaces do not share one container.'
    }
}

function Get-SerialHostKey {
    Write-Stage 'Per-boot SSH host-key trust through USB ACM'
    $serialDevices = @(Get-CimInstance Win32_SerialPort | Where-Object {
        $_.PNPDeviceID -match '(?i)^USB\\VID_05AC&PID_4142&MI_02\\'
    })
    if ($serialDevices.Count -ne 1 -or [string]$serialDevices[0].DeviceID -notmatch '^COM\d+$') {
        throw "Expected exactly one A1625 USB ACM COM port; found $($serialDevices.Count)."
    }
    $portName = [string]$serialDevices[0].DeviceID
    $port = [IO.Ports.SerialPort]::new($portName, 115200, 'None', 8, 'One')
    $port.NewLine = "`n"
    $port.ReadTimeout = 500
    $port.WriteTimeout = 1000
    $text = ''
    $endPattern = '(?m)^__A1625_KEY_END__\r?$'
    try {
        $port.Open()
        Start-Sleep -Milliseconds 250
        $port.DiscardInBuffer()
        $port.Write("`r`n")
        Start-Sleep -Milliseconds 600
        $port.Write("echo __A1625_KEY_BEGIN__; dropbearkey -y -f /run/dropbear_ed25519_host_key; echo __A1625_KEY_END__`r`n")
        $deadline = [DateTimeOffset]::Now.AddSeconds(8)
        while ([DateTimeOffset]::Now -lt $deadline -and $text -notmatch $endPattern) {
            Start-Sleep -Milliseconds 100
            $text += $port.ReadExisting()
        }
    }
    finally {
        if ($port.IsOpen) { $port.Close() }
        $port.Dispose()
    }
    if ($text -notmatch '(?m)^__A1625_KEY_BEGIN__\r?$' -or $text -notmatch $endPattern) {
        throw "Did not receive a complete host-key response from $portName."
    }
    $keyMatch = [regex]::Match($text, '(?m)^ssh-ed25519\s+([A-Za-z0-9+/]+={0,2})(?:\s+[^\r\n]*)?\r?$')
    $fingerprintMatch = [regex]::Match($text, 'Fingerprint:\s+(SHA256:[A-Za-z0-9+/]+)')
    if (-not $keyMatch.Success -or -not $fingerprintMatch.Success) {
        throw "Could not parse the Dropbear Ed25519 public key from $portName."
    }
    $blob = $keyMatch.Groups[1].Value
    $fingerprint = $fingerprintMatch.Groups[1].Value
    $computed = "ssh-ed25519 $blob" | & ssh-keygen.exe -lf -
    if ($LASTEXITCODE -ne 0 -or ($computed -join "`n") -notmatch [regex]::Escape($fingerprint)) {
        throw 'The independently computed Ed25519 fingerprint does not match the USB ACM response.'
    }

    $scan = @(& ssh-keyscan.exe -4 -T 5 -p 22 -t ed25519 172.16.42.1 2>$null)
    $scanLine = @($scan | Where-Object { $_ -match '^172\.16\.42\.1\s+ssh-ed25519\s+\S+$' })
    if ($scanLine.Count -gt 0 -and (($scanLine[0] -split '\s+')[2] -ne $blob)) {
        throw 'The network SSH key does not match the key obtained through USB ACM.'
    }
    if ($scanLine.Count -eq 0) {
        Write-Warning 'ssh-keyscan returned no key; trust remains anchored to the USB ACM public key.'
    }

    New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
    $knownHosts = Join-Path $stateRoot ('known_hosts_ram_{0}' -f [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss'))
    $next = "$knownHosts.next"
    Set-Content -LiteralPath $next -Value "172.16.42.1 ssh-ed25519 $blob" -Encoding ascii -NoNewline
    Move-Item -LiteralPath $next -Destination $knownHosts
    Write-Host "Verified $portName Dropbear key: $fingerprint"
    $knownHosts
}

function Wait-LinuxUsbIdentity {
    $deadline = [DateTimeOffset]::Now.AddSeconds($StageTimeoutSeconds)
    do {
        $items = @(Get-ProductDetails '4142')
        $unexpected = @($items | Where-Object {
            $_.BusDescription -and $_.BusDescription -notin @('A1625 minimal Linux', 'CDC NCM', 'CDC Serial')
        })
        if ($unexpected.Count) { throw 'Unexpected descriptor while waiting for the A1625 Linux USB interfaces.' }
        $descriptions = @($items | ForEach-Object { $_.BusDescription })
        if ('A1625 minimal Linux' -in $descriptions -and 'CDC NCM' -in $descriptions -and 'CDC Serial' -in $descriptions) {
            Assert-LinuxUsbIdentity -Details $items
            return $items
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTimeOffset]::Now -lt $deadline)
    throw 'The complete A1625 Linux composite/NCM/ACM layout did not appear before the timeout.'
}

if (-not $ConfirmRamBoot) {
    throw 'Pass -ConfirmRamBoot to confirm the temporary A1625 RAM-only boot. No persistent storage operation is implemented.'
}
if ($StartCodex -and $EnterShell) {
    throw 'Choose either -StartCodex or -EnterShell, not both.'
}
if (($EnableZram -or $RestoreRamState) -and $DevelopmentProfile -eq 'none') {
    throw '-EnableZram and -RestoreRamState require -DevelopmentProfile minimal or development.'
}

Assert-LocalPreflight
$preparedLayer = $null
if ($DevelopmentProfile -ne 'none') {
    Write-Stage 'Prepare and verify the selected immutable RAM tool layer'
    & $runtimeInstaller -PrepareOnly | Out-Null
    $preparedLayer = & $developmentInstaller -Profile $DevelopmentProfile -PrepareOnly
    if (-not $preparedLayer.BundlePath) { throw 'The development layer preflight did not return a bundle.' }
    if ($RestoreRamState) {
        & (Join-Path $repoRoot 'windows-native\ram-state\Test-A1625RamStateSnapshot.ps1') `
            -StateDirectory $RamStateDirectory -PayloadPath $payload -RuntimePath $preparedLayer.BundlePath | Out-Null
    }
}
if ($ValidateOnly) {
    Write-Host 'Validation-only mode completed; no USB transfer or network change was performed.'
    return
}

$ExpectedEcid = Resolve-ExpectedEcid
Write-Host 'Loaded the expected ECID from an explicit parameter or the private per-user device configuration.'

Import-Module $atvModule -Force
$linuxDevices = @(Get-ProductDetails '4142')
if ($BootProfile -ne 'baseline' -and $linuxDevices.Count -ne 0) {
    throw 'The experimental boot requires a fresh DFU/Pongo stage. Existing Linux was not replaced; enter DFU before retrying.'
}
if ($linuxDevices.Count -eq 0) {
    $pongoDevices = @(Get-ProductDetails '4141')
    if ($pongoDevices.Count -eq 0) {
        Write-Stage 'A1625 DFU/checkm8'
        $dfu = Confirm-LibusbK '1227' 'A1625 DFU device'
        $isYolo = ([string]$dfu.InstanceId -match '(?i)YOLO:')
        if (-not $isYolo) {
            $identityFailure = 'Failed to read DFU USB serial string descriptor|check callback rejected it'
            $phase1 = Invoke-BoundedProcess -FilePath $openra1n -ArgumentList @(
                '--confirm-a1625', '--expected-ecid', $ExpectedEcid
            ) -TimeoutSeconds $StageTimeoutSeconds -StopOnPattern "TRIGGER_HANDOFF|$identityFailure"
            if ($phase1.Output -match $identityFailure) {
                throw "DFU identity could not be verified during checkm8. Re-enter DFU before retrying. Logs: $($phase1.StdoutLog), $($phase1.StderrLog)"
            }
            if (-not $phase1.Matched -or $phase1.Output -notmatch 'TRIGGER_HANDOFF' -or
                $phase1.Output -notmatch 'Stage 0 succeeded') {
                throw "checkm8 did not reach the verified YOLO handoff. Logs: $($phase1.StdoutLog), $($phase1.StderrLog)"
            }
            Start-Sleep -Seconds 2
            $dfu = Confirm-LibusbK '1227' 'A1625 YOLO DFU device' -RequireYolo
        }
        else {
            Assert-DfuIdentity $dfu -RequireYolo
        }

        Write-Stage 'YOLO DFU to PongoOS'
        $phase2 = Invoke-BoundedProcess -FilePath $openra1n -ArgumentList @(
            '--upload-only', '--confirm-a1625', '--expected-ecid', $ExpectedEcid
        ) -TimeoutSeconds $StageTimeoutSeconds
        if ($phase2.ExitCode -ne 0 -or
            $phase2.Output -notmatch 'cpid=0x7000 yolo=yes' -or
            $phase2.Output -notmatch 'Pongo upload finished') {
            throw "PongoOS upload did not complete with the expected A1625/YOLO evidence. Logs: $($phase2.StdoutLog), $($phase2.StderrLog)"
        }
        $pongoDevices = @(Wait-ProductDetails '4141')
    }

    Write-Stage 'PongoOS to m1n1/Linux/initramfs'
    $pongo = Confirm-LibusbK '4141' 'A1625 PongoOS device'
    $pongoIdentity = [string]$pongo.InstanceId
    if ($pongoIdentity -notmatch '(?i)CPID:7000(?:_|\b)' -or
        $pongoIdentity -notmatch '(?i)BDID:34(?:_|\b)' -or
        $pongoIdentity -notmatch "(?i)ECID:$([regex]::Escape($ExpectedEcid))(?:_|\b)") {
        throw "PongoOS identity does not match the authorized A1625: $pongoIdentity"
    }
    $boot = Invoke-BoundedProcess -FilePath $uploader -ArgumentList @(
        'upload', $payload, '--libusb', $libusb, '--confirm-ram-boot'
    ) -TimeoutSeconds $StageTimeoutSeconds
    if ($boot.ExitCode -ne 0 -or $boot.Output -notmatch 'sent bootm to PongoOS') {
        throw "Linux RAM payload upload failed. Logs: $($boot.StdoutLog), $($boot.StderrLog)"
    }
    $linuxDevices = @(Wait-ProductDetails '4142')
}

$linuxDevices = @(Wait-LinuxUsbIdentity)
Configure-UsbNetwork
$knownHosts = Get-SerialHostKey

Write-Stage 'RAM Linux health verification'
$sshOptions = @(
    '-T', '-i', $sshKey,
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', ('UserKnownHostsFile=' + $knownHosts)
)
$healthCommand = 'set -eu; test "$(uname -m)" = aarch64; grep -q "^KernelPageSize:[[:space:]]*4 kB$" /proc/self/smaps; grep -q " / rootfs " /proc/mounts; awk ''NR > 1 && $1 ~ /^[0-9]+$/ && $4 !~ /^zram[0-9]+$/ { found=1 } END { exit found }'' /proc/partitions; echo a1625_ram_ready'
$health = & ssh.exe @sshOptions root@172.16.42.1 $healthCommand
if ($LASTEXITCODE -ne 0 -or ($health -join "`n") -notmatch 'a1625_ram_ready') {
    throw 'RAM Linux health verification failed; Codex was not restored.'
}
Write-Host 'Verified aarch64, 4 KiB pages, RAM rootfs, and no internal block device.'

Write-Stage 'Codex runtime and DPAPI authentication restore'
& $runtimeInstaller -KnownHostsPath $knownHosts -RestoreState:(-not $RestoreRamState)
if ($LASTEXITCODE -ne 0) { throw 'Codex RAM runtime restoration failed.' }

if ($DevelopmentProfile -ne 'none') {
    Write-Stage "RAM development tools: $DevelopmentProfile"
    $installedLayer = & $developmentInstaller -Profile $DevelopmentProfile -KnownHostsPath $knownHosts -SshKeyPath $sshKey -EnableZram:$EnableZram
    if ($installedLayer.BundleSha256 -ne $preparedLayer.BundleSha256) {
        throw 'The prepared tool layer changed during deployment; state restoration was stopped.'
    }
}
if ($RestoreRamState) {
    Write-Stage 'Restore the verified Windows-hosted RAM snapshot'
    & $ramStateRestorer -StateDirectory $RamStateDirectory -PayloadPath $payload `
        -RuntimePath $preparedLayer.BundlePath -SshKeyPath $sshKey -KnownHostsPath $knownHosts
}

Write-Host "`nA1625 RAM Linux and Codex are restored." -ForegroundColor Green
Write-Host "Per-boot known_hosts: $knownHosts"
if ($StartCodex) {
    & $codexStarter -KnownHostsPath $knownHosts
}
elseif ($EnterShell) {
    & $shellStarter -KnownHostsPath $knownHosts
}
else {
    Write-Host 'Open an interactive SSH shell (then type codex) with:'
    Write-Host "& `"$shellStarter`" -KnownHostsPath `"$knownHosts`""
    Write-Host 'Start Codex with:'
    Write-Host "& `"$codexStarter`" -KnownHostsPath `"$knownHosts`""
}
