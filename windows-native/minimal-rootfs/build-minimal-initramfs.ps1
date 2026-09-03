[CmdletBinding()]
param(
    [string]$AuthorizedKeyPath,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $AuthorizedKeyPath) {
    $AuthorizedKeyPath = Join-Path $repoRoot 'artifacts\ssh\a1625_ram_ed25519.pub'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'artifacts\minimal-rootfs'
}

$sources = [ordered]@{
    init = Join-Path $PSScriptRoot 'init'
    getty = Join-Path $PSScriptRoot 'ram-getty'
    passwd = Join-Path $PSScriptRoot 'passwd'
    group = Join-Path $PSScriptRoot 'group'
    shadow = Join-Path $PSScriptRoot 'shadow'
    authorizedKey = $AuthorizedKeyPath
    busybox = Join-Path $repoRoot 'artifacts\hoolock\hoolockrd\unpacked\bin\busybox'
    loader = Join-Path $repoRoot 'artifacts\hoolock\hoolockrd\unpacked\lib\ld-musl-aarch64.so.1'
    unudhcpd = Join-Path $repoRoot 'artifacts\hoolock\hoolockrd\inner\bin\unudhcpd'
    dropbear = Join-Path $repoRoot 'artifacts\ssh\bundle-source-v1\dropbear'
    dropbearkey = Join-Path $repoRoot 'artifacts\ssh\bundle-source-v1\dropbearkey'
    zlib = Join-Path $repoRoot 'artifacts\ssh\bundle-source-v1\libz.so.1.3.2'
    utmps = Join-Path $repoRoot 'artifacts\ssh\bundle-source-v1\libutmps.so.0.1.3.1'
    skalibs = Join-Path $repoRoot 'artifacts\ssh\bundle-source-v1\libskarnet.so.2.14.4.0'
}

foreach ($key in @($sources.Keys)) {
    $sources[$key] = (Resolve-Path -LiteralPath $sources[$key]).Path
    if ($sources[$key] -match '\s') {
        throw "gen_init_cpio manifest paths cannot contain whitespace: $($sources[$key])"
    }
}

$publicKey = (Get-Content -LiteralPath $sources.authorizedKey -Raw).Trim()
if ($publicKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,2}(\s+.*)?$') {
    throw 'AuthorizedKeyPath must contain exactly one OpenSSH Ed25519 public key'
}
if ($publicKey -match 'PRIVATE KEY') {
    throw 'Refusing to embed a private SSH key'
}

$kernelConfig = Join-Path $repoRoot 'third_party\HoolockLinux-linux-native\.config'
if ((Test-Path -LiteralPath $kernelConfig) -and
    -not (Select-String -LiteralPath $kernelConfig -Pattern '^CONFIG_ARM64_4K_PAGES=y$' -Quiet)) {
    throw 'A1625/T7000 kernel config must set CONFIG_ARM64_4K_PAGES=y'
}

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$toolPath = Join-Path $OutputDirectory 'gen_init_cpio.exe'
$toolSource = Join-Path $repoRoot 'artifacts\hoolock\kernel-build\source\usr\gen_init_cpio.c'
$compatHeader = Join-Path $repoRoot 'windows-native\kbuild-host-compat.h'
$userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$msysShell = Join-Path $userProfilePath 'scoop\apps\msys2\current\msys2_shell.cmd'
if (-not (Test-Path -LiteralPath $msysShell)) {
    throw 'Native MSYS2 shell was not found under the Scoop installation'
}

