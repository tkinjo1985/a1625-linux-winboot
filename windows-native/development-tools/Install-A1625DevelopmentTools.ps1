#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('minimal', 'development')][string]$Profile = 'minimal',
    [ValidateSet('172.16.42.1')][string]$AppleTvAddress = '172.16.42.1',
    [ValidateSet('172.16.42.2')][string]$HostAddress = '172.16.42.2',
    [ValidateRange(1024, 65535)][int]$HttpPort = 8082,
    [string]$SshKeyPath = (Join-Path $PSScriptRoot '..\..\artifacts\ssh\a1625_ram_ed25519'),
    [string]$KnownHostsPath,
    [string]$WorkDirectory = '/run/work',
    [switch]$EnableZram,
    [switch]$PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'A1625DevelopmentTools.psm1') -Force

if ($WorkDirectory -notmatch '^/run/[A-Za-z0-9._/-]+$' -or $WorkDirectory.Contains('..')) {
    throw 'WorkDirectory must be a simple absolute path below /run without parent traversal.'
}
if (-not $PrepareOnly -and [string]::IsNullOrWhiteSpace($KnownHostsPath)) {
    throw 'KnownHostsPath is required for deployment and must be the verified key for this RAM boot.'
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$artifactRoot = Join-Path $repoRoot 'artifacts\development-tools\alpine-v3.23-aarch64'
$stageRoot = Join-Path $artifactRoot $Profile
$indexArchive = Join-Path $artifactRoot 'APKINDEX.tar.gz'
$indexHash = 'BA325A020DB9BB220CF5A0A3EDF49937F6FF704B4D8F3F822CE3D176BF367798'
$repository = 'https://dl-cdn.alpinelinux.org/alpine/v3.23/main/aarch64'

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for $Path`nExpected: $Expected`nActual:   $actual" }
}
function Get-VerifiedFile([string]$Uri, [string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Path
    }
    Assert-Sha256 $Path $Expected
}

New-Item -ItemType Directory -Force -Path $artifactRoot, $stageRoot | Out-Null
Get-VerifiedFile "$repository/APKINDEX.tar.gz" $indexArchive $indexHash
$indexText = @(& tar.exe -xOf $indexArchive ./APKINDEX)
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the verified Alpine APKINDEX.' }
$packages = Resolve-A1625AlpinePackages -Index (ConvertFrom-A1625ApkIndex $indexText) -Roots (Get-A1625DevelopmentProfile $Profile)
$packageLock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'packages.lock.json') -Raw | ConvertFrom-Json
if ($packageLock.format -ne 'a1625-alpine-v3.23-aarch64-lock-v1' -or $packageLock.apkIndexSha256 -ne $indexHash) { throw 'Package lock format or index hash mismatch.' }
$expectedPackages = @($packageLock.profiles.$Profile)
if ($expectedPackages.Count -ne @($packages).Count) { throw 'Resolved package set differs from the reviewed lock.' }

$packageRoot = Join-Path $stageRoot 'packages'
$bundleRoot = Join-Path $stageRoot 'bundle-input'
New-Item -ItemType Directory -Force -Path $packageRoot, $bundleRoot | Out-Null
$locked = [System.Collections.Generic.List[object]]::new()
foreach ($package in $packages) {
    $fileName = "$($package.Name)-$($package.Version).apk"
    $path = Join-Path $packageRoot $fileName
    $expected = @($expectedPackages | Where-Object { $_.file -ceq $fileName -and $_.name -ceq $package.Name -and $_.version -ceq $package.Version })
    if ($expected.Count -ne 1 -or $expected[0].sha256 -notmatch '^[A-F0-9]{64}$') { throw "Package is missing from the reviewed lock: $fileName" }
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest -UseBasicParsing -Uri "$repository/$fileName" -OutFile $path }
    Assert-Sha256 $path $expected[0].sha256
    $hash = $expected[0].sha256
    $locked.Add([ordered]@{ name = $package.Name; version = $package.Version; file = $fileName; sha256 = $hash })
}
$manifest = [ordered]@{
    format = 'a1625-development-layer-v1'; profile = $Profile; target = 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000'
    repository = $repository; apkIndexSha256 = $indexHash; packages = $locked
    zram = [ordered]@{ bytes = 805306368; memoryLimitBytes = 268435456; compressor = 'zstd'; swapPriority = 100; writeback = $false }
} | ConvertTo-Json -Depth 6
$manifestPath = Join-Path $stageRoot 'manifest.json'
Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding utf8
$lockHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifest)))
$zramSource = Join-Path $bundleRoot 'a1625-zram-enable'
Set-Content -LiteralPath $zramSource -Value (Get-A1625ZramScript) -Encoding utf8 -NoNewline
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'a1625-tool') -Destination (Join-Path $bundleRoot 'a1625-tool') -Force
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'manifest.json') -Force
foreach ($package in $locked) { Copy-Item -LiteralPath (Join-Path $packageRoot $package.file) -Destination (Join-Path $bundleRoot $package.file) -Force }
$bundle = Join-Path $stageRoot "a1625-$Profile-packages.tar.gz"
$deterministicTar = Join-Path $PSScriptRoot 'build_deterministic_tar.py'
$bundleInspectionJson = & python.exe $deterministicTar $bundleRoot $bundle
if ($LASTEXITCODE -ne 0) { throw 'Could not create the deterministic development package archive.' }
$bundleInspection = $bundleInspectionJson | ConvertFrom-Json
$bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash
$manifestObject = $manifest | ConvertFrom-Json
$manifestObject | Add-Member -NotePropertyName bundle -NotePropertyValue ([ordered]@{
    file = [IO.Path]::GetFileName($bundle); sha256 = $bundleHash; bytes = (Get-Item -LiteralPath $bundle).Length
})
$manifestObject | Add-Member -NotePropertyName lockSha256 -NotePropertyValue $lockHash
Set-Content -LiteralPath $manifestPath -Value ($manifestObject | ConvertTo-Json -Depth 6) -Encoding utf8
$runtimeMarkerJson = $manifestObject | ConvertTo-Json -Depth 6 -Compress
$result = [pscustomobject]@{ Profile = $Profile; BundlePath = $bundle; ManifestPath = $manifestPath; LockSha256 = $lockHash; BundleSha256 = $bundleHash; BundleBytes = (Get-Item -LiteralPath $bundle).Length; ExpandedBytes = $bundleInspection.expandedBytes }
if ($PrepareOnly) { $result; return }

