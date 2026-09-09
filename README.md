# a1625-linux-winboot

A Windows-hosted, **RAM-only Linux boot workflow** for Apple TV HD  
(A1625 / AppleTV5,3 / J42d / Apple A8 / T7000).

The project uses a temporary boot chain:

```text
DFU
  ↓
checkm8
  ↓
PongoOS
  ↓
m1n1
  ↓
Linux kernel + initramfs
  ↓
RAM-only userspace
```

Linux rootfs, development tools, Codex, Wi-Fi session state, and the working
directory remain in RAM. The normal workflow does **not** mount or write the
Apple TV internal storage, APFS volumes, NVRAM, or tvOS.

> **Target hardware: Apple TV HD A1625 only**
>
> Use this project only on hardware you own or are explicitly authorized to
> test. It is not intended to be generalized to other Apple TV models or SoCs.

[日本語 README](README.ja.md)

---

## Current validation status

As of 2026-09-09, the following have been validated on the owned A1625:

- Windows-native checkm8 / PongoOS boot path
- PongoOS → m1n1 → Linux + initramfs RAM boot
- AArch64 kernel with 4 KiB pages
- RAM root filesystem
- USB NCM networking
- USB ACM recovery shell
- public-key-only Dropbear SSH
- Codex CLI running entirely from RAM
- RAM development layer with Git, OpenSSH client, GCC, G++, make, pkg-config, etc.
- RAM-only zram swap
- Windows DPAPI-backed save/restore of `/run/work` and selected Codex/Git/SSH state
- built-in BCM4350 Wi-Fi
- WPA2-PSK / AES (CCMP)
- DHCP and DNS
- certificate-verified HTTPS
- SSH addressed directly to the Wi-Fi IPv4 address
- Wi-Fi SSH after physically disconnecting USB data

Wi-Fi is still a **RAM-only research session**, not a persistent installation or
automatic boot-time network service.

Validation records:

- [RAM / development validation](windows-native/VALIDATION-ISSUES-3-4.md)
- [Wi-Fi acceptance record](windows-native/wifi/acceptance-2026-09-09.md)
- [Wi-Fi session workflow](windows-native/wifi/session-workflow.md)

---

# Two different profile types

The project has two similarly named but independent profile concepts.

## BootProfile

`-BootProfile` selects **which Linux kernel / RAM payload is booted**.

Examples:

```powershell
-BootProfile baseline
```

```powershell
-BootProfile wifi-t7000-leaf
```

## DevelopmentProfile

`-DevelopmentProfile` selects **which userland development tools are added on
top of the running RAM Linux environment**.

Example:

```powershell
-DevelopmentProfile development
```

Conceptually:

```text
BootProfile
    ↓
selects kernel / RAM payload

DevelopmentProfile
    ↓
selects Git / SSH / compiler tool layer
```

---

# Requirements

## Hardware

- Apple TV HD A1625
- Windows PC with USB connectivity
- ability to place the Apple TV into DFU mode manually
- for Wi-Fi: a compatible WPA2-PSK / AES (CCMP) access point

## Windows host

The primary commands in this README assume **PowerShell 7 (`pwsh`)**.

Required host tools include:

- PowerShell 7
- OpenSSH client
  - `ssh.exe`
  - `ssh-keygen.exe`
  - `ssh-keyscan.exe`
- Python
  - `python.exe`
- Git
- the locally prepared build artifacts required by the selected workflow

Rebuilding components may additionally require MSYS2, Rust, a C/C++ toolchain,
or other project-specific build dependencies.

---

# Clean-clone expectations

This repository does not distribute every executable, firmware image, or
device-specific artifact required for a working boot.

Some expected local assets live under ignored paths such as `artifacts` and
`third_party`.

Examples include:

- PongoOS binary
- built Linux kernel / payload
- `openra1n.exe`
- libusb-related artifacts
- SSH private key
- Codex binary
- Broadcom Wi-Fi firmware
- device-specific data
- Apple-derived data
- authentication state
- Wi-Fi SSID / PSK

