#Requires -Version 7.0
[CmdletBinding()]
param([string]$StateDirectory=(Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state'),[ValidateSet('172.16.42.1')][string]$AppleTvAddress='172.16.42.1',[Parameter(Mandatory)][string]$PayloadPath,[Parameter(Mandatory)][string]$RuntimePath,[Parameter(Mandatory)][string]$SshKeyPath,[Parameter(Mandatory)][string]$KnownHostsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'A1625RamState.psm1') -Force
$StateDirectory=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StateDirectory);$name=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $StateDirectory 'current'))).Trim()
if($name -notmatch '^state-([A-F0-9]{32})\.dpapi$'){throw 'Invalid snapshot generation pointer.'};$prefix=$Matches[1];$cipherPath=Join-Path $StateDirectory $name
if(-not(Test-Path $cipherPath -PathType Leaf) -or (Get-Item $cipherPath).Length -gt 400MB){throw 'Selected encrypted snapshot is missing or exceeds 400 MiB.'}
$cipher=$null;$plain=$null;$archive=$null
try {
 $cipher=[IO.File]::ReadAllBytes($cipherPath);if(-not (Get-A1625Sha256 -Bytes $cipher).StartsWith($prefix)){throw 'Snapshot generation filename hash mismatch.'}
 $fingerprint=Get-A1625RuntimeFingerprint -PayloadPath $PayloadPath -RuntimePath $RuntimePath
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,(Get-A1625RamStateEntropy),[Security.Cryptography.DataProtectionScope]::CurrentUser)
 $decoded=ConvertFrom-A1625RamEnvelope -Plain $plain -Fingerprint $fingerprint;$archive=$decoded.Archive;$details=$decoded.Details
 $sshArguments=Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath;Test-A1625RamTarget -SshArguments $sshArguments -AppleTvAddress $AppleTvAddress -RuntimePath $RuntimePath
 $timer=[Diagnostics.Stopwatch]::StartNew();$result=Invoke-A1625SshUpload -SshArguments $sshArguments -AppleTvAddress $AppleTvAddress -RemoteCommand (Get-A1625RamRestoreCommand -ExpandedBytes $details.ExpandedBytes -ArchiveBytes $archive.Length -ArchiveSha256 (Get-A1625Sha256 -Bytes $archive)) -Payload $archive;$timer.Stop()
 if($result -ne 'restored_ram_state'){throw "RAM state restore failed: $result"};[pscustomobject]@{Restored=$true;CompressedBytes=$archive.Length;RawTarBytes=[int64]$details.TarBytes;RestoreSeconds=[Math]::Round($timer.Elapsed.TotalSeconds,3)}
} finally {foreach($buffer in @($plain,$archive,$cipher)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}}
