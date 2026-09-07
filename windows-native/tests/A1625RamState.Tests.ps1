$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Import-Module (Join-Path $repoRoot 'windows-native\ram-state\A1625RamState.psm1') -Force
$failures = [Collections.Generic.List[string]]::new()

function Assert-True { param([bool]$Condition, [string]$Name) if (-not $Condition) { $failures.Add("FAIL $Name") } else { Write-Output "PASS $Name" } }
function Assert-Throws { param([scriptblock]$Action, [string]$Name) try { & $Action; $failures.Add("FAIL $Name (did not throw)") } catch { Write-Output "PASS $Name" } }
function Set-TarText { param([byte[]]$Header, [int]$Offset, [int]$Length, [string]$Value) $bytes = [Text.Encoding]::ASCII.GetBytes($Value); if ($bytes.Length -gt $Length) { throw "Tar field is too long: $Value" }; [Array]::Copy($bytes, 0, $Header, $Offset, $bytes.Length) }
function ConvertTo-TarOctal { param([int64]$Value) [Convert]::ToString($Value, 8) }
function Set-TarOctal { param([byte[]]$Header, [int]$Offset, [int]$Length, [int64]$Value) Set-TarText $Header $Offset $Length ((ConvertTo-TarOctal $Value).PadLeft($Length - 1, '0') + [char]0) }
function New-TarGzip {
    param([object[]]$Entries)
    $tar = [IO.MemoryStream]::new()
    foreach ($entry in $Entries) {
        $data = [byte[]]::new(0)
        if ($null -ne $entry.Data) { $data = [byte[]]$entry.Data }
        $header = New-Object byte[] 512
        $prefix = if ($entry.PSObject.Properties['Prefix']) { $entry.Prefix } else { $null }
        $mode = if ($entry.PSObject.Properties['Mode']) { $entry.Mode } else { 420 }
        $size = if ($entry.PSObject.Properties['Size']) { $entry.Size } else { $data.Length }
        $type = if ($entry.PSObject.Properties['Type']) { $entry.Type } else { '0' }
        Set-TarText $header 0 100 $entry.Name
        if ($prefix) { Set-TarText $header 345 155 $prefix }
        Set-TarOctal $header 100 8 ([int64]$mode)
        Set-TarOctal $header 124 12 ([int64]$size)
        Set-TarOctal $header 136 12 0
        for ($index = 148; $index -lt 156; $index++) { $header[$index] = 0x20 }
        $header[156] = [byte][char]$type
        Set-TarText $header 257 6 'ustar'
        $checksum = 0; foreach ($byte in $header) { $checksum += $byte }
        Set-TarText $header 148 8 ((ConvertTo-TarOctal $checksum).PadLeft(6, '0') + [char]0 + ' ')
        $tar.Write($header, 0, 512)
        if ($data.Length) { $tar.Write($data, 0, $data.Length) }
        $padding = (512 - ($data.Length % 512)) % 512
        if ($padding) { $tar.Write((New-Object byte[] $padding), 0, $padding) }
    }
    $tar.Write((New-Object byte[] 1024), 0, 1024)
    $result = [IO.MemoryStream]::new(); $gzip = [IO.Compression.GZipStream]::new($result, [IO.Compression.CompressionMode]::Compress, $true)
    try { $tar.Position = 0; $tar.CopyTo($gzip) } finally { $gzip.Dispose(); $tar.Dispose() }
    try { $result.ToArray() } finally { $result.Dispose() }
}

$validArchive = New-TarGzip @(
    [pscustomobject]@{ Name='run/work'; Type='5'; Data=$null },
    [pscustomobject]@{ Name='run/work/hello.txt'; Type='0'; Data=[Text.Encoding]::UTF8.GetBytes('hello') },
    [pscustomobject]@{ Name='run/codex-home/auth.json'; Type='0'; Data=[Text.Encoding]::UTF8.GetBytes('{"ok":true}') }
)
Assert-True ((Assert-A1625SafeTar $validArchive) -eq 3) 'valid gzip tar archive is accepted'
Assert-True (-not (Test-A1625ArchivePath 'run/workevil/file')) 'allowlist rejects run/workevil prefix bypass'
Assert-True (-not (Test-A1625ArchivePath 'run/work/../etc/shadow')) 'archive traversal is rejected'
Assert-True (-not (Test-A1625ArchivePath 'run/work/./file')) 'archive dot segment is rejected'
Assert-Throws { Assert-A1625SafeTar (New-TarGzip @([pscustomobject]@{ Name='evil'; Prefix='run/workevil'; Type='0'; Data=[byte[]](1) })) } 'prefix field cannot bypass work allowlist'
Assert-Throws { Assert-A1625SafeTar (New-TarGzip @([pscustomobject]@{ Name='run/work/duplicate'; Type='0'; Data=[byte[]](1) },[pscustomobject]@{ Name='run/work/duplicate/'; Type='5'; Data=$null })) } 'normalized duplicate archive paths are rejected'
Assert-Throws { Assert-A1625SafeTar (New-TarGzip @([pscustomobject]@{ Name='run/work/link'; Type='2'; Data=$null })) } 'symbolic-link entry is rejected'
Assert-Throws { Assert-A1625SafeTar (New-TarGzip @([pscustomobject]@{ Name='run/work/oversize'; Type='0'; Size=67108865; Data=$null })) } 'expanded-size limit is enforced'

