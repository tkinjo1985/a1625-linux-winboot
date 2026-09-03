#!/usr/bin/env bash
set -euo pipefail

# Native Windows clang writes Make dependency files with CRLF. Linux Kbuild's
# fixdep treats the trailing CR as part of a prerequisite name, so normalize
# only the dependency file produced by this compiler invocation.
depfile=""
for arg in "$@"; do
    case "$arg" in
        -Wp,-MMD,*) depfile="${arg#-Wp,-MMD,}" ;;
        -Wp,-MD,*) depfile="${arg#-Wp,-MD,}" ;;
    esac
done

/ucrt64/bin/clang.exe "$@"

if [[ -n "$depfile" && -f "$depfile" ]]; then
    sed -i 's/\r$//' "$depfile"

    # clang canonicalizes absolute MSYS include arguments to C:/... paths.
    # fixdep interprets the drive-letter colon as Make syntax, so rewrite only
    # the current kernel tree prefix to the equivalent relative dependency.
    windows_pwd="$(cygpath -am "$PWD")"
    escaped_windows_pwd="${windows_pwd//&/\\&}"
    sed -i "s#${escaped_windows_pwd}/##g" "$depfile"
fi
