Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$codexModule = Join-Path $PSScriptRoot '..\codex-state\A1625CodexState.psm1'
Import-Module $codexModule -Force

function Get-A1625RamStateEntropy { [Text.Encoding]::UTF8.GetBytes('AppleTvA1625-RamState-v1') }
function Get-A1625Sha256 { param([byte[]]$Bytes) [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function ConvertTo-A1625RamEnvelope {
    param([Parameter(Mandatory)][byte[]]$Archive,[Parameter(Mandatory)]$Fingerprint,[Parameter(Mandatory)][int]$Entries)
    $details = Assert-A1625SafeTar $Archive -Detailed
    if ($Entries -ne $details.Entries) { throw 'Archive entry count mismatch' }
    [Text.Encoding]::UTF8.GetBytes(([ordered]@{format='a1625-ram-state-envelope-v2';savedAtUtc=[DateTime]::UtcNow.ToString('o');fingerprint=$Fingerprint;archiveSha256=Get-A1625Sha256 $Archive;archiveGzipBytes=$Archive.Length;archiveEntries=$Entries;expandedBytes=$details.ExpandedBytes;tarBytes=$details.TarBytes;files=$details.Files;archiveBase64=[Convert]::ToBase64String($Archive)}|ConvertTo-Json -Compress -Depth 6))
}
function ConvertFrom-A1625RamEnvelope {
    param([Parameter(Mandatory)][byte[]]$Plain,[Parameter(Mandatory)]$Fingerprint)
    $e=[Text.Encoding]::UTF8.GetString($Plain)|ConvertFrom-Json
    if($e.format -ne 'a1625-ram-state-envelope-v2' -or $e.fingerprint.payloadSha256 -ne $Fingerprint.payloadSha256 -or $e.fingerprint.runtimeSha256 -ne $Fingerprint.runtimeSha256){throw 'Snapshot envelope does not match immutable inputs'}
    $archive=[Convert]::FromBase64String($e.archiveBase64)
    if((Get-A1625Sha256 $archive) -ne $e.archiveSha256 -or $archive.Length -ne $e.archiveGzipBytes){throw 'Snapshot archive hash or size mismatch'}
    $details=Assert-A1625SafeTar $archive -Detailed
    if ($details.Entries -ne $e.archiveEntries -or $details.ExpandedBytes -ne $e.expandedBytes -or $details.TarBytes -ne $e.tarBytes -or
        (ConvertTo-Json -InputObject @($details.Files) -Depth 4 -Compress) -cne (ConvertTo-Json -InputObject @($e.files) -Depth 4 -Compress)) { throw 'Snapshot file manifest mismatch' }
    [pscustomobject]@{Envelope=$e;Archive=$archive;Details=$details}
}
function Get-A1625FileHashStrict {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required immutable input was not found: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Get-A1625RuntimeFingerprint {
    param([Parameter(Mandatory)][string]$PayloadPath, [Parameter(Mandatory)][string]$RuntimePath)
    $runtimeIdentity = @(
        (Get-A1625FileHashStrict $RuntimePath),
        (Get-A1625FileHashStrict (Join-Path $PSScriptRoot '../development-tools/Install-A1625DevelopmentTools.ps1')),
        (Get-A1625FileHashStrict (Join-Path $PSScriptRoot '../codex-runtime/Install-CodexRamRuntime.ps1')),
        (Get-A1625FileHashStrict (Join-Path $PSScriptRoot '../codex-runtime/codex-ram'))
    ) -join ':'
    [ordered]@{ payloadSha256 = Get-A1625FileHashStrict $PayloadPath; runtimeSha256 = Get-A1625Sha256 ([Text.Encoding]::ASCII.GetBytes($runtimeIdentity)) }
}
function Test-A1625RamStateSnapshot {
    param([Parameter(Mandatory)][string]$StateDirectory,[Parameter(Mandatory)][string]$PayloadPath,[Parameter(Mandatory)][string]$RuntimePath)
    $pointer=Join-Path $StateDirectory 'current'; if(-not (Test-Path $pointer -PathType Leaf)){throw 'RAM snapshot generation pointer is missing'}
    $name=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pointer)).Trim(); if($name -notmatch '^state-[A-F0-9]{32}\.dpapi$'){throw 'Invalid RAM snapshot generation pointer'}
    $cipherPath=Join-Path $StateDirectory $name; if(-not (Test-Path $cipherPath -PathType Leaf)){throw 'RAM snapshot generation is missing'}; $fp=Get-A1625RuntimeFingerprint $PayloadPath $RuntimePath
    if ((Get-Item -LiteralPath $cipherPath).Length -gt 400MB) { throw 'Encrypted snapshot exceeds its size limit' }
    $cipher=[IO.File]::ReadAllBytes($cipherPath); try {
        if ($name -cne ('state-' + (Get-A1625Sha256 $cipher).Substring(0,32) + '.dpapi')) { throw 'Encrypted generation hash mismatch' }
        $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,(Get-A1625RamStateEntropy),[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $decoded=$null
        try {
            $decoded=ConvertFrom-A1625RamEnvelope $plain $fp
            [pscustomobject]@{ Valid=$true; ArchiveGzipBytes=[int64]$decoded.Envelope.archiveGzipBytes; ArchiveEntries=[int]$decoded.Envelope.archiveEntries; ExpandedBytes=$decoded.Details.ExpandedBytes; TarBytes=$decoded.Details.TarBytes }
        } finally {
            if ($decoded) { [Array]::Clear($decoded.Archive,0,$decoded.Archive.Length) }
            [Array]::Clear($plain,0,$plain.Length)
        }
    } finally {[Array]::Clear($cipher,0,$cipher.Length)}
}
function Test-A1625ArchivePath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -match '[\\\x00-\x1f\x7f]' -or $Path -match '(^|/)\.{1,2}(/|$)' -or $Path.Contains('//')) { return $false }
    $Path -cmatch '^(?:run/work(?:/.*)?|run/codex-home/(?:auth\.json|config\.toml|\.ssh/(?:config|known_hosts|id_ed25519|id_ed25519\.pub)|\.gitconfig))$'
}
function Assert-A1625SafeTar {
    param([Parameter(Mandatory)][byte[]]$GzipBytes, [switch]$Detailed)
    if ($GzipBytes.Length -gt 256MB) { throw 'Compressed snapshot exceeds 256 MiB' }
    $input = [IO.MemoryStream]::new($GzipBytes, $false); $gzip = [IO.Compression.GZipStream]::new($input,[IO.Compression.CompressionMode]::Decompress)
    try {
        $header = New-Object byte[] 512; $entries = 0; [int64]$expanded = 0
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $files = [Collections.Generic.List[object]]::new()
        [int64]$tarBytes = 0
        while ($true) {
            $offset=0; while ($offset -lt 512) { $n=$gzip.Read($header,$offset,512-$offset); if($n -le 0){throw 'Truncated tar header'}; $offset += $n }
            $tarBytes += 512
            if (@($header | Where-Object { $_ -ne 0 }).Count -eq 0) {
                # Consume the terminator and trailer, enforcing the gzip CRC and
                # rejecting hidden entries after an early end-of-archive marker.
                $tail = New-Object byte[] 8192
                [int64]$tailBytes = 0
                while (($n = $gzip.Read($tail, 0, $tail.Length)) -gt 0) {
                    $tailBytes += $n
                    if ($tailBytes -gt 1MB) { throw 'Excessive tar trailer' }
                    for ($i=0; $i -lt $n; $i++) { if ($tail[$i] -ne 0) { throw 'Nonzero data after tar terminator' } }
                }
                if ($tailBytes -lt 512 -or $tailBytes % 512 -ne 0) { throw 'Truncated tar terminator' }
                $tarBytes += $tailBytes
                break
            }
            $checksumText = [Text.Encoding]::ASCII.GetString($header,148,8).Trim([char]0,' ')
            if ($checksumText -notmatch '^[0-7]+$') { throw 'Invalid tar checksum field' }
            $sum = 0
            for ($i=0; $i -lt 512; $i++) { $sum += $(if ($i -ge 148 -and $i -lt 156) { 32 } else { [int]$header[$i] }) }
            if ($sum -ne [Convert]::ToInt64($checksumText,8)) { throw 'Tar header checksum mismatch' }
            $utf8 = [Text.UTF8Encoding]::new($false, $true)
            $name=$utf8.GetString($header,0,100).Trim([char]0); $prefix=$utf8.GetString($header,345,155).Trim([char]0)
            if($prefix){$name="$prefix/$name"}; $type=[char]$header[156]
            $sizeText=[Text.Encoding]::ASCII.GetString($header,124,12).Trim([char]0,' '); if($sizeText -notmatch '^[0-7]*$'){throw "Invalid tar size for $name"}; $size= if($sizeText){[Convert]::ToInt64($sizeText,8)}else{0}
            if([string]::IsNullOrWhiteSpace($name) -or $name -match '(^|/)\.(?:/|$)' -or -not (Test-A1625ArchivePath $name)){throw "Archive path is not allowlisted: $name"}
            if(-not $seen.Add($name.TrimEnd('/'))){throw "Duplicate tar entry: $name"}
            $modeText = [Text.Encoding]::ASCII.GetString($header,100,8).Trim([char]0,' ')
            if ($modeText -notmatch '^[0-7]+$' -or ([Convert]::ToInt64($modeText,8) -band 0xE00) -ne 0) { throw "Unsafe tar permissions: $name" }
            if($type -notin ([char]0,'0','5')){throw "Unsafe tar entry type for $name"}
            if($type -eq '5' -and $size -ne 0){throw "Directory contains data: $name"}
            if($size -gt 64MB){throw "Tar entry exceeds 64 MiB: $name"}; $expanded += $size; if($expanded -gt 512MB){throw 'Tar expanded size exceeds 512 MiB'}
            $skip=[int64]([Math]::Ceiling($size/512.0)*512); $tarBytes += $skip
            $buffer=New-Object byte[] 8192; $remainingData=$size
            $digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
            try {
                while($skip -gt 0){
                    $take=[int][Math]::Min($buffer.Length,$skip);$n=$gzip.Read($buffer,0,$take)
                    if($n -le 0){throw "Truncated tar data for $name"}
                    $dataCount=[int][Math]::Min($remainingData,$n)
                    if($dataCount -gt 0){$digest.AppendData($buffer,0,$dataCount);$remainingData-=$dataCount}
                    $skip-=$n
                }
                $files.Add([ordered]@{path=$name;bytes=$size;sha256=[Convert]::ToHexString($digest.GetHashAndReset());type=[string]$type})
            } finally { $digest.Dispose() }
            $entries++; if($entries -gt 4096){throw 'Archive has too many entries'}
        }
        if($entries -eq 0){throw 'Archive has no entries'}
        if ($Detailed) { [pscustomobject]@{Entries=$entries; ExpandedBytes=$expanded; TarBytes=$tarBytes; Files=$files.ToArray()} }
        else { $entries }
    } finally { $gzip.Dispose(); $input.Dispose() }
}
function Test-A1625RamTarget {
    param([Parameter(Mandatory)][string[]]$SshArguments,[string]$AppleTvAddress='172.16.42.1',[string]$RuntimePath)
    $probe=(Get-A1625RamGuard) + "`necho ram_target_ok"
    $reply=Invoke-A1625SshDownload -SshArguments $SshArguments -AppleTvAddress $AppleTvAddress -RemoteCommand $probe
    if([Text.Encoding]::UTF8.GetString($reply).Trim() -ne 'ram_target_ok'){throw 'Target is not verified as RAM-only with no block devices'}
    if ($RuntimePath) {
        $markerBytes = Invoke-A1625SshDownload -SshArguments $SshArguments -AppleTvAddress $AppleTvAddress `
            -RemoteCommand 'cat /run/a1625-development-layer.json' -MaxBytes 65536
        $marker = [Text.Encoding]::UTF8.GetString($markerBytes) | ConvertFrom-Json
        if ($marker.format -ne 'a1625-development-layer-v1' -or
            $marker.target -ne 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000' -or
            $marker.bundle.sha256 -ne (Get-A1625FileHashStrict $RuntimePath)) {
            throw 'The installed RAM tool layer differs from the selected immutable runtime.'
        }
    }
}
function Get-A1625RamGuard {
@'
set -eu
set -o pipefail
test "$(uname -m)" = aarch64
grep -q '^KernelPageSize:[[:space:]]*4 kB$' /proc/self/smaps
grep -q ' / rootfs ' /proc/mounts
grep -q ' /run tmpfs ' /proc/mounts
awk 'NR>1 && $4 !~ /^zram[0-9]+$/ && $1 ~ /^[0-9]+$/ {found=1} END {exit found}' /proc/partitions
awk '$2 ~ /^\/run\// {found=1} END {exit found}' /proc/mounts
test ! -L /run/work
test ! -L /run/codex-home
test ! -L /run/codex-home/.ssh
'@
}
function Get-A1625RamSnapshotCommand {
(Get-A1625RamGuard) + "`n" + @'
umask 077
mkdir /run/.a1625-state-lock
trap 'rmdir /run/.a1625-state-lock' EXIT
trap 'exit 130' HUP INT TERM
test -d /run/work
set -- run/work
for p in /run/codex-home/auth.json /run/codex-home/config.toml /run/codex-home/.ssh/config /run/codex-home/.ssh/known_hosts /run/codex-home/.ssh/id_ed25519 /run/codex-home/.ssh/id_ed25519.pub /run/codex-home/.gitconfig; do
  test -e "$p" || continue; test ! -L "$p"; test -f "$p"; set -- "$@" "${p#/}"
done
if find /run/work -xdev \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q .; then exit 41; fi
cd /; tar -czf - "$@"
'@
}
function Get-A1625RamRestoreCommand {
    param(
        [ValidateRange(0,536870912)][long]$ExpandedBytes = 536870912,
        [ValidateRange(0,268435456)][long]$ArchiveBytes = 268435456,
        [ValidatePattern('^[a-fA-F0-9]{64}$')][Parameter(Mandatory)][string]$ArchiveSha256
    )
    $command = (Get-A1625RamGuard) + "`n" + @'
umask 077
root=/run/.a1625-state-lock
mkdir "$root"
stage="$root/stage"; next="$root/next"; oldwork="$root/old-work"; oldhome="$root/old-home"
committed=0; worknew=0; homenew=0
rollback() {
  status=$?
  trap - EXIT HUP INT TERM
  if test "$committed" = 0; then
    if test "$worknew" = 1; then rm -rf /run/work; fi
    if test "$homenew" = 1; then rm -rf /run/codex-home; fi
    if test -d "$oldwork"; then mv "$oldwork" /run/work || exit 71; fi
    if test -d "$oldhome"; then mv "$oldhome" /run/codex-home || exit 72; fi
  fi
  rm -rf "$root"
  exit "$status"
}
trap rollback EXIT
trap 'exit 130' HUP INT TERM
# Reserve space for the archive, unpacked snapshot, a home copy and overhead
# before receiving or extracting data. Rename of work avoids a second copy.
homekb=0
if test -d /run/codex-home; then homekb=$(du -sk /run/codex-home | awk '{print $1}'); fi
need=$(( (__EXPANDED__ + __ARCHIVE__ + 1023) / 1024 + homekb + 65536 ))
available=$(df -Pk /run | awk 'NR==2 {print $4}')
test "$available" -gt "$need"
mkdir "$stage" "$next"
cat > "$root/archive.gz"
test "$(wc -c < "$root/archive.gz")" -eq __ARCHIVE__
echo '__HASH__  '"$root/archive.gz" | sha256sum -c - >/dev/null
tar -xzf "$root/archive.gz" -o -C "$stage" --no-same-permissions
rm "$root/archive.gz"
test -d "$stage/run"; if find "$stage" -xdev \( -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q .; then exit 42; fi
for p in /run/work /run/codex-home; do test ! -L "$p"; done
test -d "$stage/run/work"
mv "$stage/run/work" "$next/work"
mkdir "$next/codex-home"
test ! -e /run/codex-home || cp -a /run/codex-home/. "$next/codex-home/"
if find "$next/codex-home" -xdev \( -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q .; then exit 43; fi
for f in auth.json config.toml .gitconfig .ssh/config .ssh/known_hosts .ssh/id_ed25519 .ssh/id_ed25519.pub; do
  if test -e "$stage/run/codex-home/$f"; then
    test ! -L "$next/codex-home/$f"
    mkdir -p "$(dirname "$next/codex-home/$f")"
    cp -a "$stage/run/codex-home/$f" "$next/codex-home/$f"
    chmod 0600 "$next/codex-home/$f"
  fi
done
chmod 0700 "$next/codex-home"; test ! -d "$next/codex-home/.ssh" || chmod 0700 "$next/codex-home/.ssh"
test ! -e /run/work || mv /run/work "$oldwork"; test ! -e /run/codex-home || mv /run/codex-home "$oldhome"
mv "$next/work" /run/work; worknew=1
mv "$next/codex-home" /run/codex-home; homenew=1
committed=1; rm -rf "$oldwork" "$oldhome"
echo restored_ram_state
'@
    $command.Replace('__EXPANDED__',[string]$ExpandedBytes).Replace('__ARCHIVE__',[string]$ArchiveBytes).Replace('__HASH__',$ArchiveSha256.ToLowerInvariant())
}
Export-ModuleMember -Function Get-A1625RamStateEntropy,Get-A1625Sha256,ConvertTo-A1625RamEnvelope,ConvertFrom-A1625RamEnvelope,Get-A1625RuntimeFingerprint,Test-A1625RamStateSnapshot,Test-A1625ArchivePath,Assert-A1625SafeTar,Test-A1625RamTarget,Get-A1625RamSnapshotCommand,Get-A1625RamRestoreCommand,Get-A1625SshArguments,Invoke-A1625SshDownload,Invoke-A1625SshUpload,Set-A1625StateDirectoryAcl,Write-A1625AtomicBytes