A clean clone therefore may require local source retrieval, review, and build
steps before the restore command can boot the device.

Fetch only the pinned public upstream sources used by this project with:

```powershell
& .\windows-native\Get-PinnedSources.ps1
```

---

# First-time setup

## 1. Save the expected device ECID

Configure the owned A1625 once:

```powershell
& .\windows-native\Set-A1625DeviceConfig.ps1 `
  -ExpectedEcid '<16-hex-digit-ECID>'
```

Obtain the ECID from the diagnostic or DFU output.

The ECID is used as an additional device identity gate to reduce the chance of
operating on the wrong device.

---

## 2. Enter DFU mode

Place the Apple TV into DFU mode and connect it to Windows.

The restore workflow validates the expected A1625 / T7000 identity and the
configured ECID before proceeding through the DFU / Pongo stages.

---

## 3. Use Zadig only when the restore script asks for it

If the exact DFU or PongoOS USB instance needs libusbK, the restore script
pauses and displays the device instance that must be changed.

Relevant USB IDs:

- DFU: `05AC:1227`
- PongoOS: `05AC:4141`

Do **not** change the driver for normal tvOS, Linux USB NCM, Linux USB ACM, or
unrelated Apple USB devices.

Before changing a driver, record its current provider, version, service, and INF
locally.

Rollback instructions:

[windows-native/DRIVER-ROLLBACK.md](windows-native/DRIVER-ROLLBACK.md)

---

# BootProfile

`Restore-A1625RamEnvironment.ps1` currently accepts these boot profiles:

| BootProfile | Purpose | Normal use |
| --- | --- | --- |
| `baseline` | Standard RAM-only Linux payload for USB NCM, SSH, Codex, and development tools | **Default / recommended** |
| `wifi-experimental` | Early Wi-Fi research payload | Do not use for normal operation |
| `wifi-fw-lifetime` | Wi-Fi firmware-lifecycle validation payload | Do not use for normal operation |
| `wifi-fw-response` | Wi-Fi firmware-response validation payload | Do not use for normal operation |
| `wifi-t7000-table` | Intermediate T7000 Wi-Fi integration payload | Do not use for normal operation |
| `wifi-t7000-leaf` | Payload used for the currently validated built-in Wi-Fi session | **Use for Wi-Fi** |

Default:

```text
BootProfile = baseline
```

Therefore:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot
```

boots `baseline`.

For Wi-Fi, explicitly use:

```powershell
-BootProfile wifi-t7000-leaf
```

> Non-`baseline` BootProfiles are treated as experimental boots. Do not attempt
> to replace an already-running Linux session in place. Start again from a fresh
> DFU / Pongo stage.

---

# DevelopmentProfile

`-DevelopmentProfile` selects the optional RAM tool layer.

| DevelopmentProfile | Contents |
| --- | --- |
| `none` | No additional development layer |
| `minimal` | Git, OpenSSH client, CA bundle, and supporting runtime files |
| `development` | `minimal` plus GCC, G++, linker tools, make, file, patch, pkg-config, etc. |

Default:

```text
DevelopmentProfile = none
```

For general development work:

```powershell
-DevelopmentProfile development
```

is the usual choice.

More detail:

[windows-native/development-tools/README.md](windows-native/development-tools/README.md)

---

# Restore-A1625RamEnvironment.ps1 parameters

The primary boot / restore entry point is:

```powershell
.\windows-native\Restore-A1625RamEnvironment.ps1
```

| Parameter | Meaning |
| --- | --- |
| `-ConfirmRamBoot` | Explicitly confirms the temporary RAM-only boot. Required for a real boot |
| `-BootProfile <name>` | Selects the Linux kernel / payload. Default: `baseline` |
| `-ExpectedEcid <16hex>` | Explicit ECID override. Otherwise the saved device config is used |
| `-StageTimeoutSeconds <30-300>` | Timeout for boot stages. Default: 120 seconds |
| `-DevelopmentProfile none|minimal|development` | Selects the optional RAM development layer |
| `-EnableZram` | Enables RAM-only zram swap |
| `-RestoreRamState` | Restores a previously saved Windows-hosted RAM-state snapshot |
| `-RamStateDirectory <path>` | Snapshot directory. Default: `%LOCALAPPDATA%\AppleTvA1625\ram-state` |
| `-StartCodex` | Starts Codex after restore completes |
| `-EnterShell` | Opens an interactive SSH shell after restore completes |
| `-ValidateOnly` | Performs local artifact and snapshot compatibility validation without USB transfer or network changes |

