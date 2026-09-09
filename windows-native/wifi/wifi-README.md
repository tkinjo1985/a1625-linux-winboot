# A1625 built-in Wi-Fi

Built-in Wi-Fi support for the Apple TV HD  
(A1625 / AppleTV5,3 / J42d / T7000).

**Status (2026-09-09): validated on the owned A1625.**

The current `wifi-t7000-leaf` RAM payload has passed:

- BCM4350 firmware initialization
- WPA2-PSK association
- AES / CCMP pairwise and group ciphers
- DHCP lease acquisition and renewal
- DNS resolution
- HTTPS bound to `wlan0` with CA verification
- Dropbear SSH addressed directly to the Wi-Fi IPv4 address
- strict host-key checking using the host key already verified over USB ACM
- Wi-Fi SSH after physically disconnecting USB data

All Wi-Fi state remains temporary RAM state. This is **not** a persistent Linux
installation and does not install a permanent Wi-Fi service.

The validated target is only:

```text
Apple TV HD
A1625
AppleTV5,3
J42d
T7000
```

Do not generalize the hardware sequence to another model or SoC without a
separate review.

See also:

- [Wi-Fi acceptance record](acceptance-2026-09-09.md)
- [temporary session lifecycle](session-workflow.md)
- [PCIe / power / DART / MSI probe history](pmu-probe/README.md)
- [top-level user guide](../../README.md)

---

# What is currently supported

Validated on the owned A1625:

| Item | Current status |
| --- | --- |
| Wi-Fi device | Broadcom BCM4350 revision 8 |
| Bus | PCIe port 1 |
| Kernel payload | `wifi-t7000-leaf` |
| Regulatory configuration | Japan (`JP`) |
| Authentication | WPA2-PSK |
| Cipher | CCMP / AES |
| DHCP | validated |
| DHCP renewal | validated |
| DNS | validated |
| HTTPS | validated with CA verification |
| Wi-Fi SSH | validated |
| SSH after physical USB removal | validated |
| USB recovery while setting up Wi-Fi | preserved |
| Runtime storage | RAM only |
| Persistent Apple TV storage changes | none |

Not currently claimed:

- WPA3
- validation for regulatory regions other than Japan
- permanent Wi-Fi installation
- automatic Wi-Fi startup after every boot
- fully automatic recovery after `wpa_supplicant` or DHCP failure
- long-duration reliability beyond the acceptance testing
- full RF calibration validation
- regulatory certification

---

# Required BootProfile

Wi-Fi requires the validated RAM payload:

```powershell
-BootProfile wifi-t7000-leaf
```

For example:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

Do not omit `-BootProfile` when intending to use built-in Wi-Fi.

The default restore profile is:

```text
baseline
```

and the baseline payload is not the validated Wi-Fi configuration.

Non-`baseline` BootProfiles require a fresh DFU / Pongo stage. Do not attempt
to replace an already-running baseline Linux session in place.

---

# Wi-Fi architecture

The current Wi-Fi path is deliberately split into two lifetimes.

```text
wifi-t7000-leaf RAM boot
        ↓
temporary PCI / DART / MSI / radio hardware session
        ↓
brcmfmac firmware initialization
        ↓
wlan0
        ↓
WPA network supervisor
        ↓
DHCP
        ↓
Wi-Fi-address Dropbear listener
```

The hardware session owns the temporary PCI host, DART, MSI, firmware, and
radio/power lifetime.

The network supervisor owns:

- `wpa_supplicant`
- DHCP
- DNS changes
- the Wi-Fi-address Dropbear listener
- radio power-save policy while networking is active

The original USB NCM / SSH path remains available during setup and recovery.

---

# Important RAM paths

The current session uses:

```text
/run/a1625-wifi/
/run/a1625-wpa/
/run/a1625-curl/
/run/a1625-iw/
```

Important state files include:

```text
/run/a1625-wifi/runner.pid
/run/a1625-wifi/network.pid
/run/a1625-wifi/wpa.pid
/run/a1625-wifi/dhcp.pid
/run/a1625-wifi/dropbear.pid
/run/a1625-wifi/listen-address
/run/a1625-wifi/lease-status
/run/a1625-wifi/wpa.conf
```

Everything disappears on power loss.

---

# Quick start

This section describes the normal current workflow.

## 1. Prepare the Wi-Fi userspace bundles

From the repository root:

```powershell
python .\windows-native\wifi\build_userland.py
```

To reproduce only from an existing package cache:

```powershell
python .\windows-native\wifi\build_userland.py --offline
```

Outputs:

```text
artifacts\wifi-userland\reproduced\wpa-runtime.tar
artifacts\wifi-userland\reproduced\curl-runtime.tar
artifacts\wifi-userland\reproduced\iw-runtime.tar
```

The committed `userland.lock.json` pins the Alpine package inputs and expected
bundle hashes.

The builder:

- verifies every cached/downloaded APK against SHA-256
- parses APK contents without executing package installation scripts
- rejects unsafe archive paths and escaping links
- creates reproducible runtime archives

No credentials or firmware are bundled.

---

## 2. Supply the tested firmware and regulatory database

The tested firmware candidate is:

```text
brcm/brcmfmac4350-pcie.bin
```

Version:

```text
7.35.180.119
```

FWID:

```text
01-e791c176
```

SHA-256:

```text
5691d1e0ceb70baf18efb7a0ec6cb84feb9edd2d0700c525b42930c4e7e4b845
```

It was obtained from linux-firmware commit:

```text
87b6caca228e10537f6206b7c17f8da90666a1cc
```

The firmware binary is intentionally not distributed by this repository.

Also provide the signed wireless regulatory database used by the validated
session.

Keep firmware, licenses, provenance records, and private board data in ignored
local artifacts.

Do not:

- commit firmware binaries
- commit device MAC addresses
- commit raw board calibration
- substitute NVRAM from another board
- invent or guess a calibration conversion

The validated session initialized without a separate external NVRAM text blob.

---

## 3. Create the protected Wi-Fi profile

Run once on Windows:

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

Both SSID and passphrase are entered as hidden input.

Default output:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi
```

The profile is protected with Windows **CurrentUser DPAPI**.

The current profile format enforces:

```text
country=JP
WPA2-PSK
RSN
pairwise=CCMP
group=CCMP
```

The WPA2 PSK is itself a credential.

Do not print it, log it, place it in command-line arguments, or commit it.

---

## 4. Boot the Wi-Fi payload

Start from fresh DFU / Pongo:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

Keep USB NCM / ACM available while bringing up the first Wi-Fi session.

The Wi-Fi payload remains RAM-only and preserves the standard USB recovery path.

---

## 5. Stage and start the hardware session

The validated low-level lifecycle is documented in:

[session-workflow.md](session-workflow.md)

The session requires the matching:

- prepared kernel
- `a1625_pcie_domains.ko`
- single-call `run_probe_once`
- Broadcom firmware
- signed regulatory database
- WPA / curl / iw runtime bundles
- `hold-wifi-session.sh`
- `network-session.sh`
- `wifi-dhcp.sh`

Do not replace the dedicated single-call module runner with BusyBox `insmod`.
The fallback behavior of BusyBox module loading breaks the validated single-call
teardown contract.

The hardware hold is started in RAM with:

```sh
nohup sh /run/a1625-wifi/hold.sh \
  > /run/a1625-wifi/hold.log 2>&1 < /dev/null &
```

Before networking, verify:

```text
/run/a1625-wifi/runner.pid
```

exists and the runner is alive, and:

```text
/sys/class/net/wlan0
```

exists.

Also inspect the kernel log and confirm the expected PCI endpoint, successful
firmware initialization, and no unexpected DART fault.

Stop immediately if those checks do not match the validated target.

---

## 6. Connect WPA / DHCP / Wi-Fi SSH

Use:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1
```

The helper is intended to:

1. try an existing healthy Wi-Fi session first
2. otherwise use USB NCM SSH as the setup/recovery control path
3. stage the required WPA / iw networking pieces when needed
4. transfer the WPA configuration through authenticated SSH stdin
5. start the network supervisor
6. wait for WPA completion and DHCP
7. verify strict-host-key SSH over the Wi-Fi IPv4 address
8. save the successful address on Windows

Saved address:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

A successful run should report values equivalent to:

```text
wpa_state=COMPLETED
pairwise_cipher=CCMP
group_cipher=CCMP
key_mgmt=WPA2-PSK
lease_acquired=1
Wi-Fi SSH verification: passed
```

---

# USB-less behavior of Connect-A1625Wifi.ps1

`Connect-A1625Wifi.ps1` first tries the saved or explicitly supplied Wi-Fi
address.

Normal USB-less path:

```text
last-address.txt
        ↓
strict Wi-Fi SSH succeeds
        ↓
runner / supervisor / DHCP / WPA state verified
        ↓
complete without USB
```

You may explicitly override the address:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1 `
  -WifiAddress 192.168.1.123
```

If the Wi-Fi address is unreachable, the script falls back to:

```text
172.16.42.1
```

over USB NCM.

Important limitation:

**A cold state with no active Wi-Fi hardware session cannot currently bootstrap
the radio using no management path at all.**

The first Wi-Fi session after a fresh RAM boot still needs an existing control
path, normally USB NCM / ACM, for the hardware session and initial networking
setup.

The helper intentionally does not blindly re-run the PCI / DART / firmware
hardware initialization sequence.

---

# Open an interactive shell over Wi-Fi

After `Connect-A1625Wifi.ps1` has stored the successful address:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1
```

normally requires no IP argument.

The helper reads:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

and opens:

```text
root@<Wi-Fi IPv4>
```

using the normal RAM private key.

Manual address override:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1 `
  -Address 192.168.1.123
```

The interactive shell starts in:

```text
/run/work
```

and uses:

```text
/run/codex-home
```

as the Codex home.

---

# SSH host-key verification

The Wi-Fi Dropbear listener uses the same host key as the USB-side RAM SSH
server:

```text
/run/dropbear_ed25519_host_key
```

That key was already verified through USB ACM for the current RAM boot.

Wi-Fi SSH therefore uses:

```text
HostKeyAlias=172.16.42.1
```

with the current boot's strict known-hosts file.

Do not use:

```text
StrictHostKeyChecking=no
```

The normal per-boot host-key files are stored on Windows under:

```text
%LOCALAPPDATA%\AppleTvA1625\state\known_hosts_ram_*
```

---

# DHCP and the Wi-Fi Dropbear listener

`wifi-dhcp.sh` configures the leased address on `wlan0`.

On DHCP `bound` or `renew` it:

- applies the IPv4 address and subnet
- installs the WLAN default route
- updates DNS from the DHCP lease
- binds a separate key-only Dropbear listener to `<Wi-Fi IPv4>:22`

If the address is renewed unchanged, the existing listener is preserved so
active SSH sessions are not unnecessarily replaced.

If the address changes, Dropbear is rebound to the new address.

The active address is recorded in RAM at:

```text
/run/a1625-wifi/listen-address
```

---

# Network supervisor behavior

`network-session.sh` supervises:

- `wpa_supplicant`
- `udhcpc`
- the Wi-Fi Dropbear listener

It waits for:

```text
wpa_state=COMPLETED
```

before starting DHCP.

`udhcpc` remains in the foreground under supervision so lease renewal continues.

The supervisor disables Wi-Fi power saving while this mains-powered SSH target
is active because intermittent inbound SSH stalls were observed with power save
enabled.

The prior power-save setting is restored during cleanup.

If a supervised WPA or DHCP process fails, the networking session exits rather
than claiming successful automatic recovery.

---

# Verify Wi-Fi while USB is still connected

Use the DHCP address and the current boot's known-hosts file:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address '<Wi-Fi IPv4 address>' `
  -KnownHostsPath '<current-boot-known-hosts-path>'
