#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FirmwarePath,

    [Parameter(Mandatory)]
    [string]$RegDbPath,

    [string]$RegDbSigPath,

    [string]$RepoRoot = (Get-Location).Path,

    [string]$AppleTvAddress = '172.16.42.1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

$ModulePath = Join-Path $RepoRoot 'artifacts\wifi-pmu-probe\a1625_pcie_domains.ko'
$RunnerPath = Join-Path $RepoRoot 'artifacts\wifi-pmu-probe\run_probe_once'
$HoldScript = Join-Path $RepoRoot 'windows-native\wifi\hold-wifi-session.sh'
$SshKeyPath = Join-Path $RepoRoot 'artifacts\ssh\a1625_ram_ed25519'
$StateModule = Join-Path $RepoRoot 'windows-native\codex-state\A1625CodexState.psm1'

Import-Module $StateModule -Force

foreach ($path in @(
    $ModulePath,
    $RunnerPath,
    $HoldScript,
    $SshKeyPath,
    $FirmwarePath,
    $RegDbPath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}

if ($RegDbSigPath -and -not (Test-Path -LiteralPath $RegDbSigPath -PathType Leaf)) {
    throw "regulatory.db.p7s not found: $RegDbSigPath"
}

$ExpectedFirmwareHash =
    '5691D1E0CEB70BAF18EFB7A0EC6CB84FEB9EDD2D0700C525B42930C4E7E4B845'

$FirmwareHash = (Get-FileHash -LiteralPath $FirmwarePath -Algorithm SHA256).Hash
Write-Host "Firmware SHA256: $FirmwareHash"

if ($FirmwareHash -ne $ExpectedFirmwareHash) {
    throw @"
Firmware hash does not match the validated BCM4350 firmware.

Expected:
$ExpectedFirmwareHash

Actual:
$FirmwareHash
"@
}

$ModuleHash = (Get-FileHash -LiteralPath $ModulePath -Algorithm SHA256).Hash
Write-Host "Wi-Fi module SHA256: $ModuleHash"

$AcceptedModuleHash =
    'D8E545E0AF7CD7ADE10E2AC9157A1E0C8983B4563B28B9709BD3DC2A89DC2109'

if ($ModuleHash -ne $AcceptedModuleHash) {
    Write-Warning @"
a1625_pcie_domains.ko differs from the module recorded in the
2026-09-09 acceptance test.

Acceptance hash:
$AcceptedModuleHash

Current hash:
$ModuleHash

If this module was intentionally rebuilt, verify it was built against
the exact prepared wifi-t7000-leaf kernel and matching vmlinux.symvers.
"@
}

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

Write-Host "Known hosts: $($KnownHosts.FullName)"

$SshArguments = @(
    Get-A1625SshArguments `
        -SshKeyPath $SshKeyPath `
        -KnownHostsPath $KnownHosts.FullName
)

Write-Host 'Checking USB SSH...'
& ssh.exe -F none @SshArguments `
    "root@$AppleTvAddress" `
    'set -e; printf "usb_ssh=passed\n"; uname -m; if command -v getconf >/dev/null 2>&1; then getconf PAGESIZE; else echo "getconf=not_available"; fi'

if ($LASTEXITCODE -ne 0) {
    throw 'USB SSH failed.'
}

& ssh.exe -F none @SshArguments `
    "root@$AppleTvAddress" `
    'set -eu; umask 077; mkdir -p /run/a1625-wifi /lib/firmware/brcm'

if ($LASTEXITCODE -ne 0) {
    throw 'Failed to create RAM staging directories.'
}

function Send-A1625Binary {
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$RemotePath,

        [string]$Mode = '600'
    )

    $fullPath = (Resolve-Path -LiteralPath $LocalPath).ProviderPath
    $localHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash

    Write-Host ''
    Write-Host "Uploading: $fullPath"
    Write-Host "       -> $RemotePath"

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    try {
        $result = Invoke-A1625SshUpload `
            -SshArguments $SshArguments `
            -AppleTvAddress $AppleTvAddress `
            -RemoteCommand "set -eu; umask 077; cat > '$RemotePath'; chmod $Mode '$RemotePath'; sha256sum '$RemotePath'" `
            -Payload $bytes `
            -TimeoutSeconds 180
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }

    $remoteHash = (($result -split '\s+')[0]).ToUpperInvariant()

    if ($remoteHash -ne $localHash) {
        throw @"
SHA256 mismatch after upload.

Local:
$localHash

Remote:
$remoteHash

File:
$RemotePath
"@
    }

    Write-Host "SHA256 verified: $remoteHash"
}

function Send-A1625ShellScript {
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$RemotePath
    )

    $fullPath = (Resolve-Path -LiteralPath $LocalPath).ProviderPath
    $text = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
    $text = $text -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()

    try {
        $localHash = [Convert]::ToHexString($sha.ComputeHash($bytes))

        Write-Host ''
        Write-Host "Uploading script: $fullPath"
        Write-Host "            -> $RemotePath"

        $result = Invoke-A1625SshUpload `
            -SshArguments $SshArguments `
            -AppleTvAddress $AppleTvAddress `
            -RemoteCommand "set -eu; umask 077; cat > '$RemotePath'; chmod 700 '$RemotePath'; sh -n '$RemotePath'; sha256sum '$RemotePath'" `
            -Payload $bytes `
            -TimeoutSeconds 180

        $remoteHash = (($result -split '\s+')[0]).ToUpperInvariant()

        if ($remoteHash -ne $localHash) {
            throw "SHA256 mismatch for $RemotePath"
        }

        Write-Host 'Shell syntax OK'
        Write-Host "SHA256 verified: $remoteHash"
    }
    finally {
        $sha.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

Send-A1625Binary `
    -LocalPath $ModulePath `
    -RemotePath '/run/a1625_hold.ko' `
    -Mode '600'

Send-A1625Binary `
    -LocalPath $RunnerPath `
    -RemotePath '/run/run_probe_once' `
    -Mode '700'

Send-A1625Binary `
    -LocalPath $FirmwarePath `
    -RemotePath '/lib/firmware/brcm/brcmfmac4350-pcie.bin' `
    -Mode '644'

Send-A1625Binary `
    -LocalPath $RegDbPath `
    -RemotePath '/lib/firmware/regulatory.db' `
    -Mode '644'

if ($RegDbSigPath) {
    Send-A1625Binary `
        -LocalPath $RegDbSigPath `
        -RemotePath '/lib/firmware/regulatory.db.p7s' `
        -Mode '644'
}

Send-A1625ShellScript `
    -LocalPath $HoldScript `
    -RemotePath '/run/a1625-wifi/hold.sh'

Write-Host ''
Write-Host 'Wi-Fi hardware staging completed successfully.'