`-StartCodex` and `-EnterShell` cannot be used together.

These options:

```text
-EnableZram
-RestoreRamState
```

require:

```text
DevelopmentProfile = minimal
```

or:

```text
DevelopmentProfile = development
```

---

# Common boot commands

## Minimal baseline boot

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot
```

---

## Baseline + interactive shell

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -EnterShell
```

---

## Development environment + zram + shell

Use this when no RAM snapshot exists yet:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

---

## Restore a saved development environment

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

## Wi-Fi kernel + development environment

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

Only add `-RestoreRamState` when the snapshot was created against the same Wi-Fi
payload and compatible development layer:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

# What the restore script does

At a high level:

```text
verify local artifact SHA-256 values
        ↓
validate A1625 / ECID identity
        ↓
DFU
        ↓
checkm8
        ↓
YOLO DFU
        ↓
PongoOS
        ↓
upload m1n1 + Linux + initramfs to RAM
        ↓
Linux USB composite device
        ├─ USB NCM
        └─ USB ACM
        ↓
configure Windows USB NCM / NAT
        ↓
obtain Dropbear host key over USB ACM
        ↓
create strict per-boot known_hosts file
        ↓
SSH health verification
        ↓
restore Codex runtime
        ↓
install DevelopmentProfile
        ↓
enable zram if requested
        ↓
restore RAM snapshot if requested
        ↓
start Codex or interactive shell
```

The Linux health check verifies at least:

- `aarch64`
- 4 KiB page size
- `/` backed by RAM rootfs
- no internal block device exposed beyond permitted zram state

---

# USB SSH

The standard Linux USB NCM address is:

```text
172.16.42.1
```

SSH user:

```text
root
```

Port:

```text
22
```

Authentication is public-key-only.

Default Windows-side private key:

```text
artifacts\ssh\a1625_ram_ed25519
```

The Dropbear host key is regenerated on each RAM boot, so do not disable host-key
checking.

The restore script obtains the Dropbear public key over USB ACM, verifies it,
and stores a per-boot known-hosts file under:

```text
%LOCALAPPDATA%\AppleTvA1625\state\known_hosts_ram_*
```

---

# Interactive shell

Open a shell after the environment is already restored:

```powershell
& .\windows-native\Enter-A1625Shell.ps1
```

Or restore and enter the shell in one command:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -EnterShell
```

The shell normally connects to:

```text
root@172.16.42.1
```

Working directory:

```text
/run/work
```

Codex home:

```text
/run/codex-home
```

Start Codex from the shell with:

```sh
codex-ram
```

---

# zram

`-EnableZram` configures RAM-only compressed swap.

The validated configuration uses:

- `/dev/zram0`
- 768 MiB logical swap
- priority 100
- zstd compression
- 256 MiB compressed allocation limit
- no backing device

No internal-storage writeback is configured.

Example:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram
```

The A1625 has roughly 2 GiB of RAM. Large repositories, C/C++ builds, Codex, or
multiple memory-heavy tasks can still exhaust memory even with zram enabled.

---

# RAM-state snapshots

Powering off the Apple TV destroys the RAM environment.

To preserve selected work, save a Windows-hosted encrypted snapshot before
powering off.

Default location:

```text
%LOCALAPPDATA%\AppleTvA1625\ram-state
```

The saved state is encrypted with Windows CurrentUser DPAPI.

---

## Saved paths

The snapshot includes selected mutable state such as:

