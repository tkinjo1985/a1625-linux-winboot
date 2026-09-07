Set-StrictMode -Version Latest

function Get-A1625DevelopmentProfile {
    param([Parameter(Mandatory)][ValidateSet('minimal', 'development')][string]$Profile)

    # BusyBox in the base initramfs supplies ntpd.  The layer adds the tools
    # whose packages cannot safely be assumed to be built into BusyBox.
    $minimal = @('git', 'ca-certificates-bundle', 'openssh-client-default')
    if ($Profile -eq 'development') {
        return @($minimal + @('build-base', 'pkgconf'))
    }
    $minimal
}

function ConvertFrom-A1625ApkIndex {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)

    $entries = [System.Collections.Generic.List[object]]::new()
    $name = $null; $version = $null; $depends = ''; $provides = ''
    foreach ($line in @($Lines + '')) {
        if ($line -eq '') {
            if ($name -and $version) {
                [void]$entries.Add([pscustomobject]@{
                    Name = $name; Version = $version
                    Depends = @($depends -split '\s+' | Where-Object { $_ })
                    Provides = @($provides -split '\s+' | Where-Object { $_ })
                })
            }
            $name = $null; $version = $null; $depends = ''; $provides = ''
        }
        elseif ($line -match '^([A-Za-z]):(.*)$') {
            if ($Matches[1] -ceq 'P') { $name = $Matches[2] }
            elseif ($Matches[1] -ceq 'V') { $version = $Matches[2] }
            elseif ($Matches[1] -ceq 'D') { $depends = $Matches[2] }
            elseif ($Matches[1] -ceq 'p') { $provides = $Matches[2] }
        }
    }
    $entries
}

function Get-A1625DependencyName {
    param([Parameter(Mandatory)][string]$Dependency)
    # Alpine constraints are attached to the atom.  We only accept an exact
    # package or one provider from the locked index; alternatives are refused.
    if ($Dependency -match '\|') { throw "Unsupported alternative dependency: $Dependency" }
    ($Dependency -replace '[<>=~].*$', '')
}

function Resolve-A1625AlpinePackages {
    param(
        [Parameter(Mandatory)][object[]]$Index,
        [Parameter(Mandatory)][string[]]$Roots
    )

    $byName = @{}
    $providers = @{}
    foreach ($package in $Index) {
        $byName[$package.Name] = $package
        foreach ($provided in $package.Provides) {
            $atom = Get-A1625DependencyName $provided
            if (-not $providers.ContainsKey($atom)) { $providers[$atom] = [System.Collections.Generic.List[object]]::new() }
            [void]$providers[$atom].Add($package)
        }
    }
    $resolved = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    # BusyBox rootfs is musl-based; replacing its dynamic loader in a RAM
    # overlay would risk the running SSH/recovery environment.
    $baseAtoms = @('so:libc.musl-aarch64.so.1')
    $visit = $null
    $visit = {
        param([string]$atom)
        if ($atom.StartsWith('!')) { return }
        if ($baseAtoms -contains $atom) { return }
        $name = Get-A1625DependencyName $atom
        $candidate = $byName[$name]
        if (-not $candidate) {
            $matches = @($providers[$name])
            if ($atom -match '[<>=~]') { $matches = @($matches | Where-Object { $_.Provides -contains $atom }) }
            if ($matches.Count -eq 0) { throw "Locked APKINDEX cannot resolve '$atom'." }
            # APKINDEX may retain ABI-compatible historical providers. Select
            # its highest version deterministically; the index itself is hash
            # pinned and each selected package hash is recorded in the lock.
            $candidate = @($matches | Sort-Object Version -Descending | Select-Object -First 1)[0]
        }
        if ($seen.ContainsKey($candidate.Name)) { return }
        $seen[$candidate.Name] = $true
        foreach ($dependency in $candidate.Depends) { & $visit $dependency }
        [void]$resolved.Add($candidate)
    }
    foreach ($root in $Roots) { & $visit $root }
    foreach ($package in $resolved) {
        foreach ($dependency in $package.Depends) {
            if ($dependency.StartsWith('!') -and $seen.ContainsKey((Get-A1625DependencyName $dependency.Substring(1)))) {
                throw "Conflicting locked dependency: $dependency"
            }
        }
    }
    $resolved
}

function Get-A1625ZramScript {
@'
#!/bin/sh
set -eu

# A1625/T7000 has about 2 GiB RAM. Cap compressed allocation to 256 MiB
# to leave headroom for USB gadget, SSH/ACM recovery and workload spikes.
# This uses the kernel's
# compiled zstd backend and never configures zram writeback/backing_dev.
readonly ZRAM_BYTES=$((768 * 1024 * 1024))
readonly ZRAM_PRIORITY=100
readonly ZRAM_MEMORY_LIMIT=$((256 * 1024 * 1024))

[ "$(uname -m)" = aarch64 ] || { echo 'zram: expected aarch64' >&2; exit 1; }
grep -q ' / rootfs ' /proc/mounts
grep -q ' /run tmpfs ' /proc/mounts
awk 'NR>1 && $1 ~ /^[0-9]+$/ && $4 !~ /^zram[0-9]+$/ {found=1} END {exit found}' /proc/partitions
[ -r /sys/block/zram0/comp_algorithm ] || { echo 'zram: zram0 is unavailable' >&2; exit 1; }
grep -qw zstd /sys/block/zram0/comp_algorithm || { echo 'zram: zstd backend unavailable' >&2; exit 1; }
test "$(sed -n 's/^KernelPageSize:[[:space:]]*\([0-9][0-9]*\) kB$/\1/p' /proc/self/smaps | head -n 1)" = 4 || { echo 'zram: expected 4 KiB pages' >&2; exit 1; }
test "$(cat /sys/block/zram0/backing_dev)" = none || { echo 'zram: writeback is configured; refusing to continue' >&2; exit 1; }
if grep -q '^/dev/zram0[[:space:]]' /proc/swaps; then
    grep -q '\[zstd\]' /sys/block/zram0/comp_algorithm || { echo 'zram: existing swap does not use zstd' >&2; exit 1; }
    test "$(cat /sys/block/zram0/disksize)" = "$ZRAM_BYTES"
    awk '$1=="/dev/zram0" && $5==100 {ok=1} END {exit !ok}' /proc/swaps
    awk '$4==268435456 {ok=1} END {exit !ok}' /sys/block/zram0/mm_stat
    cat /proc/swaps
    exit 0
fi
test "$(cat /sys/block/zram0/disksize)" = 0
echo zstd > /sys/block/zram0/comp_algorithm
echo "$ZRAM_MEMORY_LIMIT" > /sys/block/zram0/mem_limit
echo "$ZRAM_BYTES" > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null
swapon -p "$ZRAM_PRIORITY" /dev/zram0
grep -q '^/dev/zram0[[:space:]]' /proc/swaps || { echo 'zram: swapon did not take effect' >&2; exit 1; }
free -m
cat /proc/swaps
'@
}

Export-ModuleMember -Function Get-A1625DevelopmentProfile, ConvertFrom-A1625ApkIndex,
    Resolve-A1625AlpinePackages, Get-A1625ZramScript
