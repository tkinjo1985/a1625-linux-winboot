# A1625 built-in Wi-Fi — Issue #2

**Status (2026-09-09): Wi-Fi initializes and connects on the owned A1625.**
The `wifi-t7000-leaf` RAM kernel has passed WPA2-PSK/CCMP association, DHCP,
DNS, certificate-verified HTTPS, and SSH addressed directly to its Wi-Fi IP.
Those checks also passed after physical USB disconnection. This is a RAM-only
research session, not an installed or automatic boot-time network service.
See [the acceptance record](acceptance-2026-09-09.md) for evidence and limits.
Use [the session workflow](session-workflow.md) for RAM startup and cleanup.

## Reproduce the tested userland

Run `python windows-native/wifi/build_userland.py` from the repository root
with native Windows Python. `--offline` uses the existing APK cache. The
checked-in `userland.lock.json` pins the official Alpine aarch64 package and
resulting WPA, curl and iw bundle hashes. Outputs go to ignored
`artifacts/wifi-userland/reproduced/`. No firmware or credentials are bundled.
The RAM root must already provide musl and `/etc/ssl/certs/ca-certificates.crt`.
This builder stages executable/library archives only; it does not install
packages, change the device, or establish a network connection.

On 2026-09-08, the owned AppleTV5,3/J42d booted kernel `7.2.0` and answered SSH
over USB NCM. Its Apple Device Tree (ADT) identifies a **BCM4350 on PCIe port 1**.
A temporary Windows-hosted probe has now established the PCIe link and read
endpoint `01:00.0`: **Broadcom `14e4:43a3`, PCI revision `08`, subsystem
`106b:10fe`**. A subsequent BAR0 read returned chipcommon ID `0x17084350`:
**BCM4350 internal revision 8**. The local driver selects the
`brcmfmac4350-pcie` firmware family for this revision. Board-specific firmware
and NVRAM compatibility still need validation. A bounded Linux PCI scan now
enumerates both the root port and endpoint, with BAR0 size 32 KiB and BAR2
size 4 MiB. Subsequent driver binding, firmware loading and Wi-Fi connectivity
passed with the combined T7000 DART changes described in the acceptance record.
The probe restores bus numbers, stops the link and powers the radio off.

The requested deployment is **Japan, WPA2-PSK/AES (CCMP)**.

## Firmware candidate and board data

The upstream `brcm/brcmfmac4350-pcie.bin` candidate has been obtained from
[linux-firmware commit 87b6caca](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/87b6caca228e10537f6206b7c17f8da90666a1cc).
It is 626,140 bytes, version `7.35.180.119`, FWID `01-e791c176`, SHA256
`5691d1e0ceb70baf18efb7a0ec6cb84feb9edd2d0700c525b42930c4e7e4b845`.
The binary, WHENCE, license and provenance stay in ignored research artifacts.
At this commit the license is under `LICENSES/LICENCE.broadcom_bcm43xx`.
The saved license permits use/integration and distribution of the complete,
unmodified binary for its intended Broadcom ICs, subject to its conditions,
including supplying the license and retaining notices. It restricts modification
and reverse engineering of that firmware. This repository distributes neither
this binary nor Apple-derived firmware; obtain the exact upstream file and
retain its license locally. Hardware compatibility was tested separately.

This exact candidate has now initialized the radio and passed the WPA2 test.
The live ADT contains board RX/TX calibration properties under
`/arm-io/uart2/wlan`, but no ready-to-use brcmfmac NVRAM text was identified
there. Those raw calibration values and the MAC address remain private.
Do not substitute another board's NVRAM or guess a calibration conversion.
Native Linux PCI/DART/MSI integration must precede a firmware test. The local
`brcmfmac/pcie.c` marks external NVRAM, CLM and TXCAP requests optional;
`firmware.c` permits missing optional NVRAM, and the PCIe download path can
start the chip without an external NVRAM blob. Therefore acquiring a separate
NVRAM file is not an established prerequisite for firmware initialization.
The tested session initialized without an external NVRAM blob. Japan country
configuration and channel restrictions were observed; this connection test
does not establish full RF calibration or regulatory certification.

## Read-only ADT collection

Run in PowerShell 7 with the known-hosts file verified during the current boot:

```powershell
& .\windows-native\wifi\Get-A1625WifiAdt.ps1 -KnownHostsPath '<current-boot-known-hosts-path>'
python .\windows-native\wifi\inspect_adt.py .\artifacts\wifi-research\a1625.adt.bin
```

