#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compat_header="$script_dir/kbuild-host-compat.h"
gcc_args=("$@")
output=""
has_c_source=false

for ((i = 0; i < ${#gcc_args[@]}; i++)); do
    if [[ "${gcc_args[i]}" == -o && $((i + 1)) -lt ${#gcc_args[@]} ]]; then
        output="${gcc_args[i + 1]}"
    fi
    if [[ "${gcc_args[i]}" == *.c ]]; then
        has_c_source=true
    fi
done

if $has_c_source; then
    /usr/bin/gcc -include "$compat_header" "${gcc_args[@]}"
else
    /usr/bin/gcc "${gcc_args[@]}"
fi

# MinGW appends .exe even when Kbuild requested an extensionless host tool.
# MSYS itself aliases those names, so use cmd.exe to create a distinct NTFS
# hard link at the exact path used by Kbuild prerequisites and recipes.
if [[ -n "$output" && ! "$output" =~ \.exe$ && -f "$output.exe" ]]; then
    windows_output_dir="$(cygpath -aw "$(dirname "$output")")"
    windows_output="$windows_output_dir\\$(basename "$output")"
    /c/Windows/System32/cmd.exe //d //c del //f //q "$windows_output" 2>/dev/null || true
    /c/Windows/System32/cmd.exe //d //c mklink //H "$windows_output" "$windows_output.exe" >/dev/null
fi
