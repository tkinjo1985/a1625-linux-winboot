#!/bin/sh
set -eu
test "$interface" = wlan0
state=/run/a1625-wifi
umask 077
case "$1" in
deconfig)
    if test -s "$state/dropbear.pid"; then
        kill -TERM "$(cat "$state/dropbear.pid")" 2>/dev/null || true
    fi
    rm -f "$state/dropbear.pid" "$state/listen-address" "$state/lease-status"
    ip route flush dev wlan0 2>/dev/null || true
    /sbin/ifconfig wlan0 0.0.0.0
    if test -f "$state/resolv-before-network.conf"; then
        cp "$state/resolv-before-network.conf" /etc/resolv.conf
    fi
    exit 0 ;;
bound|renew)
    test -n "${ip:-}" && test -n "${subnet:-}"
    /sbin/ifconfig wlan0 "$ip" netmask "$subnet" up
    for gateway in ${router:-}; do
        ip route replace default via "$gateway" dev wlan0
        break
    done
    if test -n "${dns:-}"; then
        umask 077
        : > /run/a1625-wifi/resolv.conf
        for server in $dns; do printf 'nameserver %s\n' "$server" >> /run/a1625-wifi/resolv.conf; done
        cat /run/a1625-wifi/resolv.conf > /etc/resolv.conf
    fi
    # Rebind only when the address changes, preserving SSH sessions on renewal.
    previous_ip=$(cat "$state/listen-address" 2>/dev/null || true)
    listener_alive=0
    if test -s "$state/dropbear.pid" && kill -0 "$(cat "$state/dropbear.pid")" 2>/dev/null; then
        listener_alive=1
    fi
    if test "$previous_ip" != "$ip" || test "$listener_alive" != 1; then
        if test "$listener_alive" = 1; then
            kill -TERM "$(cat "$state/dropbear.pid")"
        fi
        /usr/sbin/dropbear -E -s -j -k -p "$ip:22" \
            -r /run/dropbear_ed25519_host_key -P "$state/dropbear.pid" \
            >> "$state/dropbear.log" 2>&1
        printf '%s\n' "$ip" > "$state/listen-address"
    fi
    printf 'lease_acquired=1\nlease_event=%s\n' "$1" > /run/a1625-wifi/lease-status
    ;;
esac
