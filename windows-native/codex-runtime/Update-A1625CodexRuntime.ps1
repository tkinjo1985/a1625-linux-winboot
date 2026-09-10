<#
.SYNOPSIS
Updates the pinned OpenAI Codex CLI runtime used by the A1625 RAM environment.

.DESCRIPTION
Resolves the latest stable Codex GitHub release by default, or a requested
version, requires SHA-256 digests for the three AArch64 musl runtime assets,
downloads and verifies the actual asset bytes, stages them under
artifacts\codex-runtime, updates both host-side and target-side SHA-256 pins in
Install-CodexRamRuntime.ps1, and runs the installer with -PrepareOnly.

The installer edit is fail-closed: each expected version/hash location must
match exactly once. If final prepare validation fails after the installer was
written, the previous installer text is restored.

.EXAMPLE
& .\windows-native\codex-runtime\Update-A1625CodexRuntime.ps1

Updates to the latest stable Codex release.

.EXAMPLE
& .\windows-native\codex-runtime\Update-A1625CodexRuntime.ps1 -CheckOnly

Shows the latest stable release and required asset digests without changing
files or downloading runtime assets.

.EXAMPLE
& .\windows-native\codex-runtime\Update-A1625CodexRuntime.ps1 -Version 0.153.4

Pins and validates Codex 0.153.4 explicitly.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$')]
    [string]$Version,

    [string]$InstallerPath = (Join-Path $PSScriptRoot 'Install-CodexRamRuntime.ps1'),

    [switch]$AllowPrerelease,

    [switch]$CheckOnly,

    [switch]$SkipPrepareValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredAssets = @(
    [pscustomobject]@{
        Name = 'codex-aarch64-unknown-linux-musl.tar.gz'
        RemotePath = '/run/codex.tar.gz'
    },
    [pscustomobject]@{
        Name = 'codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz'
        RemotePath = '/run/codex-host.tar.gz'
    },
    [pscustomobject]@{
        Name = 'bwrap-aarch64-unknown-linux-musl.tar.gz'
        RemotePath = '/run/bwrap.tar.gz'
    }
)

$githubHeaders = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'a1625-linux-winboot-codex-updater'
    'X-GitHub-Api-Version' = '2022-11-28'
}

function Get-SingleRegexMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $Description in the installer, found $($matches.Count). Refusing to edit an unexpected installer layout."
    }
    return $matches[0]
}

function Get-ReleaseAssetInfo {
    param(
        [Parameter(Mandatory)]
        [object]$Release,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$RemotePath
    )

    $matching = @($Release.assets | Where-Object { $_.name -eq $Name })
    if ($matching.Count -ne 1) {
        throw "Expected exactly one release asset named '$Name', found $($matching.Count)."
    }

    $asset = $matching[0]
    if ([string]::IsNullOrWhiteSpace([string]$asset.digest)) {
        throw "Release asset '$Name' does not expose a GitHub digest. Refusing an unpinned update."
    }

    $digest = [string]$asset.digest
    $digestMatch = [regex]::Match($digest, '^sha256:(?<hash>[0-9A-Fa-f]{64})$')
    if (-not $digestMatch.Success) {
        throw "Release asset '$Name' has an unsupported digest: $digest"
    }

    [pscustomobject]@{
        Name = $Name
        RemotePath = $RemotePath
        Sha256 = $digestMatch.Groups['hash'].Value.ToUpperInvariant()
        Uri = [string]$asset.browser_download_url
        Size = [int64]$asset.size
    }
}

$installerFullPath = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $installerFullPath -PathType Leaf)) {
    throw "Installer was not found: $installerFullPath"
}

if ($Version) {
    $tag = "rust-v$Version"
    $releaseUri = "https://api.github.com/repos/openai/codex/releases/tags/$tag"
}
else {
    $releaseUri = 'https://api.github.com/repos/openai/codex/releases/latest'
}

Write-Host "Resolving Codex release: $releaseUri"
$release = Invoke-RestMethod -Headers $githubHeaders -Uri $releaseUri

if ([bool]$release.draft) {
    throw "Refusing draft release: $($release.tag_name)"
}
if ([bool]$release.prerelease -and -not $AllowPrerelease) {
    throw "Release '$($release.tag_name)' is a prerelease. Re-run with -AllowPrerelease if that is intentional."
}
$tagMatch = [regex]::Match([string]$release.tag_name, '^rust-v(?<version>.+)$')
if (-not $tagMatch.Success) {
    throw "Unexpected Codex release tag: $($release.tag_name)"
}

$resolvedVersion = $tagMatch.Groups['version'].Value
if ($Version -and $resolvedVersion -ne $Version) {
    throw "Requested version '$Version' resolved to unexpected release '$resolvedVersion'."
}

$assets = @()
foreach ($required in $requiredAssets) {
    $assets += Get-ReleaseAssetInfo -Release $release -Name $required.Name -RemotePath $required.RemotePath
}

$installerText = [IO.File]::ReadAllText($installerFullPath)
$updatedText = $installerText

