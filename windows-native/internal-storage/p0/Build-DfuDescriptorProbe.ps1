[CmdletBinding()]
param(
    [string]$MsysRoot = "$env:USERPROFILE\scoop\apps\msys2\current",
    [string]$LibusbDll = (Join-Path $PSScriptRoot '..\..\..\artifacts\openra1n-win\libusb-1.0.dll')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$source = Join-Path $PSScriptRoot 'dfu_descriptor_probe.c'
$output = Join-Path $root 'artifacts\p0-usb\dfu-descriptor-probe'
$exe = Join-Path $output 'dfu_descriptor_probe.exe'
$dll = Join-Path $output 'libusb-1.0.dll'
$manifest = Join-Path $output 'build-manifest.json'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'

foreach ($path in @($source, $LibusbDll, $bash)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build input: $path" }
}
$text = Get-Content -LiteralPath $source -Raw
foreach ($forbidden in @('libusb_set_configuration', 'libusb_claim_interface',
                          'libusb_reset_device', 'LIBUSB_ENDPOINT_OUT')) {
    if ($text.Contains($forbidden)) { throw "Read-only probe contains forbidden API/token: $forbidden" }
}
if (($text.Split('libusb_control_transfer(').Count - 1) -ne 1 -or
    -not $text.Contains('uint8_t bytes[18]') -or
    -not $text.Contains('sizeof(bytes), 500')) {
    throw 'Read-only probe must contain exactly one bounded 18-byte control transfer.'
}

New-Item -ItemType Directory -Force -Path $output | Out-Null
$sourcePosix = (& $bash -lc 'cygpath -u "$1"' probe-build $source).Trim()
$exePosix = (& $bash -lc 'cygpath -u "$1"' probe-build $exe).Trim()
if (-not $sourcePosix -or -not $exePosix) { throw 'cygpath failed' }
& $bash -lc 'export PATH=/ucrt64/bin:/usr/bin; gcc -std=c11 -Wall -Wextra -Werror "$1" -lusb-1.0 -o "$2"' probe-build $sourcePosix $exePosix
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'Probe build failed' }
Copy-Item -LiteralPath $LibusbDll -Destination $dll -Force

$record = [ordered]@{
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    source = $source
    source_sha256 = (Get-FileHash $source -Algorithm SHA256).Hash
    executable = $exe
    executable_sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash
    libusb_sha256 = (Get-FileHash $dll -Algorithm SHA256).Hash
    allowed_operation = 'one standard control-IN 18-byte device descriptor read'
    timeout_ms = 500
    configuration_changes = 0
    interface_claims = 0
    usb_resets = 0
    control_out_requests = 0
    checkm8_stages = 0
}
$record | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding utf8
$record
