# J42d PMU read-only probe

This diagnostic reads only the D2186 GPIO3 configuration byte at `0x406`,
through the existing `simple-mfd-i2c` driver's regmap. It checks the J42d/T7000
root compatibles, exact PMU node path, and I2C address. It does not write a
GPIO, scan registers, switch power, or initialize Wi-Fi.

The running research kernel has `CONFIG_MODULE_UNLOAD=n`. The probe therefore
returns `-ECANCELED` after releasing its references, so it does not remain
loaded. Loading an out-of-tree module still taints this temporary kernel.

**Use `run_probe_once`, not BusyBox `insmod`, for this diagnostic.** BusyBox's
[module loading code](https://github.com/mirror/busybox/blob/master/modutils/modutils.c)
can fall back from `finit_module` to `init_module` on an error, executing this
probe twice. The freestanding AArch64 runner makes one `finit_module` call
with no fallback. Its zero exit status only indicates the expected errno;
also verify a single new successful read log and absence from `/proc/modules`.

## Build on native Windows

Run `bash windows-native/wifi/pmu-probe/build.sh` in the project's MSYS2
environment. This reuses the existing Windows compiler/linker wrappers and
prepared kernel tree, without rebuilding or deploying the kernel. Outputs
are ignored under `artifacts/wifi-pmu-probe/`.

The kernel tree needs `modules_prepare` from the **same configuration and
toolchain as the running kernel**, plus `vmlinux.symvers`. Do not force module
loading past a version or symbol mismatch. Compare the running kernel's GNU
Build ID in `/sys/kernel/notes` with local `llvm-readelf -n vmlinux` first.

Transfer both binaries through verified USB SSH to a root-only directory on
`/run` tmpfs, compare SHA256 before executing, and invoke the runner with the
module's absolute path. Never deploy these files to internal storage.

## Observed on the owned A1625, 2026-09-08

- Running/local kernel Build ID: `4776c5754ce5ac725ac272d841f0a7dee2c4156a`.
- ELF: AArch64; module vermagic: `7.2.0 SMP preempt aarch64`.
- Initial BusyBox invocation unexpectedly produced two reads; both were
  `0x00`. No registers were written. Further operations stopped for diagnosis.
- Dedicated runner: argument-count error exits 2, missing file exits 1,
  neither adds a read log. Valid invocation adds exactly **one** successful
  read of `0x00`, exits 0 for expected `ECANCELED`, and leaves no loaded module.
- USB SSH remained available; interfaces were `lo`, `sit0`, `usb0`.

This establishes the present GPIO configuration only. It does not prove
electrical voltage, working PCIe enumeration, radio firmware, or Wi-Fi access.

## PCIe control GPIO snapshot

`a1625_gpio_probe.ko` uses the same runner and target checks. It reads only
pins 77 (PERST), 41 (CLKREQ), and 63 (device_wake) from the bound T7000
pinctrl driver's regmap, comparing cached and uncached values. It does not
request a GPIO, change pinmux, enable an interrupt, or write a register.

2026-09-08 live result, with matching cached/uncached values:

| Pin | Register value | Configuration decoded from the existing Linux driver |
| --- | --- | --- |
| 77, PERST | `0x00076200` | Data 0, mode 0 (not output mode 1), GPIO mux |
| 41, CLKREQ | `0x00076221` | Data 1, mode 0, peripheral mux 1 |
| 63, device_wake | `0x00072202` | Data 0, output mode 1, GPIO mux |

Exactly three pin records and one completion record appeared. The module
was absent afterwards and USB SSH remained available. Before enabling radio
power, the reset line still needs to be exclusively acquired and held in
output-low mode, with its original configuration saved for rollback. A low
data bit while the radio is off does not by itself establish a driven reset.

## Bounded power-control validation

`a1625_power_probe.ko` defaults to checking the previously observed baseline,
without writes. Passing `pulse=1` through `run_probe_once` explicitly requests
one temporary power pulse. This module checks J42d/T7000, exact device paths,
bound drivers, PMU address, and all three initial GPIO configurations.

For the pulse it exclusively requests GPIO77 using the normal GPIO consumer
API, drives PERST low, verifies the output configuration, writes `0x02` to
PMU GPIO3 (`0x406`), and reads it back. It keeps reset asserted for 100 ms,
restores PMU `0x00`, verifies that restore, waits another 100 ms, and restores
the original PERST configuration before releasing the GPIO. PCIe and DMA are
not enabled. If power restoration fails, it leaves PERST held low and reports
an error rather than releasing reset while the radio may still be powered.

The explicit invocation, after binary hash and kernel checks, is:

```sh
/run/a1625-pmu-probe/run_probe_once_v2 \
  /run/a1625-pmu-probe/a1625_power_probe.ko pulse=1
```

2026-09-08 real-device result:

- Default mode passed with no writes and no resident module.
- Pulse mode read back WL_REG_ON `0x02` and PERST `0x76202` (output low).
  CLKREQ changed from `0x76221` to `0x76220`, consistent with the powered radio
  asserting its clock request. This is not a PCIe link or firmware test.
- Rollback read back WL_REG_ON `0x00` and PERST `0x76200`.
- A subsequent independent GPIO probe verified all three cached/live values
  returned to the table above. USB SSH survived; no modules remained loaded.

This is the first temporary hardware-write stage of the Wi-Fi investigation.
It performs no persistent storage, NVRAM, driver installation, or tvOS changes.

## PCIe host power domains

`a1625_pcie_domains.ko` reads the existing PMGR state by default. With
`cycle=1`, it creates temporary consumers of the existing PCIE, PCIE_AUX and
PCIE_REF domains through `of_genpd_add_device` and runtime PM. It releases
them in reverse order and verifies the domains are off again. It does not
replace the PMGR driver or add DT phandles. All three must initially be off.

The 2026-09-08 cycle passed on the owned board:

| Domain | Offset in PMGR | Before / after | Enabled |
| --- | --- | --- | --- |
| PCIE | `0x20308` | `0x0f000200` | `0x1f0002ff` |
| PCIE_AUX | `0x20310` | `0x00000200` | `0x000002ff` |
| PCIE_REF | `0x20220` | `0x04000200` | `0x1400024f` |

No temporary platform devices or modules remained; USB SSH stayed available.
PCIE_REF's automatic power management permits the actual state to be clock
gated while the requested state is active; it must not be treated as a
guarantee that a reference clock reaches the radio.

Optional `cycle=1 snapshot=1` maps only the ADT-confirmed PCIe common-control
and port1 regions, exclusively requests those ranges, and reads selected
known registers before releasing the mappings and power domains.
The common block responded, but port1 returned **`0xffffffff`** at offsets
`0x80`, `0x88`, `0x124` and `0x128`. These are inaccessible-register results,
not a link-up status. No PCIe register writes were attempted.

The initial snapshot version logged the values and released the domains.
The source now explicitly stops with `-ENODEV` on the first all-ones result;
that change has been built, but was not rerun because the missing internal
clock/reset initialization must be resolved first. Do not repeat this test
or interpret individual port status bits as valid in the present state.

### Internal-control experiment and forced-active clocks

`force_active=1` requires `cycle=1`. While the temporary consumers hold the
domains, it saves each AUTO bit and suppresses automatic gating using the
PMGR mask used by m1n1. It polls the requested and actual states for active,
then restores AUTO before releasing consumers. On the owned board this
passed: PCIE, AUX and REF read `0x0f0002ff`, `0x000002ff` and `0x040002ff`.
All three returned to the baseline values in the table; USB SSH survived.
This verifies PMGR state, not the physical reference-clock waveform.

`prepare_port=1` additionally requires `snapshot=1 cycle=1`. This experimental
path saves each modified mask, checks each write, and restores masks in
reverse order before releasing domains. It was stopped at its first step,
both with normal domain management and with `force_active=1`: common offset
`0x90`, mask `0xff`, requested `0x28`, readback `0x00` in the forced-active
test. No later initialization steps ran. The saved mask and all three power
domain baselines were restored; no probe modules or consumers remained.

The pure forced-active test succeeded, but the internal initialization did
not. Do not bypass the readback guard or proceed to LTSSM/DMA on this evidence.

Subsequent source tracing identified a probe error: those three triples are
`apcie-config-tunables`, not `apcie-common-tunables`. The stock driver stores
the common property in host member `0x198`, which the T7000 common initializer
passes to its register writer. The configuration property is stored separately
in port member `0x1d8`. The captured J42d ADT has no common tunables. The probe
has therefore removed the three incorrectly targeted writes; its sequence now
starts with shared PHY0 setup. The old failure does not establish that an
actual common-control setting is unwritable.

The corrected module (`f004b2d0e34ea84bdc75663cd18160c5c9c7afcf5c02ec72b4640fc4ee27fe9f`)
was tested once with all four options enabled. Steps 0 through 10 passed
their individual readback checks. Step 11, common offset `0x860`, requested
`0x3` but read `0x0`, so the final step and port snapshot did not run. All
saved control masks and domain baselines were restored; USB SSH survived,
with no resident module or temporary consumer.

Further tracing connects `0x820 + port * 0x40` to two stock operations writing
`3` and `7`. Adjacent reads at `0x800` and `0x810` feed the stock energy-reporting
path. This suggests a counter-control command rather than an ordinary stored
configuration value, but its write/read semantics are not yet established.
Do not relax the readback check based only on that inference.

### Port register accessibility after the verified PHY prefix

`inspect_prefix=1` additionally requires `prepare_port=1`. It stops after
the first 11 checked internal steps and takes the requested snapshot before
restoring those steps. It neither executes nor skips past the unresolved
counter command into later initialization.

This diagnostic passed on 2026-09-08 with module SHA256
`4bbe3a11d37d1ddcd26fa2611900b252dc894cf85663f23140911391625241ee`
and `cycle=1 force_active=1 snapshot=1 prepare_port=1 inspect_prefix=1`.
Port1 returned actual register values instead of all ones:

| Port1 offset | Value |
| --- | --- |
| `0x80` | `0x00000000` |
| `0x88` | `0x0000000c` |
| `0x124` | `0x00000000` |
| `0x128` | `0x00000000` |

Core port1 controls were `0x180=0x11010101`, `0x188=0x00000101`,
`0x18c=0x00000000`, and `0x198=0x00000001` before rollback. All saved
control masks and PMGR baseline values were restored. No modules or temporary
consumers remained, and USB SSH survived. The radio remained off and link-up
bit 0 was clear; this is register accessibility, not PCI enumeration, DMA,
firmware loading or Wi-Fi connectivity.

### Root-port identification

`inspect_rc=1` requires `inspect_prefix=1`. After the port snapshot, it maps
only `0x610008000..0x610008fff` and reads the vendor/device ID and class/revision
of `00:01.0`. It stops if the vendor is not Apple or the class is not a PCI
bridge. There are no PCI configuration writes or endpoint scans.

The address follows the extracted stock driver's config mapping index 0 and
`base + (bus << 20) + (device << 15) + (function << 12) + offset`.
The owned-board test on 2026-09-08, module SHA256
`373bbae1dd4ffcd0c2d35b7a9e90782fc5e48ea4e35e5cba1ac015ce0a849764`,
passed with all prefix-test options plus `inspect_rc=1`:

- ID `0x1002106b`: vendor `106b`, device `1002`.
- Class/revision `0x06040001`: PCI bridge class `060400`, revision `01`.
- Control masks and PMGR baselines restored, no module or temporary consumer
  left behind, USB SSH available.

This identifies the host root port, not the Broadcom Wi-Fi endpoint. Endpoint
link training, enumeration, DART/DMA and firmware loading remain unverified.

### Port clock-control check

`test_refclk=1` requires `inspect_prefix=1`. It tests the stock port clock
control at common `0x188` bit 8 after the verified prefix, without executing
the unresolved counter command. Its saved mask joins the same rollback stack.
This does not measure the physical reference-clock signal.

On 2026-09-08, module
`130898cf78c7dd1d27d2d20612825162fc5c7a0af3754155940c689e10c05cd3`
passed with the previous root-port options plus `test_refclk=1`. Twelve steps
passed readback, including `0x188=0x00000001`. Port status and root-port ID
remained as above. Control masks and PMGR baselines were restored, no modules
or temporary consumers remained, and USB SSH survived. The endpoint was still
off, with LTSSM disabled.

### Combined radio power and link training

The power probe now shares its checked GPIO/PMU acquisition and rollback code
through `a1625_radio_pulse.h`. `pulse_radio=1` requires `test_refclk=1`,
`inspect_rc=1` and `force_active=1`, which in turn require the earlier options.
It performs the validated 100 ms power stage while host clocks are active.
The first combined test passed with PERST held: CLKREQ `0x76220`, port control
`0x00`, port status `0x04`. Radio and host state were restored.

`train_link=1` additionally requires `pulse_radio=1`. After verifying CLKREQ
low, it releases PERST, verifies GPIO77 `0x76203`, enables port `0x80` bit 0,
and polls port `0x88` bit 0 for at most 500 ms. It then restores LTSSM control
and reasserts PERST before the shared helper powers off the radio. The host
control masks and power domains are restored last. There are no configuration
writes, DMA setup or firmware transfers.

On 2026-09-08, module
`82186877ec2e0b6e448c48406d490d963215f39d3dc49b5ce852283fcff5eabf`
passed with all nine options enabled. Link status became `0x00000005`, with
link-up bit 0 set. LTSSM restoration, PERST reassertion, PMU/GPIO restoration
and host-domain restoration all passed. No modules or temporary consumers
remained, and USB SSH survived. This establishes a temporary PCIe link;
endpoint identification, enumeration and Wi-Fi connectivity remain pending.

### Endpoint identification after link training

`identify_endpoint=1` requires `train_link=1`. It checks the known root-port
ID, accepts only bus numbers `0` or `0x010100`, temporarily routes bus 1 when
needed, waits 100 ms, and reads only `01:00.0` identification, class/revision,
command/status and subsystem ID. It restores the root bus register before
stopping the link. BARs, bus mastering, DMA and firmware are untouched.

On 2026-09-08 module
`7544024a7fc92a0644a3c7b4e14564cb184e869eb3715f3ea9524eb29f8a466e`
passed with all ten options enabled:

| Register | Readback |
| --- | --- |
| Root bus numbers before/after | `0x00000000` |
| Endpoint vendor/device | `0x43a314e4` |
| Class/revision | `0x02800008` |
| Command/status | `0x00100000` (bus mastering disabled) |
| Subsystem vendor/device | `0x10fe106b` |

All bus, link, GPIO, PMU and host-control restoration checks passed; no modules
or temporary consumers remained, and USB SSH survived. The PCI revision `08`
must not be substituted for brcmfmac's internal chip revision: its BCM4350
firmware mapping selects different files for internal revisions 0–7 and 8+.
Reading that internal identity and integrating a DMA-capable driver remain.

### Internal chip identity through BAR0

The subsequent read-only configuration snapshot established unassigned 64-bit
BAR0/BAR1 (`0x04`, high word zero), BAR0 window `0x18003000`, and root command
and memory window zero. `identify_chip=1` requires `identify_endpoint=1` and
those exact baselines. It sizes BAR0 with decode disabled, requires 32 KiB,
assigns bus address `0xc0000000`, configures the bridge memory window, and
selects chipcommon window `0x18000000`. The ADT maps this bus range to CPU
address `0x7c0000000`. Only command bit 1 (memory decode) is enabled; bus
mastering stays disabled. A single 32-bit MMIO read obtains chipcommon ID.

Module `e1903233ce5ab637828975ae928a659ed962b29e42d97349777a9ddec389e9bc`
passed on 2026-09-08 with all eleven options enabled:

- BAR0 size masks `0xffff8004` / `0xffffffff`: size `0x8000`.
- Chipcommon ID `0x17084350`: chip `0x4350`, internal revision **8**.
- BAR, window and decode registers restored and checked before bus-number
  restoration, link stop, reset assertion and power-off.
- All host masks/domains restored, no modules or temporary consumers remained,
  and USB SSH survived.

The local brcmfmac firmware map selects `brcmfmac4350-pcie` for internal
revision 8, not `brcmfmac4350c2-pcie`. This does not validate a firmware blob,
board calibration/NVRAM or the DMA path. No firmware was transferred.

### DART read-only baseline

`inspect_dart=1` requires `test_refclk=1`. It reads only the S5L8960X command,
packed TCR, error and stream-0 TTBR registers at ADT-confirmed `0x602002000`.
It does not attach an IOMMU driver or change any DART register.

On 2026-09-08, module
`8634c5f5a9a2f34128a77905d04eefcc84c9eb92f500ebae5efa5ab324ed2fa7`
passed with the prefix and clock options, radio off. Reads were command
`0x00000f02`, TCR `0x00000000`, error `0x00000100`, and each stream-0 TTBR
(`0x40..0x4c`) `0x80ffff80`. Translation was disabled, but TTBRs were not zero.
Host state restoration passed, no modules/consumers remained, and USB SSH
survived. These values must not be adopted as a Linux DMA mapping.

### Shared power lifetime (2026-09-08)

`a1625_pcie_domains.h` now owns the bounded three-domain acquisition and
rollback. Its callback executes while the domains remain active; it must
remove any child devices and DMA clients before returning. The existing
probe uses this callback for its unchanged PHY/register observation.

Module SHA256 `04624342dc87431fcc52c739f82a6e330bd6c9bf47c295333eb1e3b48e59323f`
passed a standalone forced-active power cycle, then a separate 12-step PHY
and read-only DART observation. Both restored the original power states;
no modules or temporary consumers remained, and USB SSH stayed available.
This is a reusable bounded lifetime, not a persistent PCI host driver.

The PHY setup and reverse restoration are also shared through
`a1625_pcie_phy.h`. Its callback runs inside the outer power-domain lifetime
and must finish child teardown before returning. The refactored probe
`06bd121548f03e49dd2ebad8a2297a28d5a55caed8f90ac409e7ace9a1efacd3`
passed the 12-step PHY/read-only DART test on the owned device. Register
masks and all three power states returned to baseline; USB SSH remained live.
DART registration and PCI host registration are still pending.

### DART registration implementation

`a1625_dart_lifetime.h` creates a temporary J42d DART node using the live
AIC phandle, suppresses automatic population, verifies the translated MMIO
resource, and explicitly creates/removes the platform device within the PHY
callback. It checks that `apple-dart` bound before running an optional client
callback. Clients must be removed before that callback returns.

The default-off `probe_dart=1` stage requires `inspect_dart=1`, forced-active
power and no radio pulse. Unlike `inspect_dart`, it resets DART registers via
the real driver. It does not attach a DMA client or preserve stale TTBR/error
contents. The no-client registration/removal stage passed on the owned device
on 2026-09-08 with module SHA256
`fac026184e1431fc3aa6b94b393779679f3e7ad8661e95009f2f2edbdd52427c`.
The driver reported 4 KiB pages, four streams, no identity bypass, and
32-bit input / 36-bit output addresses. After removal, TCR remained zero
and the four inspected stream-0 TTBRs were zero; command/error remained
`0xf02` / `0x100`. No dynamic node, IOMMU device, module or temporary power
consumer remained. PHY masks and power states were restored; USB SSH stayed
available. This proves driver registration and teardown, not DMA translation.
This stage also passed after booting the verified experimental kernel with the
packed-TCR fix (build ID `920bcb30d52a917be12c322cca1f69e13ed7ff90`).

Cleanup removes the platform device before reverting the changeset. Source
review found that a changeset notifier error can leave entries applied; the
helper therefore detaches its own childless node if it remains after cleanup.
These error paths still need runtime validation.

### Stream-0 RAM mapping

The default-off `map_dart=1` option additionally requires `probe_dart=1` and
the verified fixed kernel. With the radio still off, `a1625_dart_map.h`
creates a temporary platform DMA client referencing DART stream 0. A normal
platform driver supplies DMA configuration and domain ownership. Its probe
requires a translated DMA domain and exactly `TCR=0x80`, maps one zeroed 4 KiB
page, checks both ends of its IOVA against the allocated physical page, then
unmaps and verifies that the translation is gone. Client and driver removal
precede DART, PHY and power teardown.

This passed on the owned A1625 on 2026-09-08 with module SHA256
`7ed8b29119ef22c5ef28bd2fe4366e3ed4dfcb3a4d6b9f55ee1f7482dda10a4b`.
After teardown, TCR and stream-0 TTBRs were zero; command/error were
`0x102` / `0x100`. Power baselines and USB SSH were preserved, and no test
module or IOMMU device remained. This validates software mappings and the
hardware stream-enable state, **not an endpoint DMA transfer**.

The callback path adds an unused phandle after checking for collisions. It
orders properties before node attachment because OF caches the phandle when
attaching; changeset reversal detaches before removing properties.

### Linux PCI enumeration

`scan_pci=1` requires `identify_endpoint=1` and excludes `identify_chip=1`.
Inside the verified link lifetime, `a1625_pci_scan.h` creates a temporary PCI
host and calls `pci_scan_root_bus_bridge()`. Config accesses are restricted
to root `00:01.0` and endpoint `01:00.0`. The callback rejects bus mastering,
command dword writes, MSI programming and unlisted controls. It never calls
`pci_bus_add_devices()`, which is the stage that permits driver binding in
this kernel. Scanning itself does temporarily register device objects.

The initial scan identified both devices but failed its write guard on normal
PCI capability setup. After reviewing the core code, the probe locates PM,
PCIe and L1SS capabilities using bounded lists, saves their reviewed controls
plus bridge windows, and restores them after removing the host. PM W1C status
and the self-clearing link-retrain command are not replayed during restoration.
The core's secondary-status W1C acknowledgement is allowed separately.

The revised scan passed on 2026-09-08 with tested module SHA256
`d3984ce40d51848778a1789176ab3e85da31a71dd0e6d9be6a9b271647ffd155`:
two expected devices, no rejected writes, BAR0 32 KiB and BAR2 4 MiB. Verified
capability offsets were root PM `0x40`, PCIe `0x70`, L1SS `0x150`; endpoint
PM `0x48`, PCIe `0xac`, L1SS `0x240`. Control/BAR/bus restoration passed,
then link, PERST, radio and power domains returned to baseline. No PCI device
or module remained; USB SSH stayed available. A later wording-only module
description change does not alter that tested control flow.

This stage has no host memory window assignment, PCI IOMMU mapping, MSI
domain, driver binding or endpoint DMA. Those are still required before
firmware startup and a lasting Wi-Fi interface can be claimed.

### PCI endpoint IOMMU attachment

`scan_iommu=1` requires `scan_pci=1 inspect_dart=1`, excludes the separate
`probe_dart`/`map_dart` stages, and requires the verified fixed kernel. DART
registration now encloses the radio/link/PCI lifetime. A temporary host node
provides `iommu-map = <0x100 0xa1625001 0 1>` with a full RID mask: only
endpoint `01:00.0` maps to stream 0. The host node and PCI devices are removed
before radio power-off and DART removal. The root port RID `0x8` deliberately
has no DMA mapping; the OF diagnostic for that RID is expected in this probe.

The stage passed on 2026-09-08 with module SHA256
`b1d1292d432eff01b3bb368617b0b45e6825c36a8882976a0328bb06aba7cdd9`.
The endpoint joined IOMMU group 0, had a translated DMA domain, and the real
DART TCR read exactly `0x80`. Its reserved-region list included the 4 KiB MSI
region at `0xbffff000`. Neither PCI device had a driver bound or bus mastering
enabled. All scan writes and control restoration passed. After teardown,
stream-0 TTBRs and TCR were zero, power baselines were restored, and no PCI
device, IOMMU device or module remained. USB SSH remained available.

This verifies PCI-to-IOMMU attachment and the driver's reported MSI reservation,
not endpoint DMA or interrupt delivery. The endpoint has not yet received
assigned memory resources or an MSI domain, and firmware remains unloaded.
After this test, the final result check was tightened to include any write
rejected during PCI teardown as well as during enumeration.

### MSI parent-domain allocation

`probe_msi=1` requires `test_refclk=1 force_active=1` and excludes radio pulses
and the separate DART probe. `a1625_msi.h` implements a T7000 MSI parent
domain using the current kernel MSI API. Its eight allocation slots produce
message data 8..15 at `0xbffff000`, with AIC indices 232..239. Allocation
failure releases the bitmap reservation; freeing explicitly releases parent
IRQs as well as local slots.

The radio-off probe first rejects existing AIC mappings for those indices,
then programs and verifies port offsets `0x124=0x31`, `0x128=0x00080008`.
It allocates eight individual IRQs and checks both message composition and
parent hwirqs, frees every IRQ and the domain, verifies no parent mapping
remains, and restores the port registers. It neither activates IRQs nor
generates an interrupt or programs an endpoint MSI capability.

This passed on the owned A1625 on 2026-09-08 with module SHA256
`1b98e95c5bd52535858454f0e73453be65f4f843d9836c5bc94d6b6173a6a90c`.
All eight routes, cleanup and power restoration passed; the module remained
unloaded and USB SSH stayed available. Connecting this domain to the PCI
endpoint and verifying actual interrupt delivery are still required.

### PCI MSI and memory-resource integration

`scan_msi=1` requires `scan_iommu=1`. The MSI lifetime now encloses DART,
radio/link and PCI. After its eight-slot self-check is freed, the domain is
attached directly to the PCI host bridge so the endpoint inherits it. A
bounded `pci_alloc_irq_vectors(..., 1, 1, PCI_IRQ_MSI)` checks the endpoint's
MSI address, data, enable state and parent route, then frees the vector and
checks MSI is disabled. MSI capability controls/address/data/mask (when
present) are included in restoration; pending status is not written.

This passed with module SHA256
`f0a150236f53c63911ff1c5695bfcee3409379c917e4d3771fd90d4a92316e6a`.
The live endpoint MSI capability is at `0x58`, supports 64-bit addressing,
and was programmed with low/high `0xbffff000`/`0`, data `8`, flags `0x89`.
Freeing restored flags `0x88` and cleared address/data. No IRQ handler was
requested, and endpoint DMA remained disabled. All lifetimes tore down.

`assign_memory=1` additionally requires `scan_msi=1`. It reserves the verified
J42d CPU window `0x7c0000000..0x7ffffffff`, with PCI translation offset
`0x700000000`, and uses `pci_bus_size_bridges()` / `pci_bus_assign_resources()`.
The test validates resource parents, sizes and CPU bounds without enabling
memory decoding or bus mastering. Bridge memory and upper-window controls
are added to the saved/restored set; the global resource is released after
PCI removal.

This combined stage passed with module SHA256
`16365f8194c252f1474a8d2ea1abaf896e62081df9248a6a74ff9bbdf6c4d9fc`:
BAR2 at CPU `0x7c0000000`, size `0x400000`; BAR0 at CPU `0x7c0400000`,
size `0x8000`. Config writes selected PCI bases `0xc0000000` and `0xc0400000`
respectively. The bridge window covered CPU `0x7c0000000..0x7c04fffff`.
MSI and DART checks also passed, all controls/resources were restored, and
no PCI/IOMMU/module remained. USB SSH stayed available. Firmware loading,
real interrupt delivery and endpoint DMA are the next unverified stages.
