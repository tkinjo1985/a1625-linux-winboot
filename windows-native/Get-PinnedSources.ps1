#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$thirdPartyRoot = Join-Path $repoRoot 'third_party'
$sources = @(
    [ordered]@{ Name = 'openra1n'; Url = 'https://github.com/mineek/openra1n.git'; Revision = '4595a5333e4134ade77b43fb2259e880b85801ee' },
    [ordered]@{ Name = 'Palera1nWin'; Url = 'https://github.com/pwnapplehat/Palera1nWin.git'; Revision = 'b62a087839048e4bc9a496519ccd7aca1df3246f' },
    [ordered]@{ Name = 'HoolockLinux-docs'; Url = 'https://github.com/HoolockLinux/docs.git'; Revision = 'ac579429c2bf842afb9b4aea8ed944a9afbe067e' },
    [ordered]@{ Name = 'HoolockLinux-linux-native'; Url = 'https://github.com/HoolockLinux/linux.git'; Revision = '958481f87fee0949ff6a9a4af77f7eb6dac8a149' }
)

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is required.'
}
New-Item -ItemType Directory -Force -Path $thirdPartyRoot | Out-Null

foreach ($source in $sources) {
    $destination = Join-Path $thirdPartyRoot $source.Name
    if (Test-Path -LiteralPath $destination) {
        throw "Refusing to alter an existing source directory: $destination"
    }

    Write-Host "Cloning $($source.Url) at $($source.Revision)..."
    & git.exe clone --filter=blob:none --no-checkout -- $source.Url $destination
    if ($LASTEXITCODE -ne 0) { throw "git clone failed for $($source.Name)" }
    & git.exe -C $destination checkout --detach $source.Revision
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $($source.Name)" }

    $actualRevision = (& git.exe -C $destination rev-parse HEAD).Trim()
    $actualOrigin = (& git.exe -C $destination remote get-url origin).Trim()
    if ($actualRevision -ne $source.Revision -or $actualOrigin -ne $source.Url) {
        throw "Pinned source verification failed for $($source.Name)"
    }
}

Write-Host 'Pinned public sources are ready. No firmware, payload binary, or Apple data was downloaded.'
