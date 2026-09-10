#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/ucrt64/bin:$PATH
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$script_dir/../../.." && pwd)"
kernel="${ANS_KERNEL_TREE:-$repo/third_party/HoolockLinux-linux-native}"
output="$repo/artifacts/ans-power-snapshot"
for required in scripts/module.lds include/generated/autoconf.h; do
    test -f "$kernel/$required" || { echo "Missing kernel prerequisite: $required" >&2; exit 1; }
done
extra_symbols=()
if [[ ! -f "$kernel/Module.symvers" ]]; then
    test -f "$kernel/vmlinux.symvers"
    extra_symbols=(KBUILD_EXTRA_SYMBOLS="$kernel/vmlinux.symvers")
fi
grep -qx 'CONFIG_ARM64_4K_PAGES=y' "$kernel/.config"
mkdir -p "$output"
cp "$script_dir/a1625_ans_power_snapshot.c" "$script_dir/Makefile" "$output/"
make -C "$kernel" M="$output" ARCH=arm64 LLVM=1 \
    CC="$repo/windows-native/wifi/pmu-probe/clang-external.sh" \
    LD="$repo/windows-native/msys-aarch64-ld-wrapper.sh" \
    HOSTCC="$script_dir/hostcc.sh" \
    HOSTLDFLAGS=-fuse-ld=bfd "${extra_symbols[@]}" modules
/ucrt64/bin/clang.exe --target=aarch64-linux-gnu -fuse-ld=lld \
    -nostdlib -static -ffreestanding -fno-stack-protector -fno-pie \
    -O2 -Wall -Wextra -Werror -Wl,-e,_start \
    "$repo/windows-native/wifi/pmu-probe/run_probe_once.c" -o "$output/run_probe_once"
sha256sum "$output/a1625_ans_power_snapshot.ko" "$output/run_probe_once"
