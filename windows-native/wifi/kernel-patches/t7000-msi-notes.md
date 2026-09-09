# T7000 port 1 MSI implementation evidence

This is a static implementation note, not a tested interrupt route. Target:
owned AppleTV5,3 / J42d / T7000. The reference is its AppleTV5,3 tvOS 12.4
16M568 kernelcache, SHA256
`935841b4ef66f868ffc85a4c10604a3416e4de88ff0aa9c518e5a63eaef7fc68`.
Acquisition provenance and annotated disassembly remain in ignored artifacts.
Addresses below are virtual addresses in that image, not MMIO addresses.

## Numbering

The captured ADT supplies normal MSI address `0xbffff000`, host vector count
32, parent vector offset 224, and port 1 vector base 8 / count 8.

The stock driver's paths distinguish a message vector from a parent interrupt:

- `0xfffffff00680e2b8` and `0xfffffff00680e2d4` load host count and offset
  into members `0xd8` and `0xdc`. At `0xfffffff00680e3dc` these become
  `ApplePCIEMSIController::init` arguments. Its `0xfffffff00680d220` stores
  count at `0xc0` and first vector at `0xc4`.
- Port initialization at `0xfffffff0068112a8` / `0xfffffff0068112c0` loads
  count/base into `0x190` / `0x194`. The allocator at `0x198` is populated
  with that base/count at `0xfffffff006811320`. Allocation delegates to this
  allocator at `0xfffffff006813cfc`; the MSI controller uses the resulting
  vector directly to index its port array at `0xfffffff00680d420`.
- `addDeviceInterruptProperties` at `0xfffffff00680d300` adds controller
  member `0xc4` to the message vector. The inverse subtraction appears at
  `0xfffffff00680d5a0` in the vector release path.
- The normal `GetMessagedInterruptAddress` branch at
  `0xfffffff006810058` reads host member `0xc8`. At
  `0xfffffff006810068` it returns address low/high words, and at
  `0xfffffff00681006c` returns the caller's vector unchanged as data.

Together these support message data 8..15 and parent interrupt indices
232..239 for port 1. These are **not Linux virtual IRQ numbers**. Parent
controller identity, trigger semantics and actual interrupt delivery must be
verified before a Linux IRQ-domain mapping is treated as working.

## Port programming

T7000 setup at `0xfffffff006b742c4` selects `0x31` for eight vectors. The
write at `0xfffffff006b742d0` targets port offset `0x124`. At
`0xfffffff006b742e4`, the base is encoded as `base | (base << 16)` and
written to port offset `0x128`, giving `0x00080008` for this port.

The inspected T7000 setup does not establish an MSI address register at
offset `0x168`; the M1 driver's write there must not be copied without
T7000 evidence. A radio-off probe has now written and read back `0x31` at
`0x124` and `0x00080008` at `0x128`, then restored both to zero.

## Remaining integration

Use the verified power/PHY/link lifetime while initializing DART and the PCI
host. Reserve the MSI doorbell from normal DMA IOVA allocation and establish
whether T7000 intercepts it before DART translation. Do not enable endpoint
bus mastering until translation and the interrupt route have been reviewed.
The verified experimental kernel now runs the packed DART TCR fix. A
radio-off stream-0 RAM mapping test passed, and a separate bounded Linux PCI
scan passed. Combining the PCI clients with DART and this MSI route remains
unverified.

On 2026-09-08, the standalone MSI parent-domain probe allocated all eight
messages 8..15 against the live AIC domain. It verified composed address
`0xbffff000`, message data, and AIC parent hwirqs `0x100e8`..`0x100ef`
(IRQ type encoding plus indices 232..239). Explicit parent IRQ freeing left
no mappings, and the port and power settings were restored. Tested module
SHA256: `1b98e95c5bd52535858454f0e73453be65f4f843d9836c5bc94d6b6173a6a90c`.
This proves allocation/composition and register readback, **not interrupt
delivery**. No IRQ was activated, no endpoint MSI capability was programmed,
and the radio remained off. PCI-to-DART attachment has separately passed;
the PCI endpoint still needs this MSI domain integrated.
