# P0 ANS AKF MMIO operations

The validated J42d CPU register base is 0x208040000; the V1 mailbox base is
0x208041000. The session lock excludes arbitrary host MMIO/calls after sealing.
ANS uses one retained AKF object in one initialization attempt. Other controllers
are not made targets by this ANS policy.

| CPU-base offset | Operation / bound |
| --- | --- |
| 0x1008, 0x1020 | Mailbox-enable RMW sets bit 0, once each during AKF initialization |
| 0x28 | Read before remapping; an already-set start bit rejects mapping |
| 0x10, 0x14 | IOVA low/high from the reserved and revalidated firmware tuple, once |
| 0x08, 0x0c | Physical address low/high from that tuple, once |
| 0x18, 0x1c | Firmware size low/high from that tuple, once |
| 0x20 | Endianness value 1, once |
| 0x80c | No write in the P0 build |
| 0x28 | Start RMW sets bit 4, once and only after successful mapping; before/after reads logged; failed readback latches failure |
| 0x28 | Stop RMW clears bit 4, at most twice (RTKit sleep's clear, then ANS explicit clear); before/after reads logged; final running check observes the bit only |
| 0x1008 | TX FULL-bit polling, at most 199999 reads per attempt, with existing 1-us delay and 200000 input timeout |
| 0x1010 | One 64-bit mailbox write after successful poll, at most 128 attempts; RTKit state/value policy has already approved the envelope |
| 0x1020 | RX EMPTY-bit status reads, capped at 0x1000000 per AKF object in addition to RTKit wait deadlines |
| 0x1038 | 64-bit received mailbox word; RTKit additionally caps received messages at 512 |

The attempt flag is set before mapping checks. A failed mapping cannot be
retried; CPU start requires successful mapping. Stop blocks later TX/start.
TX timeout, start-readback failure and RX-status-budget exhaustion latch the
AKF failure state. The raw sender cannot retry after that state. AKF free also
retains the ANS object. No CPU-bit observation is interpreted as DMA quiescence.

`test_akf_mmio.py` compiles actual map/start/stop/send/status/free functions
against a synthetic register model. It checks all seven remap write offsets,
order and values; rejected repeat mapping/start; already-running rejection;
stop/send budgets; failed-start and failed-mailbox latches; RX-status cap and
object retention. It does not execute MMIO on the device or certify hardware
semantics. In particular, real cold-boot layout, identity, loaded firmware hash
and hardware handshake/read/stop observations are still required.