$releaseMatch = Get-SingleRegexMatch -Text $updatedText `
    -Pattern '(?m)^\$release = ''(?<value>[^'']+)''\s*$' `
    -Description '$release assignment'
$currentVersion = $releaseMatch.Groups['value'].Value
$updatedText = $updatedText.Replace($releaseMatch.Value, "`$release = '$resolvedVersion'")

foreach ($asset in $assets) {
    $escapedName = [regex]::Escape($asset.Name)
    $assetMatch = Get-SingleRegexMatch -Text $updatedText `
        -Pattern "(?ms)Name = '$escapedName'\s*\r?\n\s*Sha256 = '(?<hash>[0-9A-Fa-f]{64})'" `
        -Description "SHA-256 pin for $($asset.Name)"

    $oldAssetHash = $assetMatch.Groups['hash'].Value
    $newAssetBlock = $assetMatch.Value.Replace($oldAssetHash, $asset.Sha256)
    $updatedText = $updatedText.Replace($assetMatch.Value, $newAssetBlock)

    $escapedRemotePath = [regex]::Escape($asset.RemotePath)
    $remoteMatch = Get-SingleRegexMatch -Text $updatedText `
        -Pattern "(?m)^echo '(?<hash>[0-9A-Fa-f]{64})  $escapedRemotePath' \| sha256sum -c -\s*$" `
        -Description "remote SHA-256 verification for $($asset.RemotePath)"

    $oldRemoteHash = $remoteMatch.Groups['hash'].Value
    $newRemoteLine = $remoteMatch.Value.Replace($oldRemoteHash, $asset.Sha256.ToLowerInvariant())
    $updatedText = $updatedText.Replace($remoteMatch.Value, $newRemoteLine)
}

$summary = [pscustomobject]@{
    CurrentVersion = $currentVersion
    TargetVersion = $resolvedVersion
    Tag = [string]$release.tag_name
    PublishedAt = [datetimeoffset]$release.published_at
    Prerelease = [bool]$release.prerelease
    InstallerPath = $installerFullPath
    Assets = $assets
}

if ($CheckOnly) {
    Write-Host "Codex runtime update check: $currentVersion -> $resolvedVersion"
    $summary
    return
}

if ($updatedText -ceq $installerText) {
    Write-Host "Installer is already pinned to Codex $resolvedVersion. Verifying/staging release assets anyway."
}
else {
    Write-Host "Preparing installer update: $currentVersion -> $resolvedVersion"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("a1625-codex-update-" + [guid]::NewGuid().ToString('N'))
$runtimeDirectory = Split-Path -Parent $installerFullPath
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $runtimeDirectory '..\..\artifacts\codex-runtime'))
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$installerWritten = $false

New-Item -ItemType Directory -Force -Path $tempRoot, $artifactRoot | Out-Null

try {
    foreach ($asset in $assets) {
        $tempAsset = Join-Path $tempRoot $asset.Name
        Write-Host "Downloading $($asset.Name)"
        Invoke-WebRequest -Headers @{ 'User-Agent' = $githubHeaders['User-Agent'] } `
            -Uri $asset.Uri -OutFile $tempAsset

        $actualHash = (Get-FileHash -LiteralPath $tempAsset -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($actualHash -ne $asset.Sha256) {
            throw "SHA-256 mismatch for $($asset.Name): expected $($asset.Sha256), got $actualHash"
        }

        $actualSize = (Get-Item -LiteralPath $tempAsset).Length
        if ($asset.Size -gt 0 -and $actualSize -ne $asset.Size) {
            throw "Size mismatch for $($asset.Name): expected $($asset.Size), got $actualSize"
        }

        Write-Host "Verified $($asset.Name): $actualHash"
        Copy-Item -LiteralPath $tempAsset -Destination (Join-Path $artifactRoot $asset.Name) -Force
    }

    if ($updatedText -cne $installerText) {
        $temporaryInstaller = "$installerFullPath.tmp.$PID"
        [IO.File]::WriteAllText($temporaryInstaller, $updatedText, $utf8NoBom)
        Move-Item -LiteralPath $temporaryInstaller -Destination $installerFullPath -Force
        $installerWritten = $true
        Write-Host "Updated installer pin: Codex $resolvedVersion"
    }

    if (-not $SkipPrepareValidation) {
        Write-Host 'Running Install-CodexRamRuntime.ps1 -PrepareOnly'
        & $installerFullPath -PrepareOnly
        if (-not $?) {
            throw 'Install-CodexRamRuntime.ps1 -PrepareOnly reported failure.'
        }
    }

    Write-Host "Codex runtime pin is ready: $resolvedVersion"
    $summary
}
catch {
    $updateFailure = $_
    if ($installerWritten) {
        try {
            [IO.File]::WriteAllText($installerFullPath, $installerText, $utf8NoBom)
            Write-Warning "Prepare validation failed. Restored the previous installer pin ($currentVersion)."
        }
        catch {
            Write-Warning "The update failed and automatic installer rollback also failed: $($_.Exception.Message)"
        }
    }
    throw $updateFailure
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