```text
/run/work
/run/codex-home/auth.json
/run/codex-home/config.toml
/run/codex-home/.gitconfig
/run/codex-home/.ssh/config
/run/codex-home/.ssh/known_hosts
/run/codex-home/.ssh/id_ed25519
/run/codex-home/.ssh/id_ed25519.pub
```

`/run/work` is recursive, including `.git` and uncommitted regular files.

---

## Excluded paths

Examples of data that are not included:

- `/dev`
- `/proc`
- `/sys`
- `/etc`
- block devices
- Dropbear server keys
- `authorized_keys`
- internal storage
- APFS
- NVRAM

---

## Save a baseline development environment

Stop editing `/run/work` and stop active Codex commands before saving.

Then run:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

---

# Snapshot compatibility matters

A RAM snapshot is not just a generic copy of `/run/work`.

Compatibility is bound to immutable inputs such as:

- boot payload
- development-tool bundle
- installer/runtime identity
- schema version
- per-file hashes

This means a snapshot created with:

```text
baseline
```

must not be treated as compatible with:

```text
wifi-t7000-leaf
```

Likewise:

```text
DevelopmentProfile minimal
```

and:

```text
DevelopmentProfile development
```

represent different base configurations.

**When BootProfile or DevelopmentProfile changes, create a new compatible
snapshot for that configuration.**

---

# Saving RAM state for a Wi-Fi BootProfile

`Save-A1625RamEnvironment.ps1` defaults to the baseline payload:

```text
artifacts\hoolock\payload\m1n1-linux-a1625-minimal-ssh.bin
```

If the running environment was booted with `wifi-t7000-leaf`, explicitly select
the matching payload when saving:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1 `
  -DevelopmentProfile development `
  -PayloadPath .\artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.bin
```

Restore it later with the same logical configuration:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState
```

---

# Codex CLI

Codex CLI has been validated on the A1625 RAM rootfs.

Start Codex directly after restore:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -StartCodex
```

Or start it from the interactive shell:

```sh
codex-ram
```

First-time login:

```powershell
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -Login
```

Save Codex authentication state to Windows DPAPI:

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
```

Codex authentication state and the general RAM snapshot are separate storage
mechanisms.

More detail:

- [Codex runtime](windows-native/codex-runtime/README.md)
- [Codex state](windows-native/codex-state/README.md)

---

# Built-in Wi-Fi

## Current validated configuration

Validated on the owned A1625:

- Apple TV HD A1625 / J42d / T7000
- Broadcom BCM4350
- PCIe
- `wifi-t7000-leaf`
- Japan regulatory configuration
- WPA2-PSK
- AES / CCMP
- DHCP
- DNS
- HTTPS with CA verification
- Dropbear SSH bound to the Wi-Fi IPv4 address
- Wi-Fi SSH after physically disconnecting USB data

Not currently claimed:

- WPA3
- validation for other regulatory regions
- persistent Wi-Fi installation
- automatic Wi-Fi startup at boot
- long-duration reliability guarantees
- fully automatic recovery after supervisor failure
- full RF calibration or regulatory certification

---

# Wi-Fi firmware

The tested firmware candidate is:

```text
brcm/brcmfmac4350-pcie.bin
```

Version:

```text
7.35.180.119
```

SHA-256:

```text
5691d1e0ceb70baf18efb7a0ec6cb84feb9edd2d0700c525b42930c4e7e4b845
```

The firmware binary is not distributed by this repository.

Do not commit device MAC addresses, raw calibration data, Apple-derived
firmware/NVRAM data, or other device-specific blobs.

Do not substitute NVRAM from another board or guess calibration conversions.

More detail:

[windows-native/wifi/README.md](windows-native/wifi/README.md)

---

# Build the Wi-Fi userspace bundles

From the repository root:

```powershell
python .\windows-native\wifi\build_userland.py
```

Using only the existing package cache:

```powershell
python .\windows-native\wifi\build_userland.py --offline
```

Output:

```text
artifacts\wifi-userland\reproduced\
```

The WPA, curl, and iw bundles are built from pinned package inputs and verified
against expected hashes.

---

# Save the Wi-Fi credentials

