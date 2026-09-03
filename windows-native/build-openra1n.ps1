[CmdletBinding()]
param(
    [string]$MsysRoot = "$env:USERPROFILE\scoop\apps\msys2\current",
    [Parameter(Mandatory)]
    [string]$PongoPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedPongoSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$upstream = Join-Path $workspace 'third_party\openra1n'
$windowsFork = Join-Path $workspace 'third_party\Palera1nWin'
$build = Join-Path $workspace 'artifacts\openra1n-build'
$output = Join-Path $workspace 'artifacts\openra1n-win'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'

$expectedUpstream = '4595a5333e4134ade77b43fb2259e880b85801ee'
$expectedWindowsFork = 'b62a087839048e4bc9a496519ccd7aca1df3246f'
$expectedUpstreamOrigin = 'https://github.com/mineek/openra1n.git'
$expectedWindowsForkOrigin = 'https://github.com/pwnapplehat/Palera1nWin.git'

foreach ($required in @($upstream, $windowsFork, $bash)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path is missing: $required"
    }
}

function Get-Revision([string]$Repository) {
    $revision = (& git -C $Repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read git revision: $Repository"
    }
    return $revision
}

function Assert-PinnedRepository(
    [string]$Repository,
    [string]$ExpectedRevision,
    [string]$ExpectedOrigin
) {
    $revision = Get-Revision $Repository
    if ($revision -ne $ExpectedRevision) {
        throw "Unexpected revision in ${Repository}: $revision"
    }

    $origin = (& git -C $Repository remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -ne $ExpectedOrigin) {
        throw "Unexpected origin in ${Repository}: $origin"
    }

    $status = @(& git -C $Repository status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) {
        throw "Source repository is not clean: $Repository"
    }

    return $revision
}

$upstreamRevision = Assert-PinnedRepository $upstream $expectedUpstream $expectedUpstreamOrigin
$windowsForkRevision = Assert-PinnedRepository $windowsFork $expectedWindowsFork $expectedWindowsForkOrigin

$resolvedPongo = (Resolve-Path -LiteralPath $PongoPath).Path
$actualPongoSha256 = (Get-FileHash -LiteralPath $resolvedPongo -Algorithm SHA256).Hash
if ($actualPongoSha256 -ne $ExpectedPongoSha256.ToUpperInvariant()) {
    throw "Pongo payload hash mismatch. Expected $ExpectedPongoSha256, got $actualPongoSha256"
}

New-Item -ItemType Directory -Force -Path $build, $output | Out-Null

Copy-Item -LiteralPath (Join-Path $upstream 'Makefile') -Destination $build -Force
Copy-Item -LiteralPath (Join-Path $upstream 'lz4') -Destination $build -Recurse -Force
Copy-Item -LiteralPath (Join-Path $upstream 'include') -Destination $build -Recurse -Force
Copy-Item -LiteralPath (Join-Path $upstream 'payloads') -Destination $build -Recurse -Force
Copy-Item -LiteralPath (Join-Path $windowsFork 'vendor\openra1n-win\openra1n.c.hardened') `
    -Destination (Join-Path $build 'openra1n.c') -Force

$generatedSource = Join-Path $build 'openra1n.c'
$sourceText = Get-Content -LiteralPath $generatedSource -Raw
$blankBufferPattern = "void\* blank\[DFU_MAX_TRANSFER_SZ\];\r?\n\tmemset\(&blank, '\\0', DFU_MAX_TRANSFER_SZ\);"
$sourcePatches = [ordered]@{
    'DFU blank buffer type/initialization' = [regex]::IsMatch($sourceText, $blankBufferPattern)
    'Standards-compliant byte offset' = $sourceText.Contains('(unsigned char*)&out[len]')
    'LZ4 input signedness' = $sourceText.Contains('LZ4_compress_HC(payloads_Pongo_bin, out, len, out_len_, LZ4HC_CLEVEL_MAX)')
    'Remove unused pwnd_str' = $sourceText.Contains('static const char *pwnd_str = " YOLO:checkra1n";')
    'A1625 T7000 pre-exploit gate' = $sourceText.Contains('if(cpid != 0) {')
    'Reset target state on every enumeration' = $sourceText.Contains("static bool`r`ncheckm8_check_usb_device(usb_handle_t *handle, void *pwned) {") -or $sourceText.Contains("static bool`ncheckm8_check_usb_device(usb_handle_t *handle, void *pwned) {")
    'Require expected ECID CLI binding' = $sourceText.Contains('static uint16_t cpid;') -and $sourceText.Contains('int main(int argc, char **argv) {')
}
foreach ($entry in $sourcePatches.GetEnumerator()) {
    if (-not $entry.Value) {
        throw "Expected source patch location was not found: $($entry.Key)"
    }
}
$sourceText = [regex]::Replace($sourceText, $blankBufferPattern, 'uint8_t blank[DFU_MAX_TRANSFER_SZ] = {0};')
$sourceText = $sourceText.Replace('(unsigned char*)&out[len]', '(unsigned char*)out + len')
$sourceText = $sourceText.Replace(
    'LZ4_compress_HC(payloads_Pongo_bin, out, len, out_len_, LZ4HC_CLEVEL_MAX)',
    'LZ4_compress_HC((const char*)payloads_Pongo_bin, out, len, out_len_, LZ4HC_CLEVEL_MAX)'
)
$sourceText = [regex]::Replace($sourceText, 'static const char \*pwnd_str = " YOLO:checkra1n";\r?\n', '')
$ecidHelpers = @'
static const char *expected_ecid;

