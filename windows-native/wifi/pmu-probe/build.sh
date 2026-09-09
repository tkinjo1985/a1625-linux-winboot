#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/ucrt64/bin:$PATH
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$script_dir/../../.." && pwd)"
kernel="$repo/third_party/HoolockLinux-linux-native"
output="$repo/artifacts/wifi-pmu-probe"
for required in vmlinux.symvers scripts/module.lds include/generated/autoconf.h; do
    if [[ ! -f "$kernel/$required" ]]; then
        echo "Prepared kernel prerequisite missing: $required" >&2
        exit 1
    fi
done
mkdir -p "$output"
cp "$script_dir/a1625_pmu_probe.c" "$script_dir/a1625_gpio_probe.c" \
    "$script_dir/a1625_power_probe.c" "$script_dir/a1625_pcie_domains.c" \
    "$script_dir/a1625_radio_pulse.h" "$script_dir/a1625_pcie_domains.h" \
    "$script_dir/a1625_pcie_phy.h" "$script_dir/a1625_dart_lifetime.h" "$script_dir/a1625_dart_map.h" \
    "$script_dir/a1625_pci_scan.h" "$script_dir/a1625_pci_node.h" \
    "$script_dir/a1625_msi.h" \
    "$script_dir/Makefile" "$output/"
make -C "$kernel" M="$output" ARCH=arm64 LLVM=1 \
    CC="$script_dir/clang-external.sh" \
    LD="$repo/windows-native/msys-aarch64-ld-wrapper.sh" \
    HOSTCC="$repo/windows-native/msys-hostcc-kbuild-wrapper.sh" \
    HOSTLDFLAGS=-fuse-ld=bfd KBUILD_EXTRA_SYMBOLS="$kernel/vmlinux.symvers" modules
/ucrt64/bin/clang.exe --target=aarch64-linux-gnu -fuse-ld=lld \
    -nostdlib -static -ffreestanding -fno-stack-protector -fno-pie \
    -O2 -Wall -Wextra -Werror -Wl,-e,_start \
    "$script_dir/run_probe_once.c" -o "$output/run_probe_once"
sha256sum "$output/a1625_pmu_probe.ko" "$output/a1625_gpio_probe.ko" \
    "$output/a1625_power_probe.ko" "$output/a1625_pcie_domains.ko" "$output/run_probe_once"
