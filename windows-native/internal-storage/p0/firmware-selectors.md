# Existing ANS firmware selector evidence

Policy: HostReadOnlyExperimental. These are existing firmware-internal paths,
not operations issued by the controlled Windows/m1n1/Linux tools. Their unknown
meaning or persistence alone is not a P0 execution blocker. Firmware is not
patched, and no sending instruction is replaced by a NOP.

Analyzed capture: `artifacts/ans-offline-tests/ans-fw-live-region.bin` (10 MiB).
SHA-256 (rechecked from the local file):
`41ce142b90ce7b4fe51a4ea078dcbc6a936d19129b7f8709fcbe5a4e674a1482`.
This is the historical captured image, not attestation of a newly loaded image.
Offsets below are byte offsets in this image. The existing analysis attributes
its code to ANS1-710.500.1; that does not establish the installed tvOS version.

| Selector | Outgoing call offset | Payload | Static execution condition |
| --- | --- | --- | --- |
| 0x480 | 0x30884 | four-byte value 1 | Per selected channel, through 0x314de after successful post-probe queries |
| 0x7080 | 0xbf6c, caller 0x3077a, helper 0xbf58 | four-byte value 1 | Context bytes +0x38 and +0x628 nonzero |
| 0x7180 | 0x3080a | four-byte value 0 | Caller 0x313c0 and context bytes +0x38/+0x628 nonzero |
| 0x8580 | 0x308e8, caller 0x314e8 | four-byte value 1 | Startup reaches helper 0x308ac |
| 0xb080 | 0x30902 | four-byte value 1 | Prior 0x8580 call returns nonzero; fallback belongs to existing firmware |

Static facts from `../inspect-live-ans-image.py` sections
`prenand_outgoing_settings`, `prenand_setting_flag_origin`,
`prenand_setting_7080`, and `prenand_setting_fallback`, with interpretation
recorded in `../linux/controller-integration.md`:

- Calls enter firmware helper 0xb8c4. For these selectors, 0xb9fc loads the
  caller's payload words and 0xba00 sends them through 0x38980. This proves
  outgoing direction, rather than a caller-provided output buffer.
- The submission path uses firmware controller context and the mapped command
  interface. Related pair submission helper 0x3886c writes mapped register
  +0x100 and checks queue status at +0x18. This is not an RTKit host endpoint
  number. The exact final device/register semantics of each selector are unknown;
  a physical destination address is not inferred from the selector value.
- Fresh context initialization at 0x31006 stores halfword 1 at +0x628; +0x38
  is conditioned on Chip ID version >0x104ff. These guards are not evidence
  that a particular future run takes the branch or that no later writer exists.
- Successful 0x7080 handling caches a byte at +0x114 and invokes 0xbfa0, which
  sets bit 1 at mapped register +0x2000. Successful 0x8580/0xb080 sets +0x3c=1.
- The helper's wait at 0xba8a..0xba94 has no firmware timeout. A host timeout
  can end host waiting; it cannot prove this internal activity has stopped.

Inference and limits: the paths resemble device settings, but selector meanings,
NAND effects and persistence are not established. The listed evidence is not
concrete proof of erase/overwrite, and is not proof of their absence. Any concrete
evidence of existing-data erasure or overwrite on this route requires stopping
outside this authorization. No live observation of these selectors is claimed.
