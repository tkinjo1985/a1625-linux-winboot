# Temporary Wi-Fi session

Use only the owned A1625/J42d/T7000 and the verified `wifi-t7000-leaf` RAM
kernel. Keep USB NCM/ACM available during setup. No commands here install a
persistent system or modify internal storage.

## Prerequisites

1. Build the prepared kernel with patches 0001–0007 and the Wi-Fi config,
   preserving 4 KiB pages. Validate the RAM payload and live build ID as
   described in the acceptance record and restore script.
2. Run `windows-native/wifi/pmu-probe/build.sh` in the native MSYS2 environment
   against that exact prepared kernel. It produces the module and single-call
   runner under ignored `artifacts/wifi-pmu-probe/`.
3. Run `python windows-native/wifi/build_userland.py`. Its lock pins the tested
   WPA, curl and iw APKs and resulting archives. The RAM root needs musl, Dropbear,
   its current host key, BusyBox udhcpc and the CA bundle.
4. Supply the pinned Broadcom firmware and signed regulatory database described
   in README.md to RAM `/lib/firmware`. Do not substitute board NVRAM. Configure
   Japan and check effective channel restrictions with the staged iw runtime.
5. Create the Windows DPAPI profile with `Set-A1625WifiProfile.ps1`. Transfer
   `ConvertTo-A1625WpaConfig` bytes through verified SSH stdin to mode-600
   `/run/a1625-wifi/wpa.conf`, never through command arguments or logs.

Stage files through strict, current-boot host-key checked SSH and compare
SHA256 after transfer. Tar extraction destinations must be fresh RAM directories:

| Local artifact | RAM destination |
| --- | --- |
| `a1625_pcie_domains.ko` | `/run/a1625_hold.ko` |
| `run_probe_once` | `/run/run_probe_once` (executable) |
| WPA runtime archive contents | `/run/a1625-wpa/` |
| curl runtime archive contents | `/run/a1625-curl/` |
| iw runtime archive contents | `/run/a1625-iw/` |
| `hold-wifi-session.sh` | `/run/a1625-wifi/hold.sh` |
| `network-session.sh` | `/run/a1625-wifi/network-session.sh` |
| `wifi-dhcp.sh` | `/run/a1625-wifi/dhcp.sh` (executable) |

Normalize shell scripts to LF when transferring from Windows, and run `sh -n`
on each staged script. Keep `/run/a1625-wifi` and its logs private (umask 077).

## Start and stop

Start the hardware hold first:

```sh
nohup sh /run/a1625-wifi/hold.sh > /run/a1625-wifi/hold.log 2>&1 < /dev/null &
```

Inspect the actual kernel output before continuing. It must show the expected
PCI endpoint, successful firmware initialization, no DART fault in its bounded
observation, and entry into the Wi-Fi hold. Check that the recorded runner is
alive and `wlan0` belongs to the expected PCI device. Stop on unexpected results.
Never substitute BusyBox insmod: its fallback retry breaks the single-call
teardown contract. The regular hold continues until a signal or detected fault;
bounded `hold_seconds` remains available for diagnostics and is mutually
exclusive with `hold_until_signal`.

Then start the network supervisor:

```sh
nohup sh /run/a1625-wifi/network-session.sh > /run/a1625-wifi/network.log 2>&1 < /dev/null &
```

It disables radio power saving for this mains-powered SSH target, waits for
WPA completion, runs udhcpc continuously for lease renewal, and
binds a separate key-only Dropbear listener to the leased address. Renewing
the same address preserves that listener. Changing addresses rebinds it.
The original USB SSH listener remains available. Use the existing verified
host key for WLAN SSH (`HostKeyAlias`), not disabled host-key checking.

Stop networking alone with:

```sh
kill -TERM "$(cat /run/a1625-wifi/network.pid)"
```

Verify that its lock and PID files disappear, child processes exit, and DNS
and original default routes are restored. Stop all Wi-Fi hardware afterwards:

```sh
kill -TERM "$(cat /run/a1625-wifi/runner.pid)"
```

The runner signal ends the hold, releases PCI clients before DART/MSI/power,
and triggers network cleanup. Inspect the kernel cleanup result and absence
of probe modules, PCI devices and IOMMU groups. Do not force-remove parents
or overwrite PID files to bypass a live session lock.

All settings disappear on power loss. WPA3 and automatic recovery after
supplicant/DHCP failure are not claimed by this workflow: a failed supervised
process ends networking, allowing the USB recovery path to diagnose it.

## Acceptance from Windows

Use the address returned by DHCP and the known-hosts file verified for this
boot. After physically removing USB data with power retained, run:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 -Address '<Wi-Fi IPv4 address>' `
  -KnownHostsPath '<current-boot-known-hosts-path>' -RequireUsbDisconnected
```

The test verifies the supervised processes, WPA2/CCMP, disabled power saving,
DNS, certificate-validated HTTPS bound to wlan0, and strict-key WLAN SSH.
It checks Windows USB presence both before and after. Another Apple/Linux
USB gadget conservatively prevents a passing disconnected result. Without
the switch, it tests Wi-Fi while allowing the USB recovery connection.
