$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Regression coverage for callers launched from a PowerShell workspace while
# the process current directory still points somewhere else (for example, a
# host application or a temporary launcher directory).
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Import-Module (Join-Path $repoRoot 'windows-native\codex-state\A1625CodexState.psm1') -Force
$failures = [Collections.Generic.List[string]]::new()

function Assert-Equal {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual, [Parameter(Mandatory)][string]$Name)
    if ($Expected -eq $Actual) { Write-Output "PASS $Name" } else { $failures.Add("FAIL ${Name}: expected '$Expected', got '$Actual'") }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Name)
    try { & $Action; $failures.Add("FAIL $Name (did not throw)") } catch { Write-Output "PASS $Name" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('a1625-ssh-paths-' + [guid]::NewGuid().ToString('N'))
$originalLocation = Get-Location
$originalCurrentDirectory = [Environment]::CurrentDirectory
try {
    $workspace = Join-Path $testRoot 'workspace'
    $environmentHome = Join-Path $testRoot 'environment-home'
    [IO.Directory]::CreateDirectory($workspace) | Out-Null
    [IO.Directory]::CreateDirectory($environmentHome) | Out-Null
    [IO.File]::WriteAllText((Join-Path $workspace 'identity'), 'fixture private key')
    [IO.File]::WriteAllText((Join-Path $workspace 'known_hosts'), 'fixture known hosts')

    Set-Location -LiteralPath $workspace
    [Environment]::CurrentDirectory = $environmentHome

    $arguments = Get-A1625SshArguments -SshKeyPath 'identity' -KnownHostsPath 'known_hosts'
    Assert-Equal (Resolve-Path -LiteralPath 'identity').ProviderPath $arguments[2] 'relative identity resolves from the PowerShell location'
    Assert-Equal ('UserKnownHostsFile=' + (Resolve-Path -LiteralPath 'known_hosts').ProviderPath) $arguments[-1] 'relative known-hosts resolves from the PowerShell location'
    Assert-Throws { Get-A1625SshArguments -SshKeyPath 'missing-identity' -KnownHostsPath 'known_hosts' } 'missing relative SSH file is rejected'
}
finally {
    Set-Location -LiteralPath $originalLocation
    [Environment]::CurrentDirectory = $originalCurrentDirectory
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

if ($failures.Count) { $failures | Write-Error; exit 1 }
Write-Output 'All A1625 SSH path regression tests passed.'
