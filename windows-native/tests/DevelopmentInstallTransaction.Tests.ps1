$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Host-only regression test for the development-layer transaction.  It obtains
# the actual expandable here-string through the PowerShell AST, then runs that
# emitted shell program against an isolated Git Bash filesystem fixture.
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$installerPath = Join-Path $repoRoot 'windows-native\development-tools\Install-A1625DevelopmentTools.ps1'
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Git Bash was not found: $bash" }
$failures = [Collections.Generic.List[string]]::new()

function Assert-True { param([bool]$Condition, [string]$Name) if ($Condition) { Write-Output "PASS $Name" } else { $failures.Add("FAIL $Name") } }
function Get-BashPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($full -notmatch '^([A-Za-z]):/(.+)$') { throw "Cannot map fixture to Git Bash: $Path" }
    '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2]
}
function Assert-FixturePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($script:testRoot)
    if ($full -ne $root -and -not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture path escaped its private temporary directory.'
    }
}
function Invoke-Bash {
    param([string]$Script, [hashtable]$Environment = @{})
    $info = [Diagnostics.ProcessStartInfo]::new($bash)
    $info.UseShellExecute = $false; $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.Environment['PATH'] = 'C:\Program Files\Git\usr\bin;' + $env:PATH
    # Feed the generated remote script over stdin.  Passing it through `-c`
    # makes the host's Windows command line the transport and can truncate or
    # rewrite a large here-string before Bash sees it.
    foreach ($argument in @('--noprofile', '--norc', '-s')) { [void]$info.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        [void]$process.Start(); $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Script); $process.StandardInput.Close(); $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.GetAwaiter().GetResult(); Stderr = $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}