```

This validates Wi-Fi while preserving USB as a recovery path.

---

# Verify Wi-Fi after physically disconnecting USB

After Wi-Fi is confirmed healthy, physically disconnect USB **data** while
keeping the Apple TV powered.

Then run:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address '<Wi-Fi IPv4 address>' `
  -KnownHostsPath '<current-boot-known-hosts-path>' `
  -RequireUsbDisconnected
```

The acceptance test checks:

- hardware runner is alive
- network supervisor is alive
- DHCP client is alive
- `wlan0` exists
- `wpa_state=COMPLETED`
- pairwise cipher is CCMP
- group cipher is CCMP
- key management is WPA2-PSK
- radio power save is off
- DNS succeeds
- HTTPS succeeds when explicitly bound to `wlan0`
- TLS certificate verification succeeds
- strict-host-key Wi-Fi SSH succeeds
- Windows sees no matching Apple/Linux USB, NCM, or ACM device before and after

This exact USB-independent path passed the final acceptance testing.

---

# Stop networking

To stop only WPA / DHCP / Wi-Fi SSH networking:

```sh
kill -TERM "$(cat /run/a1625-wifi/network.pid)"
```

Verify cleanup:

- network PID disappears
- DHCP PID disappears
- WPA PID disappears
- Wi-Fi Dropbear PID disappears
- network lock disappears
- WLAN routes are removed
- the prior resolver is restored
- the original USB route remains available

---

# Stop the Wi-Fi hardware session

After networking has stopped, terminate the hardware runner:

```sh
kill -TERM "$(cat /run/a1625-wifi/runner.pid)"
```

The validated teardown order releases:

1. Wi-Fi / PCI clients
2. PCI host state
3. DART
4. MSI
5. radio / power resources

After shutdown, inspect the cleanup result and verify there are no unexpected:

- probe modules
- PCI devices
- IOMMU groups
- live session PID / lock files

Do not force-remove parent devices or overwrite a live session lock.

---

# Power loss

All Wi-Fi runtime state disappears on power loss.

That includes:

- hardware session
- `wlan0`
- WPA configuration in `/run`
- `wpa_supplicant`
- DHCP lease
- Wi-Fi Dropbear listener
- runtime routes and DNS
- RAM host key

Windows-side protected state can remain, including:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

The saved IPv4 address is only a hint for a still-running session. After a new
RAM boot it must not be assumed valid until a new Wi-Fi session has been
established.

---

# Security model

## Wi-Fi credential

The Windows profile contains:

- SSID
- derived WPA2 PSK

It is stored using CurrentUser DPAPI.

The WPA configuration is transferred through authenticated SSH **stdin**, not
as a shell argument.

Runtime destination:

```text
/run/a1625-wifi/wpa.conf
```

Mode:

```text
0600
```

No plaintext Wi-Fi credential should appear in:

- Git
- command-line history
- logs
- public test records
- firmware artifacts

---

## Firmware and device-specific data

The repository does not distribute:

- Apple firmware
- Broadcom firmware binary
- board calibration
- device MAC address
- Apple-derived NVRAM
- raw ADT containing private device data

Keep those inputs local and ignored.

---

## Internal storage boundary

The validated Wi-Fi workflow remains RAM-only.

It does not require:

- mounting Apple TV internal storage
- APFS modification
- NVRAM writes
- tvOS restore
- tvOS update
- fakefs creation

---

# Regulatory configuration

The validated deployment is:

```text
JP
```

with WPA2-PSK / CCMP.

The signed regulatory database was staged into the RAM environment and effective
channel restrictions were checked with the staged `iw` runtime.

This establishes the tested Linux configuration and observed restrictions. It
does **not** constitute full RF calibration validation or regulatory
certification.

Other regulatory regions have not been accepted by this project.

---

# Hardware identification

The owned AppleTV5,3 / J42d Apple Device Tree and subsequent PCI probing
identified the built-in radio path as:

```text
Broadcom BCM4350
PCI vendor/device: 14e4:43a3
PCI revision: 08
subsystem: 106b:10fe
chipcommon ID: 0x17084350
```

The radio is attached to T7000 PCIe port 1.

Root port identification:

```text
vendor/device: 106b:1002
class: 060400
```

The validated Linux path includes temporary integration for:

- T7000 PCIe
- DART / IOMMU
- MSI
- radio power / reset
- Broadcom PCIe enumeration
- brcmfmac firmware initialization

Detailed staged hardware evidence is retained in:

[pmu-probe/README.md](pmu-probe/README.md)

---

# Firmware / NVRAM conclusions

The validated device selects the `brcmfmac4350-pcie` firmware family.

The tested firmware initialized successfully without a separate external NVRAM
text file.

The live ADT contains board calibration properties, but this project has not
established a safe or correct conversion of those raw values into a generic
brcmfmac NVRAM file.

Therefore:

- do not guess a board NVRAM conversion
- do not borrow another board's NVRAM
- do not treat a matching BCM4350 chip number as proof of board compatibility
- do not commit raw individual-device calibration data

The firmware-reported MAC address is preserved; the validated workflow does not
spoof the MAC address.

---

# Read-only ADT collection

For hardware research, collect the RAM copy of the Apple Device Tree with:

```powershell
& .\windows-native\wifi\Get-A1625WifiAdt.ps1 `
  -KnownHostsPath '<current-boot-known-hosts-path>'
```

Then inspect the allowlisted fields:

```powershell
python .\windows-native\wifi\inspect_adt.py `
  .\artifacts\wifi-research\a1625.adt.bin
```

The collector verifies the expected J42d / T7000 Linux target and reads the
m1n1 RAM-backed ADT MTD.

It does not write the Apple TV.

The raw ADT contains individual-device data and must remain under ignored local
artifacts.

The parser intentionally omits sensitive fields such as:

- MAC addresses
- calibration blobs
- NVRAM-like data
- serial numbers
- random seeds

---

# Research history

The Wi-Fi implementation was developed in bounded stages.

Earlier stages included:

1. read-only PMU inspection
2. temporary radio power pulse
3. PCIe power-domain validation
4. T7000 PHY / port register investigation
5. root-port identification
6. reference-clock control
7. radio power + link training
8. endpoint identification
9. PCI enumeration
10. DART / MSI integration
11. brcmfmac binding
12. firmware initialization
13. WPA2 / DHCP / DNS / HTTPS
14. Wi-Fi SSH
15. USB-disconnected acceptance
16. supervised session lifecycle and cleanup

Some historical sections and logs describe failed or incomplete intermediate
experiments. They should not be interpreted as the current implementation
status.

The authoritative current-state references are:

- [acceptance-2026-09-09.md](acceptance-2026-09-09.md)
- [session-workflow.md](session-workflow.md)

The detailed hardware-development record remains in:

- [pmu-probe/README.md](pmu-probe/README.md)

---

# Validated acceptance facts

The final accepted RAM payload had:

```text
Build ID:
3848d1b6e0bfa0c4c7abca7a9c9e8cfb33e754a2
```

Payload SHA-256:

```text
bc775028aba05573ab2155ca399c5ec6c7e6f1dc42e5f3a97f3e37ffef7d6af1
```

The accepted session demonstrated:

```text
wpa_state=COMPLETED
pairwise_cipher=CCMP
group_cipher=CCMP
key_mgmt=WPA2-PSK
Power save: off
DNS success
HTTPS HTTP 200
TLS verify result 0
strict-host-key WLAN SSH success
```

The final `Test-A1625Wifi.ps1 -RequireUsbDisconnected` run passed with Windows
reporting no matching Apple/Linux USB device before and after the test.

See the complete evidence and limitations in:

[acceptance-2026-09-09.md](acceptance-2026-09-09.md)

---

# Troubleshooting

## `wlan0` does not exist

Do not start the network supervisor.

Confirm the hardware session was staged and started correctly.

Check:

