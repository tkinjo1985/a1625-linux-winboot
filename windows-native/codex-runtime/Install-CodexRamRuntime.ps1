[CmdletBinding()]
param(
    [ValidateSet('172.16.42.1')]
    [string]$AppleTvAddress = '172.16.42.1',
    [ValidateSet('172.16.42.2')]
    [string]$HostAddress = '172.16.42.2',
    [ValidateRange(1024, 65535)]
    [int]$HttpPort = 8081,
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\known_hosts_minimal_boot_20260902'),
    [switch]$RestoreState,
    [switch]$Login,
    [switch]$PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Login -and $RestoreState) {
    throw 'Choose either -Login or -RestoreState, not both.'
}

$release = '0.153.4'
$tag = "rust-v$release"
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\artifacts\codex-runtime'))
$caExtractRoot = Join-Path $artifactRoot 'ca-extracted'

$assets = @(
    [pscustomobject]@{
        Name = 'codex-aarch64-unknown-linux-musl.tar.gz'
        Sha256 = '5CDA6182BD94C3A30F2EB63A495489EBF7F691FDDB14D70F48C6C1A5071B6CDE'
        Uri = "https://github.com/openai/codex/releases/download/$tag/codex-aarch64-unknown-linux-musl.tar.gz"
    },
    [pscustomobject]@{
        Name = 'codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz'
        Sha256 = 'D8047B8D33370D6090E729D27EB76DE60A2686BAA1C143C138C9B05DC70D813B'
        Uri = "https://github.com/openai/codex/releases/download/$tag/codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz"
    },
    [pscustomobject]@{
        Name = 'bwrap-aarch64-unknown-linux-musl.tar.gz'
        Sha256 = '2C6EA97DFB0A936B695ECE6DF058B89D4DFD53774A9AD852B3E4C98E6BBDFD20'
        Uri = "https://github.com/openai/codex/releases/download/$tag/bwrap-aarch64-unknown-linux-musl.tar.gz"
    },
    [pscustomobject]@{
        Name = 'ca-certificates-bundle-20260611-r0.apk'
        Sha256 = '9CC6938C1950BFA84D15AEB61BD6DEE294B0B856804F36252796E340975C264E'
        Uri = 'https://dl-cdn.alpinelinux.org/alpine/v3.23/main/aarch64/ca-certificates-bundle-20260611-r0.apk'
    }
)

foreach ($tool in 'ssh.exe', 'python.exe', 'tar.exe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required host tool was not found: $tool"
    }
}
foreach ($path in $(if ($PrepareOnly) { @() } else { @($SshKeyPath, $KnownHostsPath) })) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file was not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $artifactRoot, $caExtractRoot | Out-Null
foreach ($asset in $assets) {
    $destination = Join-Path $artifactRoot $asset.Name
    $valid = (Test-Path -LiteralPath $destination -PathType Leaf) -and
        ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $asset.Sha256)
    if (-not $valid) {
        Invoke-WebRequest -UseBasicParsing -Uri $asset.Uri -OutFile $destination
    }
    $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($actualHash -ne $asset.Sha256) {
        throw "SHA-256 mismatch for $($asset.Name): $actualHash"
    }
    Write-Host "Verified $($asset.Name): $actualHash"
}

$caApk = Join-Path $artifactRoot 'ca-certificates-bundle-20260611-r0.apk'
& tar.exe -xf $caApk -C $caExtractRoot
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to extract the Alpine CA bundle.'
}
$caBundle = Join-Path $caExtractRoot 'etc\ssl\certs\ca-certificates.crt'
if (-not (Test-Path -LiteralPath $caBundle -PathType Leaf)) {
    throw "Extracted CA bundle was not found: $caBundle"
}

$launcherSource = Join-Path $PSScriptRoot 'codex-ram'
Copy-Item -LiteralPath $launcherSource -Destination (Join-Path $artifactRoot 'codex-ram') -Force
$launcherHash = (Get-FileHash -LiteralPath $launcherSource -Algorithm SHA256).Hash.ToLowerInvariant()
if ($PrepareOnly) {
    [pscustomobject]@{ Release = $release; ArtifactRoot = $artifactRoot; LauncherSha256 = $launcherHash }
    return
}

$sshOptions = @(
    '-i', [IO.Path]::GetFullPath($SshKeyPath),
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', ('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath))
)

