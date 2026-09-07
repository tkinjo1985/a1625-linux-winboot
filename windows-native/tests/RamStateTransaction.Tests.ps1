$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Host-only transaction test.  The device guard is deliberately removed by its
# exact private-module value; this isolates the filesystem transaction while
# preserving the command body produced for the A1625.
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$modulePath = Join-Path $repoRoot 'windows-native\ram-state\A1625RamState.psm1'
Import-Module $modulePath -Force
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Git Bash was not found: $bash" }
$failures = [Collections.Generic.List[string]]::new()

function Assert-True { param([bool]$Condition, [string]$Name) if ($Condition) { Write-Output "PASS $Name" } else { $failures.Add("FAIL $Name") } }
function Get-BashPath {
    param([string]$Path)
    $normalized = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($normalized -notmatch '^([A-Za-z]):/(.+)$') { throw "Cannot map fixture to Git Bash: $Path" }
    '/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2]
}
function Invoke-BashTransaction {
    param([string]$Script, [byte[]]$Payload)
    $info = [Diagnostics.ProcessStartInfo]::new($bash)
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['PATH'] = $env:PATH + ';C:\Program Files\Git\usr\bin;C:\Program Files\Git\bin'
    foreach ($argument in @('--noprofile','--norc','-c',$Script)) { [void]$info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.BaseStream.Write($Payload, 0, $Payload.Length); $process.StandardInput.Close(); $process.WaitForExit()
        [pscustomobject]@{ ExitCode=$process.ExitCode; Stdout=$stdoutTask.GetAwaiter().GetResult(); Stderr=$stderrTask.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}
function ConvertTo-FixtureTransaction {
    param([string]$Command, [string]$FixtureBashPath)
    # Keep archive paths beneath the transaction stage relative to $stage;
    # every other /run occurrence is the mocked target root.
    $Command.Replace('$stage/run', '$stage/__A1625_STAGE_RUN__').Replace('/run', $FixtureBashPath).Replace('__A1625_STAGE_RUN__', 'run')
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('a1625-ram-transaction-' + [guid]::NewGuid().ToString('N'))
function Assert-FixturePath([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($testRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $root.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($root) -notmatch '^a1625-ram-transaction-[a-f0-9]{32}$' -or
        ($resolved -ne $root -and -not $resolved.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase))) {
        throw 'Fixture path escaped its private temporary directory.'
    }
}
Assert-FixturePath $testRoot
try {
    $fixture = Join-Path $testRoot 'ram'
    $source = Join-Path $testRoot 'source'
    [IO.Directory]::CreateDirectory((Join-Path $source 'run\work')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'run\work\new.txt'), 'new-work')
    $archivePath = Join-Path $testRoot 'state.tar.gz'
    $sourceBash = Get-BashPath $source; $archiveBash = Get-BashPath $archivePath
    & $bash --noprofile --norc -c "tar -czf '$archiveBash' -C '$sourceBash' run/work"
    if ($LASTEXITCODE -ne 0) { throw 'Could not construct host-only transaction fixture archive.' }
    $archive = [IO.File]::ReadAllBytes($archivePath)
    $details = Assert-A1625SafeTar -GzipBytes $archive -Detailed
    $hash = (Get-A1625Sha256 $archive).ToLowerInvariant()
    $module = Get-Module A1625RamState
    $guard = & $module { Get-A1625RamGuard }
    $command = Get-A1625RamRestoreCommand -ArchiveSha256 $hash -ExpandedBytes $details.ExpandedBytes -ArchiveBytes $archive.Length
    if (-not $command.StartsWith($guard)) { throw 'Restore command no longer begins with the exact RAM guard boundary.' }
    $fixtureBash = Get-BashPath $fixture
    # MSYS `dirname` returns a drive-form path for /c/...; retain the POSIX
    # form the generated BusyBox command receives on the target.
    $hostPreamble = 'set -eu; set -o pipefail; dirname() { case "$1" in /c/*) printf "%s\n" "${1%/*}" ;; [A-Za-z]:/*) drive=${1%%:*}; path=${1#?:}; printf "/%s%s\n" "$(printf "%s" "$drive" | tr A-Z a-z)" "${path%/*}" ;; *) command dirname "$1" ;; esac; }; '
    $transaction = $hostPreamble + (ConvertTo-FixtureTransaction $command.Substring($guard.Length).TrimStart("`r", "`n") $fixtureBash)

    function Initialize-Fixture {
        param([switch]$WithFileSymlink)
        Assert-FixturePath $fixture
        if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
        [IO.Directory]::CreateDirectory((Join-Path $fixture 'work')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $fixture 'codex-home')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'work\old.txt'), 'old-work')
        [IO.File]::WriteAllText((Join-Path $fixture 'codex-home\keep.txt'), 'keep-home')
        if ($WithFileSymlink) {
            $fixturePath = Get-BashPath $fixture
            & $bash --noprofile --norc -c "ln -s keep.txt '$fixturePath/codex-home/keep-link'"
            if ($LASTEXITCODE -ne 0) { throw 'Could not create fixture symlink.' }
        }
    }

    Initialize-Fixture
    $result = Invoke-BashTransaction -Script $transaction -Payload $archive
    Assert-True ($result.ExitCode -eq 0 -and $result.Stdout.Trim() -eq 'restored_ram_state') 'successful transaction reports completion'
    $newWorkPath = Join-Path $fixture 'work\new.txt'
    Assert-True ((Test-Path -LiteralPath $newWorkPath) -and ([IO.File]::ReadAllText($newWorkPath) -eq 'new-work')) 'successful transaction swaps work tree'
    $keepPath = Join-Path $fixture 'codex-home\keep.txt'
    Assert-True ((Test-Path -LiteralPath $keepPath) -and ([IO.File]::ReadAllText($keepPath) -eq 'keep-home')) 'successful transaction preserves unrelated home file'

    # Git for Windows cannot reproduce a successful POSIX `cp -a` of a file
    # symlink on this host. Verify its real failure rolls back, and leave
    # success-path symlink preservation to the Linux/device validation.
    Initialize-Fixture -WithFileSymlink
    $fixturePath = Get-BashPath $fixture
    & $bash --noprofile --norc -c "test -L '$fixturePath/codex-home/keep-link'"
    $createdRealLink = $LASTEXITCODE -eq 0
    $result = Invoke-BashTransaction -Script $transaction -Payload $archive
    $fixturePath = Get-BashPath $fixture
    & $bash --noprofile --norc -c "test -L '$fixturePath/codex-home/keep-link'"
    $linkPreserved = $LASTEXITCODE -eq 0
    if (-not $createdRealLink) {
        Write-Output 'SKIP POSIX symlink preservation: this Git Bash ln creates a file copy, not a symlink.'
    }
    elseif ($result.ExitCode -eq 0) {
        Assert-True ($linkPreserved -and (Test-Path -LiteralPath (Join-Path $fixture 'work\new.txt'))) 'symlink-capable Git Bash preserves unrelated home link on successful restore'
    }
    else {
        Assert-True ($linkPreserved -and (Test-Path -LiteralPath (Join-Path $fixture 'work\old.txt')) -and -not (Test-Path -LiteralPath (Join-Path $fixture 'work\new.txt'))) 'Git Bash file-symlink copy failure rolls back original work and link'
    }

    Initialize-Fixture
    # Failure injection is at the third mv: after both old directories moved
    # aside, before the new work directory becomes live. `command mv` leaves
    # rollback's moves unmocked.
    $failurePrefix = 'mv_count=0; mv() { mv_count=$((mv_count + 1)); if test "$mv_count" -eq 3; then return 99; fi; command mv "$@"; }; '
    $result = Invoke-BashTransaction -Script ($failurePrefix + $transaction) -Payload $archive
    Assert-True ($result.ExitCode -ne 0) 'injected commit failure returns nonzero'
    Assert-True (([IO.File]::ReadAllText((Join-Path $fixture 'work\old.txt')) -eq 'old-work') -and -not (Test-Path -LiteralPath (Join-Path $fixture 'work\new.txt'))) 'rollback restores original work tree'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixture 'codex-home\keep.txt')) -eq 'keep-home') 'rollback restores original home tree'

    Initialize-Fixture
    # Mock only df so the command fails before it creates its transaction root.
    $capacityPrefix = "df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\nmock 100 99 1 99%% $fixtureBash\\n'; }; "
    $result = Invoke-BashTransaction -Script ($capacityPrefix + $transaction) -Payload $archive
    Assert-True ($result.ExitCode -ne 0) 'insufficient capacity returns nonzero'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixture 'work\old.txt')) -eq 'old-work') 'insufficient capacity leaves work unchanged'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixture 'codex-home\keep.txt')) -eq 'keep-home') 'insufficient capacity leaves home unchanged'

    Initialize-Fixture
    $corrupt = [byte[]]$archive; $corrupt[$corrupt.Length - 8] = $corrupt[$corrupt.Length - 8] -bxor 1
    $corruptCommand = Get-A1625RamRestoreCommand -ArchiveSha256 (Get-A1625Sha256 $corrupt).ToLowerInvariant() -ExpandedBytes $details.ExpandedBytes -ArchiveBytes $corrupt.Length
    $corruptTransaction = $hostPreamble + (ConvertTo-FixtureTransaction $corruptCommand.Substring($guard.Length).TrimStart("`r", "`n") $fixtureBash)
    $result = Invoke-BashTransaction -Script $corruptTransaction -Payload $corrupt
    Assert-True ($result.ExitCode -ne 0) 'corrupt gzip returns nonzero'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixture 'work\old.txt')) -eq 'old-work') 'corrupt gzip leaves work unchanged'
    Assert-True ([IO.File]::ReadAllText((Join-Path $fixture 'codex-home\keep.txt')) -eq 'keep-home') 'corrupt gzip leaves home unchanged'
}
finally {
    Assert-FixturePath $testRoot
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

if ($failures.Count) { $failures | Write-Error; exit 1 }
Write-Output 'All RAM-state transaction tests passed.'
