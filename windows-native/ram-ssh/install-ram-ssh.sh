#!/bin/sh
set -eu

SOURCE_DIR="${1:-/tmp/a1625-ram-ssh}"

if ! grep -q ' / rootfs ' /proc/mounts; then
    echo "Refusing SSH install: / is not a RAM rootfs" >&2
    exit 1
fi

for file in dropbear dropbearkey libz.so.1.3.2 libutmps.so.0.1.3.1 \
    libskarnet.so.2.14.4.0 authorized_keys; do
    if [ ! -f "$SOURCE_DIR/$file" ]; then
        echo "Missing bundle file: $SOURCE_DIR/$file" >&2
        exit 1
    fi
done

mkdir -p /usr/sbin /usr/bin /usr/lib /etc /root/.ssh /run
install -m 0755 "$SOURCE_DIR/dropbear" /usr/sbin/dropbear
install -m 0755 "$SOURCE_DIR/dropbearkey" /usr/bin/dropbearkey
install -m 0755 "$SOURCE_DIR/libz.so.1.3.2" /usr/lib/libz.so.1.3.2
install -m 0755 "$SOURCE_DIR/libutmps.so.0.1.3.1" /usr/lib/libutmps.so.0.1.3.1
install -m 0755 "$SOURCE_DIR/libskarnet.so.2.14.4.0" /usr/lib/libskarnet.so.2.14.4.0
ln -sf libz.so.1.3.2 /usr/lib/libz.so.1
ln -sf libutmps.so.0.1.3.1 /usr/lib/libutmps.so.0.1
ln -sf libskarnet.so.2.14.4.0 /usr/lib/libskarnet.so.2.14

cat > /etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat > /etc/group <<'EOF'
root:x:0:
EOF
cat > /etc/shadow <<'EOF'
root:!:1:0:99999:7:::
EOF
chmod 0644 /etc/passwd /etc/group
chmod 0600 /etc/shadow
install -m 0600 "$SOURCE_DIR/authorized_keys" /root/.ssh/authorized_keys
chmod 0700 /root /root/.ssh

HOST_KEY=/run/dropbear_ed25519_host_key
if [ ! -f "$HOST_KEY" ]; then
    /usr/bin/dropbearkey -t ed25519 -f "$HOST_KEY"
fi
chmod 0600 "$HOST_KEY"

if [ -f /run/dropbear.pid ] && kill -0 "$(cat /run/dropbear.pid)" 2>/dev/null; then
    echo "Dropbear is already running with PID $(cat /run/dropbear.pid)"
    exit 0
fi

/usr/sbin/dropbear \
    -E \
    -s \
    -j \
    -k \
    -p 172.16.42.1:22 \
    -r "$HOST_KEY" \
    -P /run/dropbear.pid

echo "Dropbear started on 172.16.42.1:22 with public-key-only authentication"