static bool
is_hex_string(const char *value) {
	size_t i, n;
	if(value == NULL || (n = strlen(value)) == 0 || n > 16) return false;
	for(i = 0; i < n; i++) {
		char c = value[i];
		if(!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
	}
	return true;
}

static bool
serial_has_expected_ecid(const char *serial) {
	const char *found;
	size_t i, n;
	if(serial == NULL || expected_ecid == NULL) return false;
	found = strstr(serial, "ECID:");
	if(found == NULL) return false;
	found += 5;
	n = strlen(expected_ecid);
	for(i = 0; i < n; i++) {
		char a = found[i], b = expected_ecid[i];
		if(a >= 'a' && a <= 'f') a = (char)(a - 'a' + 'A');
		if(b >= 'a' && b <= 'f') b = (char)(b - 'a' + 'A');
		if(a != b) return false;
	}
	return found[n] == '\0' || found[n] == ' ';
}
'@
$sourceText = $sourceText.Replace('static uint16_t cpid;', "static uint16_t cpid;`n$ecidHelpers")
$callbackPattern = '(checkm8_check_usb_device\(usb_handle_t \*handle, void \*pwned\) \{\r?\n)(\tchar \*usb_serial_num)'
if ([regex]::Matches($sourceText, $callbackPattern).Count -ne 1) {
    throw 'Expected exactly one checkm8 target callback.'
}
$sourceText = [regex]::Replace(
    $sourceText,
    $callbackPattern,
    '$1' + "`tcpid = 0; /* Fail closed: never reuse a previous enumeration's target. */`n" + '$2'
)
$yoloFallbackNeedle = "`t`tif(cpid == 0 && strstr(usb_serial_num, `"CPID:8015`") != NULL) {"
if (-not $sourceText.Contains($yoloFallbackNeedle)) {
    throw 'Expected the existing YOLO CPID fallback location.'
}
$t7000YoloFallback = @'
		if(cpid == 0 && strstr(usb_serial_num, "CPID:7000") != NULL && serial_has_yolo(usb_serial_num)) {
			/* YOLO removes SRTG; accept only the exploited T7000 form. ECID is checked below. */
			cpid = 0x7000;
			LOG_INFO("Mapped CPID:7000 from YOLO serial (SRTG absent)");
		}
'@
$sourceText = $sourceText.Replace($yoloFallbackNeedle, $t7000YoloFallback + "`n" + $yoloFallbackNeedle)
$targetGate = @'
		if(cpid != 0 && cpid != 0x7000) {
			LOG_ERROR("Safety gate: refusing non-A1625/T7000 DFU target (cpid=0x%x)", cpid);
			cpid = 0;
		}
		if(cpid == 0x7000 && !serial_has_expected_ecid(usb_serial_num)) {
			LOG_ERROR("Safety gate: refusing T7000 whose ECID does not match --expected-ecid");
			cpid = 0;
		}
		if(cpid != 0) {
'@
$sourceText = $sourceText.Replace("`t`tif(cpid != 0) {", $targetGate)
$mainVarsPattern = '(int main\(int argc, char \*\*argv\) \{\r?\n\tint upload_only = 0;\r?\n)(\tint ai;)'
if ([regex]::Matches($sourceText, $mainVarsPattern).Count -ne 1) {
    throw 'Expected exactly one openra1n main variable block.'
}
$sourceText = [regex]::Replace($sourceText, $mainVarsPattern, '$1' + "`tint confirm_a1625 = 0;`n" + '$2')

$argumentPattern = '(?s)(\tfor \(ai = 1; ai < argc; ai\+\+\) \{\r?\n\t\tif \(strcmp\(argv\[ai\], "--upload-only"\) == 0 \|\| strcmp\(argv\[ai\], "-u"\) == 0\) \{\r?\n\t\t\tupload_only = 1;\r?\n)(\t\t\}\r?\n\t\}\r?\n)'
if ([regex]::Matches($sourceText, $argumentPattern).Count -ne 1) {
    throw 'Expected exactly one openra1n argument parser.'
}
$argumentTail = @'
		} else if (strcmp(argv[ai], "--confirm-a1625") == 0) {
			confirm_a1625 = 1;
		} else if (strcmp(argv[ai], "--expected-ecid") == 0 && ai + 1 < argc) {
			expected_ecid = argv[++ai];
		} else {
			LOG_ERROR("Unknown or incomplete argument: %s", argv[ai]);
			return EXIT_FAILURE;
		}
	}
	if (!confirm_a1625 || !is_hex_string(expected_ecid)) {
		LOG_ERROR("Refusing to start: require --confirm-a1625 --expected-ecid <1-16 hex digits>");
		return EXIT_FAILURE;
	}
