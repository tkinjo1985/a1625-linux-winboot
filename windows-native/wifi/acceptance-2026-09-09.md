# Issue #2 acceptance record — 2026-09-09

Target: owned AppleTV5,3 / J42d / A1625 / T7000 only. All device changes are
temporary RAM state; internal storage, NVRAM and tvOS remain unchanged.

## Verified

- Live kernel build ID: `3848d1b6e0bfa0c4c7abca7a9c9e8cfb33e754a2`.
- RAM payload SHA256: `bc775028aba05573ab2155ca399c5ec6c7e6f1dc42e5f3a97f3e37ffef7d6af1`.
- ARM64 4 KiB pages; kernel patches 0001 through 0007, with the diagnostic
  host's `test_dma_range=1` aperture.
- BCM4350 revision 8 firmware initializes; `wlan0` has the expected PCI parent.
  Two bounded initialization trials delivered MSI callbacks and no DART fault
  during the 20-second observation interval.
- The three-second hold deadline and SIGTERM path both release the driver,
  PCI host, DART, MSI and radio/power resources. SIGTERM runner exit 143 is
  expected. Use the single-call runner, never BusyBox insmod's retry path.
- Japan country configuration, WPA2-PSK and pairwise/group CCMP; supplicant
  reports `wpa_state=COMPLETED`.
- DHCP installs a WLAN address and default route; the USB connected route
  remains available as a recovery path.
- DNS lookup succeeds. curl bound to `wlan0`, using the RAM system CA bundle,
  returns HTTP 200 and `ssl_verify_result=0` for `https://example.com`.
- Windows SSH addressed directly to the WLAN IP succeeds with strict host-key
  checking, reusing the same key previously verified through USB ACM.
- After the user physically removed USB data, Windows reported zero matching
  Apple/Linux USB, NCM or COM5 devices. At uptime 1587.94, a new WLAN SSH
  connection passed, DNS returned success, HTTPS returned 200 with TLS verify
  result 0, and WPA2/CCMP remained COMPLETED. Two intervening SSH attempts
  timed out; subsequent SSH and four ping probes passed without restarting.
  The gadget's UDC `configured` and usb0 carrier `1` remained stale after
  physical removal; these fields cannot alone establish cable presence here.
- `build_userland.py --offline` reproduces both deployed WPA and curl bundle
  hashes from the pinned package cache. Every APK is checked against SHA256
  before parsing; installation scripts are never run.
- SSID and PSK remain in a Windows DPAPI profile and a mode-600 RAM file.
  They are not included here. Firmware binaries and individual device data
  remain in ignored local artifacts.

## Final acceptance

The final supervised configuration passed `Test-A1625Wifi.ps1` with
`-RequireUsbDisconnected` after the user removed the cable again. Windows
had no matching USB devices before or after the test. The runner, network
supervisor and DHCP client were alive; WPA2/CCMP was COMPLETED, power saving
was off, DNS succeeded, HTTPS returned HTTP 200 with TLS verification result
0, and the new WLAN SSH session passed strict host-key checking.

The final payload passed restore `-ConfirmRamBoot -BootProfile wifi-t7000-leaf
-ValidateOnly`; no device state changed during this check. All eight Python
parser/archive tests passed. Documentation now distinguishes the earlier
failed experiments from the verified configuration.

## Session integration results

The initial bounded hold was stopped cleanly at uptime 2041; PCI devices,
probe modules and IOMMU groups were absent, with firmware timeout restored
to 60 seconds. Its automatic one-hour expiry no longer governs the session.

Module SHA256 `d8e545e0af7cd7ade10e2ac9157a1e0c8983b4563b28b9709bd3dc2a89dc2109`
adds explicit `hold_until_signal`, mutually exclusive with bounded holds.
It built against the live kernel's prepared exports; all undefined symbols
resolved against `vmlinux.symvers`. Signal-driven teardown passed with
network cleanup, no remaining PCI/module state, and restored DNS/timeout.
The current hold began at uptime 2213.117, continuing until signal or fault.

The network supervisor passed startup, explicit DHCP renewal (`lease_event=renew`),
unchanged SSH listener PID on same-address renewal, and WLAN SSH/DNS/HTTPS.
Network-only termination removed all three child processes, its lock/PID files,
and WLAN routes; the original resolver and USB connected route were restored.

Intermittent initial SSH timeouts also occurred with USB attached and radio
power saving enabled. Disabling power saving was followed by successful new
SSH connections immediately and after more than 100 seconds. The supervisor
now disables it for this mains-powered target and restores the prior setting
at exit; both transitions and DNS restoration passed a subsequent live test.
This is a tested mitigation, not proof that every timeout had that cause.

The builder reproduces WPA/curl byte-for-byte. Its iw archive contains files
identical to the staged iw runtime, plus the pinned libnl package's remaining
libraries. The iw APK also matched the pinned index control hash.
Archive path/link boundary and tampered-cache tests pass (three tests).
Profile tests pass PSK vectors, validation, DPAPI round trip and tamper rejection.
The final source-candidate audit covered 112 files: no current SSID, SSID hex or PSK
hex, and no firmware/archive/module/profile/key file extensions were found.

See [session-workflow.md](session-workflow.md) for staging and lifecycle steps.
WPA3, automatic reconnection after a failed supervised process, and long-duration
reliability beyond the observed tests remain unclaimed.

## Issue #2 requirement audit

| Requirement | Evidence |
| --- | --- |
| Identify chip, bus, power, clocks, GPIO and interrupts | Owned ADT, endpoint/chip reads, and staged power/PCI/MSI tests in README and pmu-probe notes |
| Determine driver, device-tree and firmware/NVRAM requirements | brcmfmac BCM4350/8, temporary T7000 host/DART nodes, patches 0001–0007, pinned firmware and successful initialization without external NVRAM |
| Document acquisition and redistribution | Pinned linux-firmware source, hash and locally inspected Broadcom license summarized in README; no Apple binaries in source candidates |
| Regulatory domain, MAC and authentication | JP database/PHY observations, firmware-reported MAC preserved, WPA2-PSK/CCMP enforced by protected profile |
| Minimal WPA userland | Pinned Alpine supplicant/iw libraries with BusyBox DHCP; WPA3 requirements discussed, no WPA3 claim |
| Preserve USB recovery | USB NCM SSH and COM5 returned after physical reconnection; network and hardware stop tests retained USB SSH |
| Protect connection secrets | DPAPI profile, SSH stdin transfer, RAM mode 600, profile tamper tests and final source audit |
| Stable initialization and AP association | Repeated clean firmware initialization and teardown, maintained hold, completed WPA2 association |
| DHCP, DNS and HTTPS | Lease acquisition and renewal; DNS success; WLAN-bound HTTP 200 with TLS verification 0 |
| SSH after USB removal | Final acceptance command passed twice with Windows USB absent before and after each run |
| Keep firmware and credentials out of Git | Ignored artifacts/profile paths and audit of every tracked/unignored source candidate |
| RAM-only boundary | Temporary driver/userspace lifecycle, no internal-storage/NVRAM operation added or performed |