$remoteInstall = @'
set -eu
grep -q ' / rootfs ' /proc/mounts
test "$(uname -m)" = aarch64
grep -q '^KernelPageSize:[[:space:]]*4 kB$' /proc/self/smaps
awk 'NR > 1 && $1 ~ /^[0-9]+$/ && $4 !~ /^zram[0-9]+$/ { found=1 } END { exit found }' /proc/partitions
test ! -L /opt
test ! -L /opt/bin
test ! -L /run/codex-home
test ! -L /run/work
ntpd -n -q -p time.cloudflare.com
mkdir -p /opt/bin /etc/ssl/certs /run/codex-home /run/work
chmod 0700 /run/codex-home
wget -q -O /run/codex.tar.gz http://__HOST__:__PORT__/codex-aarch64-unknown-linux-musl.tar.gz
echo '5cda6182bd94c3a30f2eb63a495489ebf7f691fddb14d70f48c6c1a5071b6cde  /run/codex.tar.gz' | sha256sum -c -
tar -xzf /run/codex.tar.gz -C /opt/bin
mv /opt/bin/codex-aarch64-unknown-linux-musl /opt/bin/codex
rm /run/codex.tar.gz
wget -q -O /run/codex-host.tar.gz http://__HOST__:__PORT__/codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz
echo 'd8047b8d33370d6090e729d27eb76de60a2686baa1c143c138c9b05dc70d813b  /run/codex-host.tar.gz' | sha256sum -c -
tar -xzf /run/codex-host.tar.gz -C /opt/bin
mv /opt/bin/codex-code-mode-host-aarch64-unknown-linux-musl /opt/bin/codex-code-mode-host
rm /run/codex-host.tar.gz
wget -q -O /run/bwrap.tar.gz http://__HOST__:__PORT__/bwrap-aarch64-unknown-linux-musl.tar.gz
echo '2c6ea97dfb0a936b695ece6df058b89d4dfd53774a9ad852b3e4c98e6bbdfd20  /run/bwrap.tar.gz' | sha256sum -c -
tar -xzf /run/bwrap.tar.gz -C /opt/bin
mv /opt/bin/bwrap-aarch64-unknown-linux-musl /opt/bin/bwrap
rm /run/bwrap.tar.gz
wget -q -O /etc/ssl/certs/ca-certificates.crt http://__HOST__:__PORT__/ca-extracted/etc/ssl/certs/ca-certificates.crt
echo 'b8d837841b88bfaa1a0fa827cbca8e2576418dd47c9fc4bb7f1f9d89c83111b9  /etc/ssl/certs/ca-certificates.crt' | sha256sum -c -
ln -sf certs/ca-certificates.crt /etc/ssl/cert.pem
wget -q -O /opt/bin/codex-ram http://__HOST__:__PORT__/codex-ram
echo '__LAUNCHER_HASH__  /opt/bin/codex-ram' | sha256sum -c -
chmod 0755 /opt/bin/codex /opt/bin/codex-code-mode-host /opt/bin/bwrap /opt/bin/codex-ram
ln -sfn /opt/bin/codex-ram /usr/bin/codex
/opt/bin/codex-ram --version
/opt/bin/bwrap --version
free -m
'@
$remoteInstall = $remoteInstall.Replace('__HOST__', $HostAddress).Replace('__PORT__', [string]$HttpPort).Replace('__LAUNCHER_HASH__', $launcherHash)

$server = $null
try {
    $server = Start-Process -FilePath python.exe -ArgumentList @(
        '-m', 'http.server', [string]$HttpPort,
        '--bind', $HostAddress,
        '--directory', $artifactRoot
    ) -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 750
    if ($server.HasExited) {
        throw 'The temporary HTTP server exited before deployment.'
    }

    & ssh.exe -T @sshOptions "root@$AppleTvAddress" $remoteInstall
    if ($LASTEXITCODE -ne 0) {
        throw "RAM runtime deployment failed with ssh exit code $LASTEXITCODE."
    }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}

Write-Host 'Codex RAM runtime is ready. Internal storage was not touched.'
if ($RestoreState) {
    & (Join-Path $PSScriptRoot '..\codex-state\Restore-A1625CodexState.ps1') `
        -AppleTvAddress $AppleTvAddress `
        -SshKeyPath $SshKeyPath `
        -KnownHostsPath $KnownHostsPath
    if ($LASTEXITCODE -ne 0) {
        throw "Codex state restore failed with exit code $LASTEXITCODE."
    }
}
if ($Login) {
    $loginCommand = 'export TERM=xterm-256color; /opt/bin/codex-ram login --device-auth'
    & ssh.exe -tt @sshOptions "root@$AppleTvAddress" $loginCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Codex device login failed with ssh exit code $LASTEXITCODE."
    }
}
