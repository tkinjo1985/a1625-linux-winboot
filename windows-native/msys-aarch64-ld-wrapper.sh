#!/usr/bin/env bash
set -euo pipefail

# The MSYS2 ld.lld executable does not select its ELF driver when invoked
# directly from this x64 Windows environment. Route raw Kbuild LD arguments
# through clang, which selects the AArch64 Linux ELF linker from --target.
clang_target="aarch64-linux-gnu"
if [[ "${1:-}" == --clang-target=* ]]; then
    clang_target="${1#--clang-target=}"
    shift
fi

clang_args=(
    "--target=$clang_target"
    -fuse-ld=lld
    -nostdlib
    -no-pie
)

while (($#)); do
    case "$1" in
        -o)
            clang_args+=("$1" "$2")
            shift 2
            ;;
        -T|-z|-m|-Map|--script|--version-script|--dynamic-list)
            clang_args+=("-Wl,$1,$2")
            shift 2
            ;;
        -*)
            clang_args+=("-Wl,$1")
            shift
            ;;
        *)
            clang_args+=("$1")
            shift
            ;;
    esac
done

exec /ucrt64/bin/clang.exe "${clang_args[@]}"
