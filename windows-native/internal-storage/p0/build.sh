#!/usr/bin/env bash
set -euo pipefail
export PATH=/ucrt64/bin:/usr/bin:$PATH
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
src="$root/third_party/HoolockLinux-m1n1-p0"
test "$(git -C "$src" rev-parse HEAD)" = d5a10ac52a6468484854419a6c5130f1d62073eb
# Apply the patch to a clean pinned checkout; do not overwrite any local edits.
if git -C "$src" diff --quiet; then
    git -C "$src" apply "$root/windows-native/internal-storage/p0/m1n1-p0.patch"
fi
# New policy header is part of the reproducible diff, including after fresh apply.
git -C "$src" add -N -- src/rtkit_p0.h
git -C "$src" diff --binary -- src > "$src/build-p0-current.patch"
cmp "$src/build-p0-current.patch" "$root/windows-native/internal-storage/p0/m1n1-p0.patch"
export PATH=/ucrt64/bin:/usr/bin:$PATH
make -C "$src" USE_CLANG=1 ARCH=aarch64-none-elf CHAINLOADING=1 \
    EXTRA_CFLAGS=-DANS1_P0 LD="$root/windows-native/msys-aarch64-ld-wrapper.sh" \
    -j4 build/m1n1.bin