function As-MsysPath([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($resolved -notmatch '^([A-Za-z]):/(.*)$') {
        throw "Cannot convert path to MSYS form: $Path"
    }
    return "/$($Matches[1].ToLowerInvariant())/$($Matches[2])"
}

$compileCommand = "gcc -O2 -include '$(As-MsysPath $compatHeader)' -o '$(As-MsysPath $toolPath)' '$(As-MsysPath $toolSource)'"
& $msysShell -defterm -no-start -msys -c $compileCommand
if ($LASTEXITCODE -ne 0) {
    throw "gen_init_cpio build failed with exit code $LASTEXITCODE"
}

function As-ManifestPath([string]$Path) {
    return As-MsysPath $Path
}

$manifestPath = Join-Path $OutputDirectory 'minimal-initramfs.list'
$manifest = @(
    'dir /bin 0755 0 0'
    'dir /sbin 0755 0 0'
    'dir /lib 0755 0 0'
    'dir /usr 0755 0 0'
    'dir /usr/bin 0755 0 0'
    'dir /usr/sbin 0755 0 0'
    'dir /usr/lib 0755 0 0'
    'dir /etc 0755 0 0'
    'dir /root 0700 0 0'
    'dir /root/.ssh 0700 0 0'
    'dir /proc 0555 0 0'
    'dir /sys 0555 0 0'
    'dir /dev 0755 0 0'
    'dir /run 0755 0 0'
    'dir /tmp 01777 0 0'
    'dir /config 0755 0 0'
    'nod /dev/console 0600 0 0 c 5 1'
    'nod /dev/null 0666 0 0 c 1 3'
    "file /init $(As-ManifestPath $sources.init) 0755 0 0"
    "file /bin/busybox $(As-ManifestPath $sources.busybox) 0755 0 0"
    "file /bin/unudhcpd $(As-ManifestPath $sources.unudhcpd) 0755 0 0"
    "file /sbin/ram-getty $(As-ManifestPath $sources.getty) 0755 0 0"
    "file /lib/ld-musl-aarch64.so.1 $(As-ManifestPath $sources.loader) 0755 0 0"
    'slink /lib/libc.musl-aarch64.so.1 ld-musl-aarch64.so.1 0777 0 0'
    "file /usr/sbin/dropbear $(As-ManifestPath $sources.dropbear) 0755 0 0"
    "file /usr/bin/dropbearkey $(As-ManifestPath $sources.dropbearkey) 0755 0 0"
    "file /usr/lib/libz.so.1.3.2 $(As-ManifestPath $sources.zlib) 0755 0 0"
    'slink /usr/lib/libz.so.1 libz.so.1.3.2 0777 0 0'
    "file /usr/lib/libutmps.so.0.1.3.1 $(As-ManifestPath $sources.utmps) 0755 0 0"
    'slink /usr/lib/libutmps.so.0.1 libutmps.so.0.1.3.1 0777 0 0'
    "file /usr/lib/libskarnet.so.2.14.4.0 $(As-ManifestPath $sources.skalibs) 0755 0 0"
    'slink /usr/lib/libskarnet.so.2.14 libskarnet.so.2.14.4.0 0777 0 0'
    "file /etc/passwd $(As-ManifestPath $sources.passwd) 0644 0 0"
    "file /etc/group $(As-ManifestPath $sources.group) 0644 0 0"
    "file /etc/shadow $(As-ManifestPath $sources.shadow) 0600 0 0"
    "file /root/.ssh/authorized_keys $(As-ManifestPath $sources.authorizedKey) 0600 0 0"
)
$manifest | Set-Content -LiteralPath $manifestPath -Encoding ascii

$cpioPath = Join-Path $OutputDirectory 'minimal-initramfs.cpio'
$archiveCommand = "'$(As-MsysPath $toolPath)' -t 0 -o '$(As-MsysPath $cpioPath)' '$(As-MsysPath $manifestPath)'"
& $msysShell -defterm -no-start -msys -c $archiveCommand
if ($LASTEXITCODE -ne 0) {
    throw "gen_init_cpio failed with exit code $LASTEXITCODE"
}

$gzip = 'C:\Program Files\Git\usr\bin\gzip.exe'
if (-not (Test-Path -LiteralPath $gzip)) {
    throw 'Git for Windows gzip.exe was not found'
}
& $gzip -n -9 -f $cpioPath
if ($LASTEXITCODE -ne 0) {
    throw "gzip failed with exit code $LASTEXITCODE"
}

$gzipPath = "$cpioPath.gz"
$result = [ordered]@{
    target = 'Apple TV HD A1625 / AppleTV5,3 / J42d / T7000'
    storage = 'RAM-only initramfs; no internal-storage mount or write commands'
    authentication = 'Dropbear Ed25519 public-key only; password and forwarding disabled'
    authorized_key_fingerprint = (& ssh-keygen.exe -lf $sources.authorizedKey)
    initramfs = [ordered]@{
        path = $gzipPath
        bytes = (Get-Item -LiteralPath $gzipPath).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $gzipPath).Hash
    }
}
$resultPath = Join-Path $OutputDirectory 'minimal-initramfs.manifest.json'
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8
$result | ConvertTo-Json -Depth 5
