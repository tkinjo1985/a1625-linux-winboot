# P0 PMGR operation plan

Source evidence: `../a1625-platform-inventory.json` and
`../a1625-adt-inventory.json`, derived from the owned J42d RAM ADT. This is
metadata evidence, not proof of current power state or successful transition.

| ID | Name in inventory | Physical register | Parents | Operation limit |
| --- | --- | --- | --- | --- |
| 0x16 | ANS | 0x20e020318 | 0, 0 | One ACTIVE request |
| 0x35 | DEBUG | 0x20e020118 | 0, 0 | One ACTIVE request, only if the first succeeds |

`pmgr_p0_ans_power_enable` requires initialized PMGR and an exact eight-byte
clock-gates list `[0x16, 0x35]`. Both device records must resolve, be nonvirtual,
have no parents, and resolve on die zero to the listed addresses. It validates
the complete plan before the first write. It does not invoke recursive mode
setting. Its attempt latch prevents reentry, including after partial failure.
The normal generic PMGR APIs are unchanged; only the experimental ANS call site
uses this fixed plan.

Each request uses the existing `pmgr_set_mode` implementation: one 32-bit
read-modify-write clears mask `0x1000030f` (AUTO_ENABLE, WAS_CLKGATED,
WAS_PWRGATED, TARGET) and sets value `0xf`. Other bits are preserved. It then
polls ACTUAL bits 7:4 for `0xf0`. `poll32` with 10000 allows at most 9999
poll reads, with a one-microsecond delay after each unsuccessful read. There
is one additional read for the timeout diagnostic. Including the RMW read,
there are at most 10001 reads and one write per listed address. These are code
limits, not a guarantee about elapsed wall time or hardware effects.

Failure returns immediately; the second address is not touched after failure
of the first request. ANS retains uncertain power state and does not restart
the controller. No power-disable operation is issued by the current P0 stop
path because DMA quiescence has not been established.

`test_pmgr_plan.py` compiles the actual plan with mocked ADT and MMIO helpers.
It covers success, missing/bad metadata, wrong addresses/parents/virtual flags,
first and second transition failures, and repeated invocation. It does not
perform or certify live power transitions. AKF MMIO ordering/count enforcement,
firmware/heap separation and individual identity remain independent gates.
