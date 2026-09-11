#!/usr/bin/env bash
set -euo pipefail
export PATH="/ucrt64/bin:/usr/bin:/c/Program Files/Git/cmd:/c/Users/tkinj/.cargo/bin:$PATH"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
src="$root/third_party/HoolockLinux-m1n1-p0"
git_bin="${P0_GIT:-$(command -v git || true)}"
python_bin="${P0_PYTHON:-$(command -v python || true)}"
for tool in "$git_bin" "$python_bin" "$(command -v make || true)" \
            "$(command -v clang || true)" "$(command -v llvm-objcopy || true)" \
            "$(command -v cargo || true)"; do
    test -n "$tool" && test -x "$tool" || { echo "missing required build tool" >&2; exit 1; }
done
test "$("$git_bin" -C "$src" rev-parse HEAD)" = d5a10ac52a6468484854419a6c5130f1d62073eb
# Build-metadata policy is separate from the device-code patch.
metadata_patch="$root/windows-native/internal-storage/p0/build-metadata.patch"
if "$git_bin" -C "$src" diff --quiet -- version.sh; then
    "$git_bin" -C "$src" apply "$metadata_patch"
fi
"$git_bin" -C "$src" diff --binary -- version.sh > "$src/build-metadata-current.patch"
cmp "$src/build-metadata-current.patch" "$metadata_patch"
# Apply the patch to a clean pinned checkout; do not overwrite any local edits.
if "$git_bin" -C "$src" diff --quiet; then
    "$git_bin" -C "$src" apply "$root/windows-native/internal-storage/p0/m1n1-p0.patch"
fi
# New policy header is part of the reproducible diff, including after fresh apply.
"$git_bin" -C "$src" add -N -- src/rtkit_p0.h
"$git_bin" -C "$src" diff --binary -- src > "$src/build-p0-current.patch"
cmp "$src/build-p0-current.patch" "$root/windows-native/internal-storage/p0/m1n1-p0.patch"
"$python_bin" "$root/windows-native/internal-storage/p0/build-quality.py" prepare \
    --src "$src" --git "$git_bin" --shell /usr/bin/sh \
    --header "$src/build/build_tag.h"
make -C "$src" USE_CLANG=1 ARCH=aarch64-none-elf CHAINLOADING=1 \
    EXTRA_CFLAGS=-DANS1_P0 LD="$root/windows-native/msys-aarch64-ld-wrapper.sh" \
    -j4 build/m1n1.bin
"$python_bin" "$root/windows-native/internal-storage/p0/build-quality.py" verify \
    --src "$src" --git "$git_bin" --header "$src/build/build_tag.h" \
    --elf "$src/build/m1n1-raw.elf" --payload "$src/build/m1n1.bin" \
    --output "$src/build/build-quality.json"