The collector verifies Linux's J42d/T7000 identity, finds exactly one MTD named
`adt` of type `ram`, and reads its **read-only** device node. MTD here is the
m1n1 RAM copy, not Apple TV internal flash. It never reads another MTD and never
writes to the device. The 2026-09-08 capture was 98,304 bytes; reserved-memory
nodes used `phram` and sysfs reported `ram`.

The raw dump contains individual device data. It stays in ignored
`artifacts/wifi-research` with a restricted Windows ACL; do not attach or commit
it. The parser checks model/board, bounds, counts, nesting, and duplicate paths.
Its output includes only an allowlist of hardware properties. MAC addresses,
calibration, NVRAM data, serial numbers, and random seeds are omitted.
Hexadecimal integers in its output are raw little-endian ADT bytes, **not DTS
cells**; do not paste them into a DTS unchanged.

## What the owned device establishes

| Item | Evidence | Remaining work |
|---|---|---|
| Wi-Fi chip | Live PCI `14e4:43a3`; chipcommon `0x17084350`, internal revision 8 | Validate firmware initialization and board data requirements |
| Host controller | T7000 port 1; root port `106b:1002`; temporary link and configuration reads work | Integrate verified sequence into Linux PCI host support |
| Power/clocks | PMGR domains, PHY controls and rollback tested together | Integrate lifetime and error handling with host driver |
| Wi-Fi enable | PMU GPIO3 register `0x406`: `0x02` on / `0x00` off, verified | Integrate with driver power management |
| Port controls | GPIO77 reset, GPIO41 clock request verified during successful link training | DEVICE_WAKE behavior and power management remain pending |
| IRQ | Host ADT interrupt entries 212, 215; DART 216 | Establish host/port/MSI mapping; do not conflate these with Linux IRQ numbers |
| DMA | DART driver registered and removed on-device; 4 KiB pages, four streams, 32-to-36-bit addresses | Deploy TCR fix, attach stream 0 and verify actual translation before endpoint DMA |
| MSI | ADT address `0xbffff000`, vector offset 224, port base 8, port count 8 | Verify controller programming and reserve doorbell from IOVA |

The bounded probe sequence and observed rollback are documented in
[pmu-probe/README.md](pmu-probe/README.md). These results do not validate a
complete PCI host driver or DMA path. Do not substitute M1 initialization.

## Kernel and bootloader investigation history

The following records the initial 2026-09-08 investigation. Its unresolved
PCI/DART/MSI and enumeration stages were subsequently implemented and tested;
the acceptance record and session workflow describe the current state.

The local kernel source revision is
`958481f87fee0949ff6a9a4af77f7eb6dac8a149`. Its configuration has
`CONFIG_ARM64_4K_PAGES=y`, `CONFIG_PCIE_APPLE=y`, but `CONFIG_WLAN` and
`CONFIG_MMC` are disabled. Its T7000/J42d DTS has no PCIe/WLAN/DART device nodes.
The running system has no PCI devices and no `/sys/class/ieee80211`.

