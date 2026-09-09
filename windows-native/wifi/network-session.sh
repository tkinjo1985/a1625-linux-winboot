#!/bin/sh
# Run in the foreground under nohup; configuration and logs stay in RAM.
set -eu
umask 077
state=/run/a1625-wifi
test -s "$state/runner.pid"
runner=$(cat "$state/runner.pid")
kill -0 "$runner"
test -s "$state/wpa.conf"
test -x /run/a1625-wpa/sbin/wpa_supplicant
test -x /run/a1625-iw/usr/sbin/iw
test -x /usr/sbin/dropbear
test -s /run/dropbear_ed25519_host_key
mkdir "$state/network-lock"
cp /etc/resolv.conf "$state/resolv-before-network.conf"
ip route show | sed -n '/^default /p' > "$state/default-before-network.txt"
cleanup() {
    trap - EXIT INT TERM
    for name in dhcp dropbear wpa; do
        if test -s "$state/$name.pid"; then
            kill -TERM "$(cat "$state/$name.pid")" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
    ip route flush dev wlan0 2>/dev/null || true
    ifconfig wlan0 0.0.0.0 2>/dev/null || true
    if test -n "${previous_power_save:-}"; then
        LD_LIBRARY_PATH=/run/a1625-iw/usr/lib /run/a1625-iw/usr/sbin/iw \
            dev wlan0 set power_save "$previous_power_save" 2>/dev/null || true
    fi
    cp "$state/resolv-before-network.conf" /etc/resolv.conf
    while IFS= read -r route; do
        # Kernel-generated route tokens, intentionally split; never eval.
        test -z "$route" || ip route add $route 2>/dev/null || true
    done < "$state/default-before-network.txt"
    rm -f "$state/dhcp.pid" "$state/dropbear.pid" "$state/wpa.pid" \
        "$state/network.pid" "$state/lease-status" "$state/listen-address"
    rmdir "$state/network-lock"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
echo $$ > "$state/network.pid"
previous_power_save=$(LD_LIBRARY_PATH=/run/a1625-iw/usr/lib \
    /run/a1625-iw/usr/sbin/iw dev wlan0 get power_save | sed -n 's/^Power save: //p')
case "$previous_power_save" in on|off) ;; *) exit 1 ;; esac
# This mains-powered target showed intermittent inbound SSH stalls with PS on.
LD_LIBRARY_PATH=/run/a1625-iw/usr/lib /run/a1625-iw/usr/sbin/iw \
    dev wlan0 set power_save off
LD_LIBRARY_PATH=/run/a1625-wpa/usr/lib:/run/a1625-wpa/lib \
    /run/a1625-wpa/sbin/wpa_supplicant -D nl80211 -i wlan0 \
    -c "$state/wpa.conf" > "$state/wpa.log" 2>&1 &
wpa=$!
echo "$wpa" > "$state/wpa.pid"
attempt=0
while :; do
    kill -0 "$runner" && kill -0 "$wpa"
    if LD_LIBRARY_PATH=/run/a1625-wpa/usr/lib:/run/a1625-wpa/lib \
        /run/a1625-wpa/sbin/wpa_cli -p "$state/control" status 2>/dev/null \
        | grep -q '^wpa_state=COMPLETED$'; then break; fi
    attempt=$((attempt + 1))
    test "$attempt" -lt 60
    sleep 1
done
# Foreground DHCP remains supervised and renews the lease; do not use -q.
udhcpc -f -n -t 5 -T 3 -i wlan0 -s "$state/dhcp.sh" \
    > "$state/dhcp.log" 2>&1 &
dhcp=$!
echo "$dhcp" > "$state/dhcp.pid"
while kill -0 "$runner" && kill -0 "$wpa" && kill -0 "$dhcp"; do
    sleep 1
done
exit 1