Run once:

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

SSID and WPA2 passphrase are entered as hidden input.

Default storage:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi
```

The profile is encrypted with Windows CurrentUser DPAPI.

The current tested profile is intentionally constrained to:

```text
country=JP
WPA2-PSK
RSN
pairwise=CCMP
group=CCMP
```

Do not place SSIDs, passphrases, or PSKs in command-line arguments, logs, or the
Git repository.

---

# Boot for Wi-Fi

Start from a fresh DFU / Pongo boot and select the Wi-Fi payload:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

Selecting `wifi-t7000-leaf` alone does **not** mean the Wi-Fi radio is
automatically started as a permanent service.

The current design manages PCI / DART / MSI / firmware lifetime as an explicit
RAM session.

After a cold boot, follow:

[windows-native/wifi/session-workflow.md](windows-native/wifi/session-workflow.md)

to stage the required firmware, regulatory database, module, runner, and
userspace assets and start the Wi-Fi hardware hold.

Representative live-state indicators include:

```text
/run/a1625-wifi/runner.pid
/sys/class/net/wlan0
```

---

# Connect-A1625Wifi.ps1

Once the Wi-Fi hardware session is active:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1
```

The helper verifies or starts WPA / DHCP / WLAN Dropbear as appropriate.

After a successful connection it saves the Wi-Fi IPv4 address to:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

Example:

```text
192.168.1.123
```

---

## USB behavior

The helper first tries the saved Wi-Fi address.

```text
last-address.txt
        ↓
healthy Wi-Fi SSH session
        ↓
complete without USB
```

If Wi-Fi is not reachable, it falls back to the USB NCM address:

```text
172.16.42.1
```

Important limitation:

**A cold state with no active Wi-Fi hardware session cannot currently bootstrap
Wi-Fi with no management path at all.**

The current RAM-only design still needs an existing control path, normally USB
NCM SSH, to stage the WPA configuration and start the network supervisor when
Wi-Fi is not already running.

`Connect-A1625Wifi.ps1` intentionally does not blindly restart the PCI / DART /
firmware hardware hold.

Typical flow:

```text
fresh DFU boot
    ↓
USB NCM / ACM
    ↓
start Wi-Fi hardware session
    ↓
Connect-A1625Wifi.ps1
    ↓
WPA / DHCP / WLAN SSH
    ↓
save Wi-Fi IPv4 address
    ↓
physically disconnect USB data
    ↓
continue over Wi-Fi SSH
```

---

# Wi-Fi SSH

After DHCP succeeds, a separate Dropbear listener is bound to the Wi-Fi IPv4
address on port 22.

User:

```text
root
```

It reuses the same RAM-session Dropbear host key that was already verified over
USB ACM.

For Wi-Fi SSH, use:

```text
HostKeyAlias=172.16.42.1
```

so strict host-key checking remains anchored to the key verified for the current
RAM boot.

Do not disable host-key checking.

---

# Enter-A1625WifiShell.ps1

Once `Connect-A1625Wifi.ps1` has stored a successful Wi-Fi address:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1
```

is normally enough to open the Wi-Fi shell.

Manual override remains available:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1 `
  -Address 192.168.1.123
```

Saved address:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

The shell starts in:

```text
/run/work
```

---

# Verify Wi-Fi with USB physically disconnected

After confirming Wi-Fi works, physically disconnect USB data and run:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address '192.168.1.123' `
  -KnownHostsPath '<current-boot-known-hosts-path>' `
  -RequireUsbDisconnected
```

The test checks at least:

- hardware runner
- network supervisor
- DHCP client
- `wpa_state=COMPLETED`
- WPA2 / CCMP
- power saving disabled
- DNS
- HTTPS bound to `wlan0`
- TLS certificate verification
- strict-host-key Wi-Fi SSH
- absence of matching USB devices on Windows

---

# Stop the Wi-Fi session

Stop networking only:

```sh
kill -TERM "$(cat /run/a1625-wifi/network.pid)"
```

Stop the Wi-Fi hardware session:

```sh
kill -TERM "$(cat /run/a1625-wifi/runner.pid)"
```

The session cleanup is designed to restore Wi-Fi routes / DNS and release the
temporary PCI / DART / MSI / power resources in the validated sequence.

See:

[windows-native/wifi/session-workflow.md](windows-native/wifi/session-workflow.md)

---

# Windows-side state locations

| State | Default location |
| --- | --- |
| device config / per-boot known_hosts / Codex state | `%LOCALAPPDATA%\AppleTvA1625\state` |
| RAM-state snapshots | `%LOCALAPPDATA%\AppleTvA1625\ram-state` |
| Wi-Fi DPAPI profile | `%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi` |
| last successful Wi-Fi IPv4 address | `%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt` |
| host-side logs | `%LOCALAPPDATA%\AppleTvA1625\logs` |

The Wi-Fi IP itself is not a credential, but SSIDs, PSKs, authentication tokens,
private keys, and device-specific identity information must remain private.

---

# Validation-only mode

To validate local artifacts and snapshot compatibility without USB transfers or
network changes:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -DevelopmentProfile development `
  -ValidateOnly
```

Wi-Fi payload:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -ValidateOnly
```

`-ValidateOnly` does not start a device boot.

---

# Diagnostics

Run a read-oriented diagnostic:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\atv-native.ps1 diagnose
```

Monitor USB re-enumeration for 30 seconds:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\atv-native.ps1 watch `
  -TimeoutSeconds 30
```

Record the current service-mode USB topology baseline:

```powershell
& .\windows-native\atv-native.ps1 baseline
```

Run the self-contained tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\tests\AtvNative.Tests.ps1
```

The generated:

```text
windows-native/device-baseline.json
```

may contain private USB identity or topology information and must not be
committed.

---

# Troubleshooting

## `Enter-A1625WifiShell.ps1` is not found

Verify the filename:

```text
Enter-A1625WifiShell.ps1
```

List matching files:

```powershell
Get-ChildItem .\windows-native\wifi\Enter-A1625*
```

---

## `Connect-A1625Wifi.ps1` fails without USB

USB-less operation is possible only when:

- the WLAN session is already alive, and
- the saved Wi-Fi address still reaches the A1625 Dropbear listener.

Check the saved address:

```powershell
Get-Content "$env:LOCALAPPDATA\AppleTvA1625\wifi\last-address.txt"
```

If the Wi-Fi session itself is no longer running, a cold-state bootstrap still
requires an existing management path such as USB.

---

## `RestoreRamState` reports an incompatibility

The snapshot may have been created with a different BootProfile or
DevelopmentProfile.

In particular:

```text
baseline
```

and:

```text
wifi-t7000-leaf
```

are different payloads.

Create a new snapshot for the selected configuration.

---

## `EnableZram` fails

`-EnableZram` requires either:

```powershell
-DevelopmentProfile minimal
```

or:

```powershell
-DevelopmentProfile development
```

Example:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram
```

---

## Both `StartCodex` and `EnterShell` were specified

Choose one:

```powershell
-StartCodex
```

or:

```powershell
-EnterShell
```

---

## An experimental BootProfile cannot replace the running Linux session

Non-`baseline` profiles require a fresh DFU / Pongo stage.

Do not replace an existing Linux session in place.

---

## SSH host-key mismatch

The Dropbear host key changes on every RAM boot.

Do not work around this with:

```text
StrictHostKeyChecking=no
```

Use the known-hosts file generated for the current boot:

```text
%LOCALAPPDATA%\AppleTvA1625\state\known_hosts_ram_*
```

---

# Security boundary

## Apple TV internal storage

The RAM-only workflow is intentionally scoped so that it does not:

- mount internal block storage
- mount APFS
- write NVRAM
- restore or update tvOS
- create a fakefs

## SSH

- password login is not used
- public-key authentication only
- the per-boot host key is verified via USB ACM
- strict host-key checking remains enabled
- private keys must not be committed

## Wi-Fi credentials