'@
$sourceText = [regex]::Replace($sourceText, $argumentPattern, '$1' + $argumentTail + "`n")
if (-not $sourceText.Contains('confirm_a1625 = 1;') -or -not $sourceText.Contains('cpid = 0; /* Fail closed')) {
    throw 'Failed to verify the A1625/ECID safety-gate patch.'
}
Set-Content -LiteralPath $generatedSource -Value $sourceText -Encoding utf8NoBOM

Copy-Item -LiteralPath $resolvedPongo -Destination (Join-Path $build 'payloads\Pongo.bin') -Force

$buildPosix = (& $bash -lc 'cygpath -u "$1"' 'atv-build' $build).Trim()
if ($LASTEXITCODE -ne 0 -or -not $buildPosix) {
    throw 'Unable to convert the build path for MSYS2.'
}

$buildCommand = "set -euo pipefail; export PATH=/ucrt64/bin:/usr/bin; cd '$buildPosix'; rm -f openra1n.exe; make clean; make payloads; gcc -I./include -Wall -Wextra -Werror -Os -DHAVE_LIBUSB openra1n.c lz4/lz4.c lz4/lz4hc.c -lusb-1.0 -o openra1n.exe; strip openra1n.exe"
& $bash -lc $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "openra1n build failed with exit code $LASTEXITCODE"
}

$builtExe = Join-Path $build 'openra1n.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw 'Build completed without producing openra1n.exe.'
}

$destination = Join-Path $output 'openra1n.exe'
Copy-Item -LiteralPath $builtExe -Destination $destination -Force
$libusbSource = Join-Path $MsysRoot 'ucrt64\bin\libusb-1.0.dll'
if (-not (Test-Path -LiteralPath $libusbSource)) {
    throw "MSYS2 libusb runtime is missing: $libusbSource"
}
$libusbDestination = Join-Path $output 'libusb-1.0.dll'
Copy-Item -LiteralPath $libusbSource -Destination $libusbDestination -Force

$manifest = [ordered]@{
    BuiltAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    Openra1nRevision = $upstreamRevision
    WindowsForkRevision = $windowsForkRevision
    HardenedSourceSha256 = (Get-FileHash (Join-Path $build 'openra1n.c') -Algorithm SHA256).Hash
    PongoSha256 = $actualPongoSha256
    ExecutableSha256 = (Get-FileHash $destination -Algorithm SHA256).Hash
    LibusbSha256 = (Get-FileHash $libusbDestination -Algorithm SHA256).Hash
    ExecutablePath = $destination
    AppliedSafetyPatches = @($sourcePatches.Keys)
    DeviceExecutionAuthorized = $false
    TargetGate = 'CPID 0x7000 (AppleTV5,3/T7000) before checkm8 stages'
    Note = 'Host build only. A matching CPID is necessary but not sufficient: do not execute until the payload and physical-device identity are approved.'
}

$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'build-manifest.json') -Encoding utf8
$manifest
