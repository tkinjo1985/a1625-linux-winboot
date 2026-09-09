# T7000 DART table experiment

Current result (2026-09-09): patches 0006 and 0007 together with
`test_dma_range=1` passed firmware initialization and actual WPA2 networking
on the owned A1625, build `3848d1b6e0bfa0c4c7abca7a9c9e8cfb33e754a2`.
See [the acceptance record](../acceptance-2026-09-09.md). The intermediate
failures below document why all three changes were retained.

The owned A1625 boots BCM4350 firmware, but its first control response times out.
DART reports status `0x80000102` at `0x3fffe000`; no MSI handler completes.
The software mapping exists at `0xbfffe000`. An opt-in DMA aperture experiment
(`test_dma_range=1`, `0x80000000..0xbfffffff`) moves the root entry from table 2
to table 0, but the same fault and timeout remain. This is not a validated fix.

In the owned tvOS 12.4 kernel, AppleS5L8960XDART's table creation code at
`0xfffffff00651cc40` masks the next table address with `0xffffff000`, ORs `0x3`,
then stores a 64-bit descriptor at a scale-8 index (`0xfffffff00651cc4c`).
The current Linux `dart_install_table()` instead ORs only `0x1`. Both software
and hardware observations motivate testing the additional bit. The bit's full
hardware semantics are not established by this disassembly.

Patch 0006 enables that bit only for `apple,t7000-dart` using the S5L hardware
implementation. It leaves leaf permissions, physical address encoding, table
allocation, and other SoCs' descriptors unchanged. This is an experimental
candidate when first introduced. Retain separate kernel and payload
artifacts and verify the live build ID before testing it.

The tvOS table allocation grouping derives from the host VM page shift divided
by 4 KiB (`0xfffffff00651b224..0xfffffff00651b248`); it does not establish that
the hardware needs all roots allocated contiguously. Root selection extracts
IOVA bits 31:30 and the next index bits 29:21. The observed code uses 64-bit
table entries, so `stt-idx-width=10` alone does not justify a 32-bit format.

Runtime of patch 0006 (build a2dbdec839767337f59e627908e393767adb0e6e)
confirmed descriptors ending in 0x3. Alone it retains error 0x80000102;
combined with the DMA aperture it changes to 0x80000104. Firmware still
fails its first control query. These tests validate neither networking nor
all DART error semantics.

Owned tvOS full-page leaf construction at 0xfffffff00651da4c..0xfffffff00651da68
combines physical bits 35:12, bit 1, validity bit 0 and direction flags; it
adds no upper subpage limit. Its bounded-range path instead inserts start
at bits 61:50 and end at bits 47:36 (0xfffffff00651db58..0xfffffff00651db5c).
Linux adds an end field at bits 51:40 even when SP_DIS is set. Patch 0007
omits these upper fields for the existing T7000 quirk, retaining SP_DIS and
read/write protection. The combined runtime test now initializes wlan0 without
the earlier DART fault and passes WPA2, DHCP, DNS, HTTPS and WLAN-addressed SSH.
This does not establish the semantics of every DART descriptor bit or fault.
