# Old ANS1 port investigation — 2026-09-09

## New upstream evidence

Hoolock m1n1's `idevice` branch at
`d5a10ac52a6468484854419a6c5130f1d62073eb` contains an old ANS1 reader.
This is a better starting point than reconstructing the ASP command format
solely from the external iPhone diagnostic. It is **not** a Linux block driver,
nor evidence that the owned A1625 has completed any storage acceptance test.

The exact fetched file hashes are in `upstream-research.lock.json`. The files
are retained locally in ignored `artifacts/internal-storage/m1n1-d5a10ac/`.
Use the locked revision when retrieving `src/<filename>` from the repository;
verify SHA256 before drawing further conclusions from another copy.

## A1625 platform mapping

`inspect_storage_platform.py` derives these from the live A1625 ADT's PMGR
records, ps-regs and bus ranges:

| ADT gate | Name | Physical register | Existing Linux node |
| --- | --- | --- | --- |
| 0x16 | ANS | 0x20e020318 | ps_ans / power-controller@20318 |
| 0x35 | DEBUG | 0x20e020118 | ps_debug / power-controller@20118 |

Both captured parent-ID pairs are zero. The offsets match the pinned
`arch/arm64/boot/dts/apple/t7000-pmgr.dtsi`. The ANS interrupt phandle resolves
to the captured AIC at 0x20e100000, matching the pinned T7000 AIC node.
Interrupt order roles and trigger semantics still require confirmation.

Linux sysfs contains both power-controller devices. Their `power/runtime_status`
files report `unsupported`; that is not evidence of either gate being powered
on or off. A subsequent [matched-kernel PMGR snapshot](probe/README.md)
read the two status registers once and confirmed actual/target OFF for both.
No PMGR write, ANS register access or mailbox transaction was performed.

## Firmware ownership must be established before starting ANS

The live ADT has `pre-loaded = 1` and two firmware segments. Using the upstream
`adt_segment_ranges` layout (`u64 phys, iova, remap; u32 size, unk`), they span
physical [0x87f600000, 0x880000000), with contiguous IOVA starting at zero.
These are boot-memory addresses, not NAND addresses or firmware contents.

The current `/proc/iomem` System RAM ends below this span. This rules out overlap
with the currently reported System RAM, but does not prove the firmware remains
intact, that the IOP mapping is active, or that a later boot uses the same layout.
Do not bake these per-boot addresses into a kernel patch. Validate/reserve them
at boot and retain their ownership throughout controller DMA.

Upstream obtains the preloaded region from the ADT and programs its mapping.
Its first step prefers segment-ranges over legacy region-base/region-size.
The latter are zero in this A1625 capture. A port must additionally reject
truncated, overflowing, inconsistent or overlapping segment maps.
[Source](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/akf_fw.c)

## Transport boundary

The upstream AKF implementation selects mailbox offset 0x1000 for
`iop,s5l8960x`, which matches the A1625 ANS compatible. Initialization writes
mailbox enable bits; starting the IOP and firmware remapping also write
registers. Receiving reads the FIFO, so it must be treated as a state-changing
receive operation, not an unlimited passive register dump. A preliminary
status probe should avoid the FIFO and all writes.
[Source](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/akf.c)

The C transport separates the AKF endpoint byte from the lower 56 message bits.
It negotiates protocol versions 10–12 and distinguishes application endpoint
numbering by protocol version. A1625's current version and endpoint map remain
unobserved. Do not interpret every high byte as a management opcode or reuse
the external iPhone trace as this device's handshake.
[Source](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/rtkit.c)

## Linux block-port work still required

The upstream reader uses a single command tag, a shared command buffer and a
page-address entry for one-sector reads. Its source defines identify geometry,
but the reader does not establish disk capacity before submitting requests.
It assigns a 64-bit input LBA into a 32-bit field. Its shutdown function frees
the command pointer twice. These are reasons to implement checked Linux
lifecycles rather than copy the code unchanged.
[Source](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/ans1.c)

Before a Linux port may submit a request it still needs:

- A1625-specific live handshake and reference geometry/hash evidence.
- Strictly read-only command submission with no arbitrary opcode interface.
- Validated capacity, logical block size, LBA width, range and overflow checks.
- Linux DMA allocation/synchronization and address-width checks for every
  shared buffer; ownership retained until completion or a proven controller stop.
- A bounded initialization/request state machine. Timeout cannot imply DMA
  has stopped, and cannot permit immediate buffer reuse/free.
- Kernel block-layer read-only enforcement and rejection of all write,
  discard, write-zeroes and unsupported request types.
- Safe teardown and repeated-probe behavior, with real USB/SSH health checks.

No newly fetched source has been built into or transferred to the A1625.
The discovery changes the next implementation approach; it does not satisfy
Issue #5's hardware completion conditions.