The latest Hoolock kernel examined on 2026-09-08,
[`6831bc701a6ce059e71e5aaa9488c9195bea6927`](https://github.com/HoolockLinux/linux/tree/6831bc701a6ce059e71e5aaa9488c9195bea6927),
also lacks that J42d integration. Its `pcie-apple.c` matches `apple,pcie` to
M1 hardware data, plus a T6020 variant. This is not evidence for T7000 support.
Hoolock m1n1
[`d5a10ac52a6468484854419a6c5130f1d62073eb`](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/pcie.c)
rejects unsupported PCIe compatibles and has no `apcie,t7000` branch.

The Linux Broadcom PCIe driver has BCM4350 firmware mappings, but enabling
`CONFIG_CFG80211`, `CONFIG_WLAN`, `CONFIG_BRCMFMAC`, and `CONFIG_BRCMFMAC_PCIE`
alone cannot make an uninitialized host controller enumerate. Keep the
validated boot artifacts and their hash gates intact until a separate,
reviewed experimental payload is ready.

An additional offline investigation on 2026-09-08 retrieved the AppleTV5,3
tvOS 12.4 / 16M568 kernelcache directly from Apple's distribution CDN. It
contains T7000-specific PCIe and D2186 PMU drivers. Initial inspection confirms
that its PCIe/PHY register layout differs from the M1 driver. The old prelinked
Mach-O format required local metadata inspection rather than the extractor's
newer fileset workflow. Acquisition provenance, hashes and analysis remain in
the ignored research directory. A complete, reviewed initialization sequence
has **not** yet been derived. That offline stage performed no device writes
or experimental boot.

Further static analysis resolved the port's MSI count/base encoding, the
link-start operation, and the microsecond unit of the reference-clock wait.
The MSI address-routing and PMU/GPIO sequence remain under investigation.
The existing kernel configuration enables loadable modules and Device Tree
overlays, so an eventual temporary driver may be tested within the running RAM
environment. This possibility is not a verified runtime installation path.

A [read-only PMU probe](pmu-probe/README.md) has now been built on Windows and
run against the matching live kernel. It read WL_REG_ON GPIO3 configuration
register `0x406` as `0x00`, using the existing PMU regmap. The dedicated runner
executed exactly one read and the probe did not remain loaded; USB SSH stayed
available. No GPIO or power registers were written. This verifies the small
diagnostic module path only; PCIe, DART, MSI and Wi-Fi remain uninitialized.

The next bounded power-control test also passed: with PERST held output-low,
WL_REG_ON was enabled for 100 ms and CLKREQ changed low. Power and GPIO state
were restored and independently checked; USB SSH remained available. This
temporary test used the owned board's PMU/GPIO registers, without enabling
PCIe or DMA or writing internal storage. See the probe documentation for the
exact sequence and rollback behavior. Radio enumeration and connectivity
remain unverified.

## Firmware and individual board data

The candidate driver is `brcmfmac` (PCIe), not a BCM4354 SDIO configuration.
Its BCM4350 mapping selects `brcmfmac4350c2-pcie` or `brcmfmac4350-pcie` by
chip revision. Do not choose a filename or firmware based only on the ADT name.
The tested revision initializes without external NVRAM, using the firmware's
reported MAC and the JP configuration; no MAC spoofing is performed. Full RF
calibration is outside these connectivity tests. A firmware `.txt` named NVRAM
is an input uploaded into radio RAM;
it is not authorization to modify platform NVRAM.

For acquisition, first inspect the exact file's license in the official
linux-firmware repository if a compatible file exists. A matching chip number
does not establish board compatibility or redistribution permission. Otherwise
use an authorized local copy of the matching tvOS firmware, subject to its
terms, and perform extraction on the Windows host without restoring/updating
the Apple TV or mounting its internal storage. This acquisition path has not
yet been validated for J42d Wi-Fi. The current Hoolock `hKernelFWExtractor`
source tree contains a PMP extractor; its general project description is not
evidence that it extracts BCM4350 Wi-Fi firmware.

No Apple firmware, NVRAM file, calibration blob or MAC is included here.
No redistribution rights for Apple-derived data have been established.
Keep inputs private and ignored, record provenance/hashes locally, and publish
only independently written tooling and reviewed hardware facts.

## Protected Windows profile

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

Both inputs are hidden. The script validates SSID length in UTF-8 bytes and an
8–63 printable-ASCII WPA2 passphrase, derives the PSK, and encrypts the profile
with Windows **CurrentUser DPAPI**. The default is
`%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi`, with a restricted ACL.
The PSK is itself a credential. Do not print module return values or place them
in transcripts. Plaintext exists in process memory; managed strings cannot be
reliably zeroed. No plaintext temp file or command-line secret is used.

This command saves a profile only; it does not enable Wi-Fi. The in-memory
configuration serializer uses hex SSID/PSK, `country=JP`, `proto=RSN`,
`pairwise=CCMP`, `group=CCMP`, and `update_config=0`.

After hardware initialization is verified, a connection installer should pipe
these bytes through authenticated SSH stdin into a root-only directory on
`/run` tmpfs, with mode 0600, never via a shell argument. Preserve USB NCM/ACM
and restore routes/DNS on connection failure. This transfer/connection stage
is **not implemented or tested** yet.

## Userland and acceptance sequence

The signed regulatory database from the
[official wireless-regdb repository](https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/)
at `389b9b702cf9018e9a9078ccc4fa8eaae2e054e3` was verified offline and placed
in the running RAM root's `/lib/firmware` on 2026-09-08. The detached signature
passed verification against a certificate identical to the kernel's embedded
`wens` certificate. Database SHA256:
`7e236caecd939c8ec98be4870bf30422f28ffef2565a38aaaa2d9ddabd0c2641`;
signature SHA256:
`50332f0db09b8bcc719235ec4985c27377f2cc2f42abb7b5dcf951866c5a888a`.
Both remote file hashes matched. `iw reg reload` and `iw reg set JP` then
returned success, and `iw reg get` reported `country JP: DFS-JP`. This verifies
the global kernel domain. Subsequent PHY registration exposed channels 1–13,
disabled channel 14 and applicable 5 GHz channels under JP. The initial
missing-database boot log is historical.
The RAM-only `iw 6.17` and two libnl libraries came from Alpine v3.23 aarch64
packages. Their control-stream hashes matched the previously pinned APKINDEX,
and their data-stream hashes matched the control metadata before extraction.

Use the existing BusyBox initramfs, `wpa_supplicant` with nl80211, `wpa_cli`,
`iw`, and BusyBox `udhcpc`. Add only the libraries required by the selected
supplicant build. Keep the existing CA bundle, HTTPS client, and Dropbear.
No systemd or GUI is needed. WPA3 would additionally require SAE/PMF support
in userspace, kernel and firmware; that capability is not claimed here and
the user's WPA2 profile must not silently fall back to another mode.

1. Review T7000 PCIe/PMU/PHY/DART/MSI implementation and a 4 KiB experimental
   kernel, then verify repeated RAM boots with NCM and ACM still working.
2. Enumerate the radio; verify PCI/chip revision, load matching private firmware
   and calibration, and check stable interface creation without DMA faults.
3. Apply JP regulatory settings; inspect effective kernel/firmware restrictions.
   Preserve the owned radio's valid unicast MAC without committing it. Do not
   force a broad country map or a different device's calibration.
4. Associate to the specified WPA2-CCMP AP, obtain DHCP, and test DNS plus HTTPS
   with CA validation and a correct clock. Bind tests/routes to Wi-Fi so USB NAT
   cannot make a failed Wi-Fi test look successful.
5. Start a separate Dropbear listener on the Wi-Fi address, using the same
   RAM host key. The current init binds Dropbear only to `172.16.42.1:22`;
   a DHCP lease alone does not expose SSH on Wi-Fi. Pin the current boot's
   verified key for the Wi-Fi address; never disable host-key checking.
6. Open an independent Wi-Fi SSH session from Windows, physically disconnect
   USB data, and repeat SSH/DNS/HTTPS and a sustained session test. User action
   is needed for physical unplug/replug. Record results without SSID/MAC/keys.

The connection, USB-removal and session lifecycle checks now have real-device
evidence in the acceptance record, alongside the source audit. Earlier
research-stage limitations above are historical where superseded by that record.

## Validation

```powershell
python -m unittest discover -s .\windows-native\wifi\tests -v
pwsh -NoProfile -File .\windows-native\wifi\tests\WifiProfile.Tests.ps1
```

2026-09-08: five parser tests passed (truncation, invalid counts, duplicate
paths, wrong model, private-value omission); the public WPA PSK vector,
input/config validation, DPAPI round trip and tamper rejection passed.
The collector successfully retrieved the owned device's RAM ADT with strict
SSH host verification. These are tooling tests, not Wi-Fi connectivity tests.

## Primary references

- [Hoolock J42d DTS](https://github.com/HoolockLinux/linux/blob/6831bc701a6ce059e71e5aaa9488c9195bea6927/arch/arm64/boot/dts/apple/t7000-j42d.dts)
- [Hoolock PCIe driver](https://github.com/HoolockLinux/linux/blob/6831bc701a6ce059e71e5aaa9488c9195bea6927/drivers/pci/controller/pcie-apple.c)
- [Hoolock DART documentation](https://github.com/HoolockLinux/docs/blob/23ebe1fbc375599221553a7e1815e5de182a6b42/hw/DART.md)
- [m1n1 RAM ADT export (`dt_setup_mtd_phram`)](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/kboot.c)
- [Broadcom PCIe firmware mapping](https://github.com/HoolockLinux/linux/blob/6831bc701a6ce059e71e5aaa9488c9195bea6927/drivers/net/wireless/broadcom/brcm80211/brcmfmac/pcie.c)
- [wpa_supplicant configuration reference](https://android.googlesource.com/platform/external/wpa_supplicant_8/+/refs/heads/main/wpa_supplicant/wpa_supplicant.conf)
- [Hoolock firmware extractor source](https://github.com/HoolockLinux/hKernelFWExtractor)
