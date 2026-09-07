#!/bin/sh
set -eu
export PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/run/codex-home
grep -q ' /run tmpfs ' /proc/mounts
test ! -L /run/work
check=/run/work/.a1625-development-check.$$
mkdir "$check"
trap 'rm -rf "$check"' EXIT
trap 'exit 130' HUP INT TERM
git --version
ssh -V 2>&1
cc --version | head -n 1
make --version | head -n 1
pkg-config --version
cat > "$check/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("a1625_c_toolchain_ok"); return 0; }
EOF
cc -Wall -Werror "$check/hello.c" -o "$check/hello"
"$check/hello"
cat > "$check/hello.cpp" <<'EOF'
#include <iostream>
int main() { std::cout << "a1625_cpp_toolchain_ok\n"; }
EOF
g++ -Wall -Werror "$check/hello.cpp" -o "$check/hello-cpp"
LD_LIBRARY_PATH=/run/a1625-tools/root/usr/lib "$check/hello-cpp"
du -sk /run/a1625-tools
free -m
cat /proc/swaps
echo a1625_development_verified
