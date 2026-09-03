[CmdletBinding()]
param(
    [string]$BootArgs = 'hl_rd="shell" console=ttySAC6,115200n8 loglevel=7',
    [string]$InitramfsPath,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$OutputName = 'm1n1-linux-a1625.bin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $InitramfsPath) {
    $InitramfsPath = Join-Path $repoRoot 'artifacts\hoolock\hoolockrd\initramfs.gz'
}
$parts = @(
    [ordered]@{ Name = 'm1n1'; Path = Join-Path $repoRoot 'artifacts\hoolock\m1n1\m1n1.bin' },
    [ordered]@{ Name = 'bootargs'; Bytes = [Text.Encoding]::ASCII.GetBytes("chosen.bootargs=$BootArgs`n") },
    [ordered]@{ Name = 'dtb'; Path = Join-Path $repoRoot 'third_party\HoolockLinux-linux-native\arch\arm64\boot\dts\apple\t7000-j42d.dtb' },
    [ordered]@{ Name = 'kernel'; Path = Join-Path $repoRoot 'third_party\HoolockLinux-linux-native\arch\arm64\boot\Image.gz' },
    [ordered]@{ Name = 'initramfs'; Path = $InitramfsPath }
)

$outputDirectory = Join-Path $repoRoot 'artifacts\hoolock\payload'
$outputPath = Join-Path $outputDirectory $OutputName
$outputStem = [IO.Path]::GetFileNameWithoutExtension($OutputName)
$manifestPath = Join-Path $outputDirectory "$outputStem.manifest.json"
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$componentManifest = [Collections.Generic.List[object]]::new()
$output = [IO.File]::Open($outputPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    foreach ($part in $parts) {
        if ($part.Contains('Bytes')) {
            $bytes = $part.Bytes
            $output.Write($bytes, 0, $bytes.Length)
            $hashBytes = [Security.Cryptography.SHA256]::HashData($bytes)
            $hash = [Convert]::ToHexString($hashBytes)
            $length = $bytes.Length
            $source = 'inline ASCII, LF terminated'
        }
        else {
            $resolved = (Resolve-Path -LiteralPath $part.Path).Path
            $input = [IO.File]::OpenRead($resolved)
            try {
                $length = $input.Length
                $input.CopyTo($output)
            }
            finally {
                $input.Dispose()
            }
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
            $source = $resolved
        }

        $componentManifest.Add([ordered]@{
            order = $componentManifest.Count + 1
            name = $part.Name
            bytes = $length
            sha256 = $hash
            source = $source
        })
    }
}
finally {
    $output.Dispose()
}

$payload = Get-Item -LiteralPath $outputPath
if ($payload.Length -gt 128MB) {
    throw "Payload exceeds the uploader's 128 MiB limit: $($payload.Length) bytes"
}

$manifest = [ordered]@{
    target = 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000'
    mode = 'RAM-only PongoOS m1n1 Linux boot'
    bootargs = $BootArgs
    components = $componentManifest
    payload = [ordered]@{
        path = $payload.FullName
        bytes = $payload.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
$manifest | ConvertTo-Json -Depth 6