- Windows CurrentUser DPAPI
- no plaintext temporary file
- no PSK in command-line arguments
- credential bytes are transferred over authenticated SSH stdin
- runtime configuration remains under private RAM paths
- credentials must not be committed

## RAM-state snapshot

- Windows CurrentUser DPAPI
- no plaintext archive is written to Windows disk
- archive paths, file types, and sizes are validated
- payload/runtime compatibility is hash-bound

---

# Power loss

This Linux environment is RAM-only.

Power loss removes RAM-resident state such as:

- `/run/work`
- development tools
- zram
- Codex runtime
- Wi-Fi processes
- runtime Wi-Fi configuration
- DHCP lease state
- Dropbear host key

Save required work before powering off:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

For a Wi-Fi BootProfile, select the matching `-PayloadPath` as described above.

---

# Validated USB identity

Target:

```text
Apple TV HD
A1625
AppleTV5,3
J42d
T7000
```

Validated identifiers:

```text
CPID = 0x7000
BDID = 34
```

USB IDs:

```text
Normal mode  05AC:12A7
DFU          05AC:1227
PongoOS      05AC:4141
Linux gadget 05AC:4142
```

Linux USB NCM address:

```text
172.16.42.1/24
```

SSH:

```text
root@172.16.42.1:22
```

---

# Documentation map

| Document | Purpose |
| --- | --- |
| `README.md` | Main user guide |
| `README.ja.md` | Japanese main user guide |
| `windows-native/development-tools/README.md` | RAM development layer |
| `windows-native/ram-state/README.md` | `/run/work` and state save/restore |
| `windows-native/codex-runtime/README.md` | Codex runtime |
| `windows-native/codex-state/README.md` | Codex credential state |
| `windows-native/wifi/README.md` | BCM4350 / firmware / Wi-Fi technical details |
| `windows-native/wifi/session-workflow.md` | Wi-Fi startup and cleanup |
| `windows-native/wifi/acceptance-2026-09-09.md` | Wi-Fi acceptance record |
| `windows-native/DRIVER-ROLLBACK.md` | Zadig / libusbK rollback |
| `windows-native/VALIDATION-ISSUES-3-4.md` | development / zram / RAM-state validation |
| `THIRD_PARTY_NOTICES.md` | third-party provenance and notices |
| `SECURITY.md` | security policy |

---

# Recommended operating patterns

## Use the A1625 as a USB-connected development machine

First boot:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

Work in:

```sh
cd /run/work
```

Before shutdown:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

Next boot:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

## Use the A1625 as a Wi-Fi development machine

Create the Wi-Fi profile once:

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

Fresh DFU boot:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

Start the Wi-Fi hardware session according to:

```text
windows-native/wifi/session-workflow.md
```

Connect networking:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1
```

Open the Wi-Fi shell:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1
```

Validate USB-independent Wi-Fi operation:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address (Get-Content "$env:LOCALAPPDATA\AppleTvA1625\wifi\last-address.txt").Trim() `
  -KnownHostsPath '<current-boot-known-hosts-path>' `
  -RequireUsbDisconnected
```

Save a snapshot tied to the Wi-Fi payload:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1 `
  -DevelopmentProfile development `
  -PayloadPath .\artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.bin
```

---

# Safety boundary

Use this project only on an owned or explicitly authorized A1625.

The following are intentionally outside the RAM-only workflow:

- tvOS restore
- erase
- update
- internal partition modification
- APFS write
- NVRAM write
- palera1n fakefs
- generalization to other models
- automated DFU entry

If a RAM boot fails, do not switch to internal-storage operations as a recovery
shortcut.

If a USB driver was changed, restore the original driver for that exact device
instance.

---

# License and third-party software

See [LICENSE](LICENSE) for this repository's license.

For upstream source, third-party software, firmware provenance, and notices, see:

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

and the README files in the relevant subdirectories.

Apple, PongoOS, palera1n, Hoolock Linux, OpenAI Codex, and other names belong to
their respective owners. This research project does not imply official support,
endorsement, or affiliation with those projects or companies.