```sh
cat /run/a1625-wifi/runner.pid
kill -0 "$(cat /run/a1625-wifi/runner.pid)"
```

Inspect the kernel log for:

- expected PCI endpoint
- successful firmware initialization
- unexpected DART faults
- cleanup from an earlier failed session

---

## `Connect-A1625Wifi.ps1` says Wi-Fi and USB are both unavailable

The script can operate without USB only if an already-running Wi-Fi session is
reachable.

If both paths are unavailable, re-establish the normal recovery/control path
and start a fresh Wi-Fi session.

---

## Saved Wi-Fi IP is stale

Check:

```powershell
Get-Content "$env:LOCALAPPDATA\AppleTvA1625\wifi\last-address.txt"
```

The address may change after a DHCP change or a new session.

Run `Connect-A1625Wifi.ps1` again through an available control path so it can
discover and save the current address.

---

## WPA does not reach `COMPLETED`

Inspect:

```text
/run/a1625-wifi/wpa.log
/run/a1625-wifi/network.log
```

Do not expose or publish the WPA configuration.

Verify that:

- the DPAPI profile is the expected one
- the target is WPA2-PSK / CCMP
- the Japan regulatory configuration is active
- the staged WPA runtime matches the pinned build
- the hardware runner is still alive

---

## DHCP fails

Inspect:

```text
/run/a1625-wifi/dhcp.log
/run/a1625-wifi/lease-status
```

The network supervisor treats DHCP failure as a session failure rather than
silently claiming connectivity.

---

## Wi-Fi SSH intermittently stalls

The validated supervisor disables radio power saving while networking is active
because intermittent inbound SSH stalls were observed with power saving enabled.

Confirm:

```sh
LD_LIBRARY_PATH=/run/a1625-iw/usr/lib \
  /run/a1625-iw/usr/sbin/iw dev wlan0 get power_save
```

Expected while the network supervisor is running:

```text
Power save: off
```

This is a tested mitigation, not proof that every possible timeout has the same
cause.

---

## Host-key mismatch

Do not disable host-key checking.

Use the current RAM boot's verified known-hosts file and:

```text
HostKeyAlias=172.16.42.1
```

A host-key mismatch can indicate that the Windows known-hosts selection and the
running RAM boot do not correspond.

---

# Relevant files

| File | Purpose |
| --- | --- |
| `Set-A1625WifiProfile.ps1` | Create the DPAPI-protected WPA2 profile |
| `A1625WifiProfile.psm1` | Profile validation, PSK derivation, WPA config serialization |
| `build_userland.py` | Build pinned WPA / curl / iw runtime archives |
| `userland.lock.json` | Pin userspace package and bundle hashes |
| `Get-A1625WifiAdt.ps1` | Read-only collection of the RAM ADT |
| `inspect_adt.py` | Safe allowlisted ADT parser |
| `hold-wifi-session.sh` | Own the temporary hardware lifetime |
| `network-session.sh` | Supervise WPA, DHCP, Wi-Fi SSH, power-save policy |
| `wifi-dhcp.sh` | Configure lease, routes, DNS, and Wi-Fi Dropbear binding |
| `Connect-A1625Wifi.ps1` | User-facing Wi-Fi connect / verify helper |
| `Enter-A1625WifiShell.ps1` | Open the interactive shell using the saved Wi-Fi address |
| `Test-A1625Wifi.ps1` | Wi-Fi acceptance test |
| `session-workflow.md` | Exact staging / startup / teardown procedure |
| `acceptance-2026-09-09.md` | Final device acceptance evidence |
| `pmu-probe/README.md` | Detailed hardware research and bounded probe history |

---

# Safety boundary

Use only on an owned or explicitly authorized A1625.

Do not bypass:

- target identity checks
- kernel / payload hash checks
- current-boot host-key verification
- module single-call execution requirements
- session locks
- teardown checks

Do not turn a Wi-Fi failure into an internal-storage recovery procedure.

The current workflow requires no Apple TV erase, restore, update, APFS write, or
NVRAM modification.
