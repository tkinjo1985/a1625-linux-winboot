# Kernel prerequisites for A1625 Wi-Fi

These patches target the prepared HoolockLinux tree at
`958481f87fee0949ff6a9a4af77f7eb6dac8a149`. Patches 0001–0007 are deployed in
the tested `wifi-t7000-leaf` RAM kernel. Together with the temporary PCI host
and DMA aperture they pass WPA2 networking, including after USB removal.
See [the acceptance record](../acceptance-2026-09-09.md) for current evidence
and limitations. The sections below retain the earlier preparation history;
their pending-deployment statements describe those earlier stages.

## Packed S5L8960X DART TCR update

`0001-fix-s5l8960x-stream-tcr-mask.patch` fixes the packed per-stream TCR
read/modify/write. The original code kept only the selected byte and ORed
an unshifted value into stream 0. Even disabling stream 0 could retain its
enable bit. The fix clears only the selected byte and shifts the masked
replacement into that byte.

The regression test compiles the actual driver's read/write accessor bodies
against a RAM-backed register. It checks all four streams, enable/disable,
readback, preservation of other bytes and masking of oversized values. The
original implementation fails, while the patched implementation passes.
This verifies register-update logic, not hardware translation or DMA.
The patched `drivers/iommu/apple-dart.o` also compiled successfully for ARM64
using the repository's Windows compiler and AArch64 linker wrappers. The
running RAM kernel still contains the original driver; deployment is pending.

Run with the compiler's directory on PATH:

```powershell
python windows-native/wifi/tests/test_dart_tcr.py --cc '<native-gcc-path>' --driver third_party/HoolockLinux-linux-native/drivers/iommu/apple-dart.c
```

Apply the patch from the kernel root using `git apply --check` first. The
working kernel source was patched during this investigation; do not apply
it twice. A rebuilt kernel must retain 4 KiB pages and USB NCM/ACM support.

## A1625 MSI reservation and Wi-Fi configuration

The base configuration reserves `0xfffff000` in
`apple_dart_get_resv_regions`, but A1625's normal MSI address is `0xbffff000`.
The original Kconfig symbol has no prompt, so an ordinary configuration
fragment cannot override its default. `0002-allow-msi-doorbell-override.patch`
adds an expert prompt while retaining the original default for other builds.
It is already applied to the working source, not the running kernel.

`a1625-wifi.config` sets the evidenced address, enables cfg80211 and PCIe
brcmfmac, and retains 4 KiB pages and USB ACM/NCM. Merge it onto the existing
validated base with `scripts/kconfig/merge_config.sh -m -O <output-directory>`
and run `make olddefconfig` with `KCONFIG_CONFIG` pointing to that output's
`.config`, using the repository's Windows compiler/linker wrappers.

On 2026-09-08 the merged configuration in ignored
`artifacts/wifi-kernel-config/.config` passed `olddefconfig`: doorbell
`0xbffff000`, DART, cfg80211, brcmfmac PCIe, 4 KiB pages, ACM and NCM remained
enabled. Signed regulatory database verification remains enabled. The base
kernel `.config` still has WLAN disabled and its original doorbell value.

This prepares configuration only. It does not add a T7000 PCI host driver,
prove MSI bypasses DART, or produce a bootable Wi-Fi kernel. See
[T7000 MSI evidence](t7000-msi-notes.md) for the unresolved hardware gates.

The experimental configuration also compiled `net/wireless/` and
`drivers/net/wireless/broadcom/brcm80211/` successfully with the native
Windows toolchain on 2026-09-08. The build log contains no compiler warnings
or errors. `brcmfmac/pcie.o` is an ELF64 AArch64 relocatable object, SHA256
`96901546c20c75381e2e2fea680a8a5217f2963afc3967a028c39232edf5c633`.
Logs are in ignored `artifacts/wifi-kernel-config/wireless-build.log`.
This was a subsystem compilation, not a complete kernel link or runtime test.

