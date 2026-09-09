#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/../../msys-clang-kbuild-wrapper.sh" "$@"
# External Kbuild runs in M=, so kernel include paths also need drive conversion.
for arg in "$@"; do
    case "$arg" in
        -Wp,-MMD,*|-Wp,-MD,*)
            depfile=${arg##*,}
            sed -i -E 's#([A-Za-z]):/#/\L\1/#g' "$depfile"
            ;;
    esac
done