foreach ($tool in 'ssh.exe', 'python.exe') { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required host tool was not found: $tool" } }
foreach ($path in $SshKeyPath, $KnownHostsPath) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required SSH file was not found: $path" } }
$server = $null
try {
    $server = Start-Process python.exe -ArgumentList @('-m', 'http.server', $HttpPort, '--bind', $HostAddress, '--directory', $stageRoot) -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 750
    if ($server.HasExited) { throw 'The temporary HTTP server exited before deployment.' }
    $zramCommand = if ($EnableZram) { '/run/a1625-tools/root/opt/bin/a1625-zram-enable' } else { ':' }
    $remote = @"
set -eu
set -o pipefail
test "`$(uname -m)" = aarch64
grep -q '^KernelPageSize:[[:space:]]*4 kB$' /proc/self/smaps
grep -q ' /run tmpfs ' /proc/mounts
grep -q ' / rootfs ' /proc/mounts
awk 'NR>1 && `$1 ~ /^[0-9]+$/ && `$4 !~ /^zram[0-9]+$/ {found=1} END {exit found}' /proc/partitions
test ! -L /run/a1625-layer
test ! -L /run/a1625-tools
test ! -L /run/a1625-tools/root
test ! -L /opt/bin
test ! -e /run/a1625-tools/root.previous
mkdir -p /run/work /run/a1625-layer /run/a1625-tools /opt/bin
mkdir /run/.a1625-tools-install-lock
nextroot=/run/a1625-tools/root.next.`$`$
committed=0; root_changed=0; wrappers_changed=0
wrapper_names='a1625-tool a1625-git git ssh ssh-keygen scp sftp cc gcc c++ g++ cpp make pkgconf pkg-config ar as ld nm ranlib strip objcopy objdump size strings file patch'
wrapper_backup=/run/.a1625-tools-install-lock/wrappers
cleanup() {
  status=`$?
  trap - EXIT HUP INT TERM
  if test "`$committed" = 0; then
    if test -d /run/a1625-tools/root.previous; then
      rm -rf /run/a1625-tools/root
      mv /run/a1625-tools/root.previous /run/a1625-tools/root || exit 71
    elif test "`$root_changed" = 1; then
      rm -rf /run/a1625-tools/root
    fi
    if test "`$wrappers_changed" = 1; then
      for tool in `$wrapper_names; do
        rm -f "/opt/bin/`$tool"
        if test -e "`$wrapper_backup/`$tool" || test -L "`$wrapper_backup/`$tool"; then
          mv "`$wrapper_backup/`$tool" "/opt/bin/`$tool" || exit 72
        fi
      done
      rm -f /run/a1625-development-layer.json
      test ! -f /run/.a1625-tools-install-lock/old-manifest || mv /run/.a1625-tools-install-lock/old-manifest /run/a1625-development-layer.json
    fi
  fi
  rm -rf "`$nextroot"
  rm -rf /run/.a1625-tools-install-lock
  exit "`$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
neededkb=$([long][Math]::Ceiling(($bundleInspection.expandedBytes + 2 * $result.BundleBytes) / 1024) + 65536)
availablekb=`$(df -Pk /run | awk 'NR==2 {print `$4}')
test "`$availablekb" -gt "`$neededkb"
mkdir "`$nextroot"
mkdir "`$wrapper_backup"
for tool in `$wrapper_names; do
  test ! -d "/opt/bin/`$tool"
  if test -e "/opt/bin/`$tool" || test -L "/opt/bin/`$tool"; then cp -a "/opt/bin/`$tool" "`$wrapper_backup/`$tool"; fi
done
test ! -f /run/a1625-development-layer.json || cp /run/a1625-development-layer.json /run/.a1625-tools-install-lock/old-manifest
rm -rf /run/a1625-layer
mkdir /run/a1625-layer
wget -q -O /run/a1625-layer/layer.tar.gz http://$HostAddress`:$HttpPort/$([IO.Path]::GetFileName($bundle))
echo '$($bundleHash.ToLowerInvariant())  /run/a1625-layer/layer.tar.gz' | sha256sum -c -
tar -xzf /run/a1625-layer/layer.tar.gz -C /run/a1625-layer
test -s /run/a1625-layer/manifest.json
$(($locked | ForEach-Object { "echo '$($_.sha256.ToLowerInvariant())  /run/a1625-layer/$($_.file)' | sha256sum -c -" }) -join "`n")
$(($locked | ForEach-Object { "tar -xzf '/run/a1625-layer/$($_.file)' -C `"`$nextroot`"" }) -join "`n")
find "`$nextroot" -type f -perm +6000 -exec chmod a-s {} \;
mkdir -p "`$nextroot/opt/bin"
mv /run/a1625-layer/a1625-zram-enable "`$nextroot/opt/bin/a1625-zram-enable"
chmod 0755 "`$nextroot/opt/bin/a1625-zram-enable"
test ! -d /run/a1625-tools/root || mv /run/a1625-tools/root /run/a1625-tools/root.previous
mv "`$nextroot" /run/a1625-tools/root
root_changed=1
rm -f /run/a1625-layer/*.apk /run/a1625-layer/layer.tar.gz
wrappers_changed=1
mv /run/a1625-layer/a1625-tool /opt/bin/a1625-tool
chmod 0755 /opt/bin/a1625-tool
for tool in ssh ssh-keygen scp sftp cc gcc c++ g++ cpp make pkgconf pkg-config ar as ld nm ranlib strip objcopy objdump size strings file patch; do
  if test -x "/run/a1625-tools/root/usr/bin/`$tool"; then
    ln -sfn /opt/bin/a1625-tool "/opt/bin/`$tool"
  elif test "`$(readlink "/opt/bin/`$tool" 2>/dev/null || true)" = /opt/bin/a1625-tool; then
    rm "/opt/bin/`$tool"
  fi
done
cat >/opt/bin/a1625-git <<'EOF'
#!/bin/sh
set -eu
readonly TOOLROOT=/run/a1625-tools/root
export LD_LIBRARY_PATH="`$TOOLROOT/usr/lib`${LD_LIBRARY_PATH:+:`$LD_LIBRARY_PATH}"
export GIT_EXEC_PATH="`$TOOLROOT/usr/libexec/git-core"
export GIT_TEMPLATE_DIR="`$TOOLROOT/usr/share/git-core/templates"
export PATH="/opt/bin:`$TOOLROOT/usr/bin:`$TOOLROOT/usr/libexec/git-core:`$PATH"
export HOME=/run/codex-home
export SSL_CERT_FILE="`$TOOLROOT/etc/ssl/certs/ca-certificates.crt"
exec "`$TOOLROOT/usr/bin/git" "`$@"
EOF
chmod 0755 /opt/bin/a1625-git
ln -sfn /opt/bin/a1625-git /opt/bin/git
export HOME=/run/codex-home GIT_CONFIG_GLOBAL=/run/codex-home/.gitconfig SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
/opt/bin/a1625-git --version
date -u +%FT%TZ
$zramCommand
printf '%s\n' '$($runtimeMarkerJson.Replace("'", "'\\''"))' > /run/a1625-development-layer.json
committed=1
rm -rf /run/a1625-tools/root.previous
"@
    $ssh = @('-T','-i',[IO.Path]::GetFullPath($SshKeyPath),'-o','BatchMode=yes','-o','ConnectTimeout=5','-o','StrictHostKeyChecking=yes','-o',('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath)))
    # Keep the public success stream reserved for the result object.  The
    # restore wrapper compares that object to its PrepareOnly preflight.
    # Pass larger profile scripts over stdin, avoiding Dropbear's bounded SSH
    # exec-request command length.
    Import-Module (Join-Path $PSScriptRoot '../codex-state/A1625CodexState.psm1') -Force
    $installOutput = Invoke-A1625SshUpload -SshArguments $ssh -AppleTvAddress $AppleTvAddress `
        -RemoteCommand 'sh -s' -Payload ([Text.Encoding]::UTF8.GetBytes($remote.Replace("`r", '')))
    Write-Host $installOutput
} finally { if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id } }
$result