function Invoke-BashChecked {
    param([string]$Script, [string]$Purpose)
    $execution = Invoke-Bash $Script
    if ($execution.ExitCode -ne 0) {
        throw "$Purpose failed (exit $($execution.ExitCode)).`nCommand: $Script`nstdout: $($execution.Stdout.Trim())`nstderr: $($execution.Stderr.Trim())"
    }
}
function New-GzipTar {
    param([string]$Archive, [string]$Source, [string[]]$Entries)
    $quoted = $Entries | ForEach-Object { "'$_'" }
    Invoke-BashChecked "'/usr/bin/tar' -czf '$(Get-BashPath $Archive)' -C '$(Get-BashPath $Source)' $($quoted -join ' ')" 'Could not create fixture archive'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('a1625-development-transaction-' + [guid]::NewGuid().ToString('N'))
try {
    Assert-FixturePath $testRoot
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Installer has PowerShell parse errors.' }
    $assignment = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$remote' }, $true)) | Select-Object -First 1
    $remoteExpression = if ($assignment.Right -is [Management.Automation.Language.CommandExpressionAst]) { $assignment.Right.Expression } else { $assignment.Right }
    if (-not $assignment -or $remoteExpression -isnot [Management.Automation.Language.ExpandableStringExpressionAst]) { throw 'Could not locate the installer remote expandable here-string.' }

    $fixture = Join-Path $testRoot 'fixture'; $run = Join-Path $fixture 'run'; $optBin = Join-Path $fixture 'opt\bin'; $fakeBin = Join-Path $fixture 'fake-bin'
    $apkSource = Join-Path $testRoot 'apk'; $layerSource = Join-Path $testRoot 'layer'; $bundle = Join-Path $testRoot 'layer.tar.gz'; $staleSource = Join-Path $testRoot 'stale'
    foreach ($dir in @($run, $optBin, $fakeBin, (Join-Path $apkSource 'usr\bin'), $layerSource, (Join-Path $staleSource 'usr\bin'))) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    [IO.File]::WriteAllText((Join-Path $apkSource 'usr\bin\git'), "#!/bin/sh`necho 'git version fixture'`n")
    [IO.File]::WriteAllText((Join-Path $staleSource 'usr\bin\stale-marker'), "#!/bin/sh`nexit 0`n")
    $apkBash = Get-BashPath $apkSource; $staleBash = Get-BashPath $staleSource
    foreach ($command in @("'/usr/bin/chmod' 0755 '$apkBash/usr/bin/git'", "'/usr/bin/chmod' 0755 '$staleBash/usr/bin/stale-marker'")) { Invoke-BashChecked $command 'Could not mark fixture executable' }
    $apk = Join-Path $layerSource 'git-1.apk'; New-GzipTar $apk $apkSource @('.')
    $staleApk = Join-Path $run 'a1625-layer\stale.apk'; [IO.Directory]::CreateDirectory((Split-Path $staleApk)) | Out-Null; New-GzipTar $staleApk $staleSource @('.')
    [IO.File]::WriteAllText((Join-Path $layerSource 'manifest.json'), '{"fixture":true}')
    [IO.File]::WriteAllText((Join-Path $layerSource 'a1625-tool'), "#!/bin/sh`nexit 0`n")
    [IO.File]::WriteAllText((Join-Path $layerSource 'a1625-zram-enable'), "#!/bin/sh`nexit 0`n")
    $layerBash = Get-BashPath $layerSource
    foreach ($file in @('a1625-tool', 'a1625-zram-enable')) { Invoke-BashChecked "'/usr/bin/chmod' 0755 '$layerBash/$file'" 'Could not mark layer helper executable' }
    New-GzipTar $bundle $layerSource @('manifest.json', 'a1625-tool', 'a1625-zram-enable', 'git-1.apk')
    $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
    $bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash

    # Evaluate the production expression with deliberately tiny, valid lock
    # data.  This catches interpolation and quoting regressions too.
    $locked = @([pscustomobject]@{ file = 'git-1.apk'; sha256 = $apkHash })
    $result = [pscustomobject]@{ BundleBytes = (Get-Item -LiteralPath $bundle).Length }
    $bundleInspection = [pscustomobject]@{ expandedBytes = 4096 }
    $HostAddress = '127.0.0.1'; $HttpPort = 8082; $manifest = '{"fixture":true}'; $runtimeMarkerJson = $manifest; $zramCommand = 'false'
    $bundle = [IO.FileInfo]$bundle
    $remote = & ([scriptblock]::Create("`$remote = $($remoteExpression.Extent.Text)`n`$remote"))
    Assert-True (($remote.IndexOf('ln -sfn /opt/bin/a1625-git /opt/bin/git', [StringComparison]::Ordinal) -ge 0) -and ($remote.IndexOf("`nfalse`n", [StringComparison]::Ordinal) -gt $remote.IndexOf('ln -sfn /opt/bin/a1625-git /opt/bin/git', [StringComparison]::Ordinal))) 'injected failure is positioned after wrapper replacement'
    if ($remote -notmatch [regex]::Escape('test ! -L /run/a1625-layer')) { throw 'Remote command lost the layer symlink guard.' }
    $boundary = 'test ! -L /run/a1625-layer'; $offset = $remote.IndexOf($boundary, [StringComparison]::Ordinal)
    $body = "set -eu`nset -o pipefail`n" + $remote.Substring($offset)
    $runBash = Get-BashPath $run; $optBash = Get-BashPath $optBin
    # BusyBox accepts its historical `-perm +mode`; Git Bash GNU find uses
    # `/mode` for the same any-bit test.
    $transaction = $body.Replace('$nextroot/opt/bin', '$nextroot/__A1625_NEXTROOT_OPT__').Replace('/opt/bin', $optBash).Replace('/run', $runBash).Replace('__A1625_NEXTROOT_OPT__', 'opt/bin').Replace('-perm +6000', '-perm /6000')

    # wget is the only network-facing utility in the remote command.  The
    # replacement copies the known local bundle and leaves every later check
    # (hash, tar extraction and lock checks) intact.
    $fakeWget = Join-Path $fakeBin 'wget'
    [IO.File]::WriteAllText($fakeWget, @'
#!/bin/sh
while test $# -gt 0; do
  if test "$1" = -O; then out="$2"; shift 2; else shift; fi
done
cp "$FIXTURE_BUNDLE" "$out"
'@)
    $fakeBash = Get-BashPath $fakeBin; Invoke-BashChecked "'/usr/bin/chmod' 0755 '$fakeBash/wget'" 'Could not make fake wget executable'
    $environment = @{ FIXTURE_BUNDLE = (Get-BashPath $bundle.FullName) }
    $transaction = "export PATH='$fakeBash`:/usr/bin:/bin'`n" + $transaction

    # Existing state has a root, wrappers and a manifest. zramCommand=false
    # fails after all three have been replaced, exercising the full rollback.
    $oldRoot = Join-Path $run 'a1625-tools\root\usr\bin'; [IO.Directory]::CreateDirectory($oldRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $oldRoot 'old-marker'), 'old-root')
    [IO.File]::WriteAllText((Join-Path $optBin 'a1625-tool'), 'old-wrapper')
    [IO.File]::WriteAllText((Join-Path $optBin 'old-git'), 'old-git')
    $optBash = Get-BashPath $optBin
    if ((Invoke-Bash "ln -s '$optBash/old-git' '$optBash/git'").ExitCode) { throw 'Could not create old git wrapper symlink.' }
    # Git for Windows can create a link even where cp -a cannot faithfully
    # round-trip it. Select the genuine supported behavior, while retaining a
    # regular-wrapper rollback assertion on hosts without that capability.
    $probe = Get-BashPath (Join-Path $testRoot 'link-copy-probe')
    $linkRoundTrip = (Invoke-Bash "cp -a '$optBash/git' '$probe' && test -L '$probe'").ExitCode -eq 0
    if (-not $linkRoundTrip) {
        [IO.File]::Delete((Join-Path $optBin 'git'))
        [IO.File]::WriteAllText((Join-Path $optBin 'git'), 'old-git-wrapper')
    }
    [IO.File]::WriteAllText((Join-Path $run 'a1625-development-layer.json'), '{"old":true}')

    $execution = Invoke-Bash $transaction $environment
    if ($execution.Stdout -notmatch 'git version fixture') { Write-Host $execution.Stderr }
    Assert-True ($execution.Stdout -match 'git version fixture') 'transaction reaches installed Git before injected failure'
    Assert-True ($execution.ExitCode -ne 0) 'post-wrapper zram failure returns nonzero'
    Assert-True ((Test-Path -LiteralPath (Join-Path $oldRoot 'old-marker')) -and -not (Test-Path -LiteralPath (Join-Path $run 'a1625-tools\root\usr\bin\git'))) 'failure restores prior root without new package files'
    Assert-True ([IO.File]::ReadAllText((Join-Path $optBin 'a1625-tool')) -eq 'old-wrapper') 'failure restores existing a1625-tool wrapper'
    if ($linkRoundTrip) {
        $linkCheck = Invoke-Bash ('test -L ''{0}/git'' && test "$(readlink ''{0}/git'')" = ''{0}/old-git''' -f $optBash)
        Assert-True ($linkCheck.ExitCode -eq 0) 'failure restores existing git wrapper link'
    } else {
        Assert-True ([IO.File]::ReadAllText((Join-Path $optBin 'git')) -eq 'old-git-wrapper') 'failure restores existing regular git wrapper'
    }
    Assert-True ([IO.File]::ReadAllText((Join-Path $run 'a1625-development-layer.json')) -eq '{"old":true}') 'failure restores prior layer marker'
    Assert-True (-not (Test-Path -LiteralPath $staleApk) -and -not (Test-Path -LiteralPath (Join-Path $run 'a1625-tools\root\usr\bin\stale-marker'))) 'stale layer APK is removed and never extracted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $run '.a1625-tools-install-lock'))) 'failure removes exclusive transaction lock'
}
finally {
    Assert-FixturePath $testRoot
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

if ($failures.Count) { $failures | Write-Error; exit 1 }
Write-Output 'All development-install transaction tests passed.'
