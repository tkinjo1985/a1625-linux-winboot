#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output=""
has_source=false
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[i]}" == -o && $((i+1)) -lt ${#args[@]} ]]; then output="${args[i+1]}"; fi
    if [[ "${args[i]}" == *.c ]]; then has_source=true; fi
done
if $has_source; then
    /usr/bin/gcc -include "$here/../../kbuild-host-compat.h" "$@"
else
    /usr/bin/gcc "$@"
fi
if [[ -n "$output" && "$output" != *.exe && -f "$output.exe" ]]; then
    /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive \
        -File "$(cygpath -aw "$here/Set-HostToolLink.ps1")" \
        -OutputPath "$(cygpath -aw "$(dirname -- "$output")")\\$(basename -- "$output")"
fi