$badChecksum = [byte[]]$validArchive; $badChecksum[$badChecksum.Length - 9] = $badChecksum[$badChecksum.Length - 9] -bxor 1
Assert-Throws { Assert-A1625SafeTar $badChecksum } 'gzip or tar checksum corruption is rejected'
Assert-Throws { Assert-A1625SafeTar (New-TarGzip @([pscustomobject]@{ Name='run/work/setuid'; Type='0'; Mode=2541; Data=[byte[]](1) })) } 'unsafe setuid tar mode is rejected'

$fingerprint = [ordered]@{ payloadSha256=('A' * 64); runtimeSha256=('B' * 64) }
$envelope = ConvertTo-A1625RamEnvelope -Archive $validArchive -Fingerprint $fingerprint -Entries 3
$decoded = ConvertFrom-A1625RamEnvelope -Plain $envelope -Fingerprint $fingerprint
Assert-True ((Get-A1625Sha256 $decoded.Archive) -eq (Get-A1625Sha256 $validArchive)) 'envelope round trip preserves archive'
$wrongFingerprint = [ordered]@{ payloadSha256=('C' * 64); runtimeSha256=('B' * 64) }
Assert-Throws { ConvertFrom-A1625RamEnvelope -Plain $envelope -Fingerprint $wrongFingerprint } 'envelope rejects immutable fingerprint mismatch'
$tamperedText = [Text.Encoding]::UTF8.GetString($envelope) -replace '"archiveSha256":"[A-F0-9]+"', ('"archiveSha256":"' + ('0' * 64) + '"')
Assert-Throws { ConvertFrom-A1625RamEnvelope -Plain ([Text.Encoding]::UTF8.GetBytes($tamperedText)) -Fingerprint $fingerprint } 'envelope rejects archive hash tampering'
$badFileManifest = [Text.Encoding]::UTF8.GetString($envelope) -replace '"sha256":"[A-F0-9]{64}"', ('"sha256":"' + ('0' * 64) + '"')
Assert-Throws { ConvertFrom-A1625RamEnvelope -Plain ([Text.Encoding]::UTF8.GetBytes($badFileManifest)) -Fingerprint $fingerprint } 'envelope rejects malformed per-file manifest'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('a1625-ram-state-test-' + [guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $payloadPath = Join-Path $testRoot 'payload.bin'; $runtimePath = Join-Path $testRoot 'runtime.bin'
    [IO.File]::WriteAllBytes($payloadPath, [byte[]](1,2,3)); [IO.File]::WriteAllBytes($runtimePath, [byte[]](4,5,6))
    $diskFingerprint = Get-A1625RuntimeFingerprint $payloadPath $runtimePath
    $diskEnvelope = ConvertTo-A1625RamEnvelope -Archive $validArchive -Fingerprint $diskFingerprint -Entries 3
    $cipher = [Security.Cryptography.ProtectedData]::Protect($diskEnvelope, (Get-A1625RamStateEntropy), [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        $name = 'state-' + (Get-A1625Sha256 $cipher).Substring(0, 32) + '.dpapi'
        [IO.File]::WriteAllBytes((Join-Path $testRoot $name), $cipher); [IO.File]::WriteAllText((Join-Path $testRoot 'current'), $name, [Text.Encoding]::ASCII)
        $preflight = Test-A1625RamStateSnapshot -StateDirectory $testRoot -PayloadPath $payloadPath -RuntimePath $runtimePath
        Assert-True ($preflight.Valid -and $preflight.ArchiveEntries -eq 3) 'DPAPI current generation validates end-to-end'
        [IO.File]::WriteAllText((Join-Path $testRoot 'current'), 'state-00000000000000000000000000000000.dpapi', [Text.Encoding]::ASCII)
        Assert-Throws { Test-A1625RamStateSnapshot -StateDirectory $testRoot -PayloadPath $payloadPath -RuntimePath $runtimePath } 'missing pointed generation is rejected'
    } finally { [Array]::Clear($cipher,0,$cipher.Length); [Array]::Clear($diskEnvelope,0,$diskEnvelope.Length) }
} finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }

if ($failures.Count) { $failures | Write-Error; exit 1 }
Write-Output 'All A1625 RAM-state behavioral tests passed.'
