#!/usr/bin/env bash
# Native UCRT64 file-image utility only; no device operations.
set -euo pipefail
export PATH=/ucrt64/bin:/usr/bin:$PATH
root="$(cd "$(dirname "$0")/../.." && pwd)"
research="$root/artifacts/diagnostic-ramdisk-research"
archive="$research/xpwn-20c32e5.tar.gz"
expected=633a34c602bc95c27342eb63ac2502a15f7394ad8dcc9ace1781ba4bb2fb6e0d
actual="$(sha256sum "$archive" | cut -d ' ' -f 1)"
[[ "$actual" == "$expected" ]] || { echo 'xpwn archive hash mismatch' >&2; exit 1; }
tar -xf "$archive" -C "$research"
cd "$research/xpwn-20c32e5c12d1b22a9d55a59a0ff6267f539b77f4"
mkdir -p "$research/windows-tools"
gcc -O2 -Iincludes \
    common/abstractfile.c common/base64.c \
    hfs/btree.c hfs/catalog.c hfs/extents.c hfs/xattr.c \
    hfs/fastunicodecompare.c hfs/flatfile.c hfs/hfslib.c hfs/rawfile.c \
    hfs/utility.c hfs/volume.c hfs/hfscompress.c hfs/hfs.c \
    -lz -Wl,--no-insert-timestamp -o "$research/windows-tools/hfsplus.exe"
sha256sum "$research/windows-tools/hfsplus.exe"
