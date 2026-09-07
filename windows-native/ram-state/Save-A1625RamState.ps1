#Requires -Version 7.0
[CmdletBinding()]
param([string]$StateDirectory=(Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state'),[ValidateSet('172.16.42.1')][string]$AppleTvAddress='172.16.42.1',[Parameter(Mandatory)][string]$PayloadPath,[Parameter(Mandatory)][string]$RuntimePath,[Parameter(Mandatory)][string]$SshKeyPath,[Parameter(Mandatory)][string]$KnownHostsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'A1625RamState.psm1') -Force
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
Set-A1625StateDirectoryAcl -Path $StateDirectory
$sshArguments=Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath
Test-A1625RamTarget -SshArguments $sshArguments -AppleTvAddress $AppleTvAddress -RuntimePath $RuntimePath
$archive=$null;$envelope=$null;$cipher=$null
try {
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $archive=Invoke-A1625SshDownload -SshArguments $sshArguments -AppleTvAddress $AppleTvAddress -RemoteCommand (Get-A1625RamSnapshotCommand)
 $timer.Stop(); if($archive.Length -gt 256MB){throw 'Compressed snapshot exceeds the 256 MiB transport limit.'}
 $details=Assert-A1625SafeTar -GzipBytes $archive -Detailed
 $fingerprint=Get-A1625RuntimeFingerprint -PayloadPath $PayloadPath -RuntimePath $RuntimePath
 $envelope=ConvertTo-A1625RamEnvelope -Archive $archive -Fingerprint $fingerprint -Entries $details.Entries
 $cipher=[Security.Cryptography.ProtectedData]::Protect($envelope,(Get-A1625RamStateEntropy),[Security.Cryptography.DataProtectionScope]::CurrentUser)
 if($cipher.Length -gt 400MB){throw 'Encrypted snapshot exceeds the 400 MiB host limit.'}
 $name='state-{0}.dpapi' -f (Get-A1625Sha256 -Bytes $cipher).Substring(0,32)
 Write-A1625AtomicBytes -Path (Join-Path $StateDirectory $name) -Bytes $cipher
 Write-A1625AtomicBytes -Path (Join-Path $StateDirectory 'current') -Bytes ([Text.Encoding]::ASCII.GetBytes($name))
 [pscustomobject]@{Saved=$true;CompressedBytes=$archive.Length;RawTarBytes=[int64]$details.TarBytes;CompressionRatio=[Math]::Round($archive.Length/$details.TarBytes,4);DownloadSeconds=[Math]::Round($timer.Elapsed.TotalSeconds,3);ArchiveEntries=$details.Entries}
} finally {foreach($buffer in @($archive,$envelope,$cipher)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}}