Changing `KCONFIG_CONFIG` in the same prepared tree changes generated headers.
Before building probes for the base kernel again, explicitly run
`make KCONFIG_CONFIG=.config syncconfig prepare` with the same wrappers,
then verify `include/config/auto.conf` matches the base configuration.
Simply running `make prepare` can leave the experimental headers in place.
The reverse transition has the same hazard: selecting another
`KCONFIG_CONFIG` for `make Image` need not regenerate `auto.conf` when the
configuration file is older. Always run an explicit `syncconfig` after
switching configurations and check the effective `include/config/auto.conf`
before building. Confirm Wi-Fi symbols in the linked kernel as well.

The first full build on 2026-09-08 exposed this issue: it linked the TCR fix
but used the base configuration, with no cfg80211/brcmfmac symbols and the
old MSI address. Its output is isolated under ignored
`artifacts/wifi-kernel-config/tcr-only-diagnostic`, marked not for deployment.
It was not packaged or booted. A corrected build was started after explicit
synchronization and verification of Wi-Fi, 4 KiB, USB and MSI settings.

Run `../verify_wifi_kernel.py --vmlinux <linked-ELF> --config <effective-auto.conf>
--nm <llvm-nm-path>` on completed builds. It checks the AArch64 ELF header,
required effective settings, and linked cfg80211/brcmfmac/DART symbols.
The isolated incorrect build fails both with its actual configuration and
with the requested Wi-Fi configuration substituted: the missing ELF symbols
are independently detected. A passing result does not replace TCR instruction
review, Image provenance checks, or real boot/DMA/network tests.

The corrected full build subsequently passed on 2026-09-08. Its ELF build ID
is `920bcb30d52a917be12c322cca1f69e13ed7ff90`; the required linked symbols
and effective configuration passed the gate. The TCR accessor's machine code
contains the corrected mask/shift operations. Re-extracting Image from this
ELF matched the built Image exactly; the Image header specifies 4 KiB pages.

The isolated experimental RAM payload is 11,377,930 bytes, SHA256
`7886737b66da0276fba66a1fd3ca2ee69bb3aab3de8f6080b6832659ca67f9f3`.
Its m1n1, baseline J42d DTB and minimal SSH initramfs retain their verified
hashes. It booted successfully on the owned A1625 on 2026-09-08. The live
GNU build ID exactly matched the verified ELF; USB NCM, ACM host-key trust,
SSH, 4 KiB pages and RAM rootfs checks passed. The TCR fix is now running.
The baseline DTB still has no PCI/DART nodes; host integration remains pending.
cfg80211 starts, but reports missing `regulatory.db`; signed regulatory data
must be supplied before the Japan association test.

## DART device-tree preparation

`a1625-dart.dtso` describes the verified port 1 DART MMIO range and IRQ 216,
with the binding's T7000/S5L8960X compatibles and one stream argument. It
remains disabled until the host driver can maintain the power/PHY lifetime.
The loader must explicitly check J42d/T7000 identity; an overlay's root
compatible property alone does not enforce a target restriction.

The overlay compiled successfully with the prepared native `dtc`; its SHA256
is `7061e7513f5d1048c131e391bab6b385795af3b12b042fb69112a1b0b0d37648`.
Offline application to a symbol-enabled J42d DTB succeeded. Decompilation
confirmed MMIO `0x602002000`, size `0x2000`, AIC IRQ 216, and disabled status.
The existing base DTB lacks `__symbols__`, so direct overlay application to
that blob fails. The offline test rebuilt the existing preprocessed J42d
source using `dtc -@`; no boot artifact or running device was changed.

Before enabling this node, the host must own and enable all three tested
PCIe domains and initialize the PHY. DART probe resets its hardware and
registers a fault IRQ; its remove callback also resets hardware before
unregistering the IOMMU. Remove PCI clients first, then remove DART while
its registers remain accessible, and only then restore PHY and power.
Do not attach DMA clients to the running kernel's unfixed TCR implementation.
