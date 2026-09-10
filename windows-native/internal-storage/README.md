# A1625 internal storage research (Issue #5)

Status: **inventory stage; no block driver or storage access is implemented**.
The default RAM-only boot and its rejection of non-zram block devices are
unchanged. No ReadWrite mode is provided.

The [completion audit](completion-audit.md) records the remaining acceptance
criteria and the reference/diagnostic environment needed to resume hardware
bring-up. The current evidence does not justify an automatic ANS power-on.
The owner has confirmed that no existing tvOS diagnostic environment is
available; [temporary diagnostic acquisition](diagnostic-acquisition.md) is
being evaluated instead.

## Reproduce the sanitized ADT inventory

From the repository root, using native Windows Python:

```powershell
python windows-native/internal-storage/inspect_storage_adt.py artifacts/internal-storage/live-20260909.adt.bin
python windows-native/internal-storage/inspect_storage_platform.py artifacts/internal-storage/live-20260909.adt.bin
python -m unittest discover -s windows-native/internal-storage/tests -v
python -m unittest discover -s windows-native/wifi/tests -p test_inspect_adt.py -v
```

The input is a private RAM ADT capture, not a NAND dump. The script checks
AppleTV5,3/J42d identity, the old ANS/nub compatibles and address cell widths.
It translates little-endian ADT register tuples through the captured arm-io
ranges, rejecting missing, overflowing, crossing or ambiguously mapped ranges.
Only explicitly selected topology properties appear in its output. ECID,
serial numbers, credentials, calibration, NVRAM and firmware segment contents
are not exported. Raw captures belong under ignored `artifacts/`.

The checked-in `a1625-adt-inventory.json` was generated from the owned device.
It is evidence for topology, not authorization to access every register in
those ranges. Do not treat ADT phandles or gate IDs as Linux phandles.

`a1625-platform-inventory.json` additionally resolves the ANS/DEBUG gate
registers and the AIC interrupt parent. See [port investigation](upstream-port-notes.md)
for the pinned upstream ANS1 reader discovered after the initial inventory,
its Linux port requirements and the remaining hardware evidence gaps.

A [PMGR-only diagnostic](probe/README.md) was built for the running baseline
using an isolated native Windows build tree and executed once. ANS and DEBUG
both reported OFF; USB/SSH remained available and the module released itself.
It adds no storage driver or mailbox access.

## Observed on 2026-09-09

Read-only SSH checks identified Apple TV HD with `apple,j42d` and `apple,t7000`
compatibles. The running kernel reported `7.2.0`, 4 KiB pages and only zram0 in
`/proc/partitions`. `ttyGS0` was present and usb0 was up after collection.
This checks ACM enumeration, not an interactive ACM session.

The capture read only `/dev/mtd1ro` after checking sysfs name `adt`, type `ram`
and size 98304 bytes. The host copy's SHA256 matched the device's hash.
The older Wi-Fi research ADT had a different whole-file hash; comparison found
seven changed property values, but the entire allowlisted ANS inventory was
identical. No firmware transfer, MMIO access or mailbox command followed the
hash discrepancy. The report was regenerated from the fresh capture.

Measured register translations:

| ADT bus address | Physical address | Length |
| --- | --- | --- |
| 0x08040000 | 0x208040000 | 0x2000 |
| 0x08060000 | 0x208060000 | 0x1000 |
| 0x0e020000 | 0x20e020000 | 0x1000 |
| 0x00f00000 | 0x200f00000 | 0x100000 |

ANS uses `iop,s5l8960x`, with child `iop-nub,rtbuddy`. Interrupt entries are
0x25, 0x24, 0x27, 0x26; clock gates are 0x16 and 0x35; power gate is 0x16.
These values are from A1625 itself, not copied from an iPhone.

The locally available AppleTV5,3 tvOS 12.4 kernelcache also contains
`com.apple.driver.AppleA7IOP` and `com.apple.driver.RTBuddy`. Static presence
does not establish a running ASP endpoint, its message protocol or disk geometry.

## Required evidence before advancing

1. A1625 tvOS IORegistry service tree including ANSEndpoint1/ASPStorage,
   disk0 logical block size/capacity, GPT primary/backup metadata and bounded
   reference sector hashes. No such evidence has been collected in this stage.
2. Resolve A1625 gate/IRQ mappings against the pinned kernel and identify
   safe register read semantics from matching code before any live probe.
3. Implement and validate a bounded old RTBuddy transport and ASP read protocol.
   Do not bind ANS2/RTKit based only on a new compatible string.
4. Only then expose a kernel-enforced read-only block device, reject writes,
   compare tvOS/Linux sector hashes, and test bounded sequential/random reads,
   USB/SSH continuity and cold boot reproducibility.

Do not mark Issue #5 complete based on this inventory. Its live IORegistry,
block enumeration, kernel read-only enforcement, sector comparison and cold
boot acceptance criteria remain open. No kernel/DT payload patch is supplied
at this stage because the probe prerequisites have not been verified.

An existing tvOS diagnostic/SSH environment or previously captured data is
needed for the reference inventory. Installing a jailbreak, restoring tvOS or
changing persistent state is outside this stage and requires separate explicit
confirmation under the repository instructions.

## Primary references

- [Issue #5](https://github.com/tkinjo1985/a1625-linux-winboot/issues/5)
- [Hoolock A8 feature status](https://github.com/HoolockLinux/docs/blob/master/features/A8.md)
  lists internal storage as WIP (checked 2026-09-09).
- [Pinned Hoolock Linux](https://github.com/HoolockLinux/linux/tree/958481f87fee0949ff6a9a4af77f7eb6dac8a149)
  matches the local source checkout.
- [External T7000 research](https://github.com/nicv1990/iphone6plus-android-port/blob/main/A8_STORAGE_FINDINGS.md)
  concerns iPhone7,1; it is comparative research, not A1625 validation.
