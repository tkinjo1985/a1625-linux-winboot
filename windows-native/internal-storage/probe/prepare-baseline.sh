#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/ucrt64/bin:$PATH
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$here/../../.." && pwd)"
kernel="$repo/artifacts/ans-baseline-kernel"
test -f "$kernel/.config"
test -f "$kernel/Module.symvers"
printf '%s  %s\n' \
    '284e7e590f6a4b748a1292fe35ef1888bdef1aaa1460ca10597d7f05b4e62dd5' \
    "$repo/artifacts/wifi-kernel-config/base-before-wifi-build/.config" \
    '9e14414c3b53cdaae579c286ab628c384cd9746dabf78f3fd1cbb6c17bf72a4c' \
    "$kernel/Module.symvers" | sha256sum -c -
args=(-C "$kernel" ARCH=arm64 LLVM=1
    CC="$repo/windows-native/msys-clang-kbuild-wrapper.sh"
    LD="$repo/windows-native/msys-aarch64-ld-wrapper.sh"
    HOSTCC="$here/hostcc.sh" HOSTLDFLAGS=-fuse-ld=bfd)
make "${args[@]}" olddefconfig
make "${args[@]}" -j4 modules_prepare
