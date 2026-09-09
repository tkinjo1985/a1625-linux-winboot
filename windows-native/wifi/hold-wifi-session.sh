#!/bin/sh
# Temporary RAM session; the runner owns all PCI/DART/power lifetimes.
set -eu
umask 077
state=/run/a1625-wifi
mkdir -p "$state"
mkdir "$state/session-lock"
previous_timeout=$(cat /sys/class/firmware/timeout)
cleanup() {
    if test -f "$state/network.pid"; then
        kill -TERM "$(cat "$state/network.pid")" 2>/dev/null || true
    fi
    if test -f "$state/wpa.pid"; then
        kill -TERM "$(cat "$state/wpa.pid")" 2>/dev/null || true
    fi
    echo "$previous_timeout" > /sys/class/firmware/timeout
    rm -f "$state/runner.pid"
    rmdir "$state/session-lock"
}
trap cleanup EXIT
echo 1 > /sys/class/firmware/timeout
/run/run_probe_once /run/a1625_hold.ko 'cycle=1 force_active=1 snapshot=1 prepare_port=1 inspect_prefix=1 test_refclk=1 inspect_rc=1 inspect_dart=1 pulse_radio=1 train_link=1 identify_endpoint=1 scan_pci=1 scan_iommu=1 scan_msi=1 assign_memory=1 bind_firmware=1 test_dma_range=1 hold_until_signal=1' &
runner_pid=$!
echo "$runner_pid" > "$state/runner.pid"
trap 'kill -TERM "$runner_pid" 2>/dev/null || true; wait "$runner_pid" || true; exit 143' TERM
trap 'kill -TERM "$runner_pid" 2>/dev/null || true; wait "$runner_pid" || true; exit 130' INT
wait "$runner_pid"
