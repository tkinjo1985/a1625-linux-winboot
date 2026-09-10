# Issue #5 completion audit — 2026-09-09

**Incomplete; an alternative reference acquisition path is under investigation.**

Current implementation: `linux/` contains unbound AKF mailbox/RTKit patches,
a read-only block frontend, bounded read client, DMA/shared-memory owners,
firmware staging, memory reservation and PMGR state checks. ARM64 core
compile/link and the offline suite passed; test scope and source hashes are
recorded in `artifacts/ans-offline-tests/results.json`. These are not a bound
storage controller or a storage-enabled boot payload. RAM-only kernel
selftests exercise portions of this code but do not read NAND.

Latest read-only SSH check: kernel 7.2.0, uptime 22884.08 seconds. The complete
partition listing contains zram0 (786432 KiB) and ans1ramtest0 (64 KiB).
Loaded modules are ans1_ram_selftest_v2 and ans1_ram_selftest. The latter
disk is synthetic RAM, not internal storage. SSH remains reachable; this
does not substitute for stability testing during actual NAND reads.

Update: the owner confirmed that no existing environment or captures are
available. See [diagnostic acquisition](diagnostic-acquisition.md). The missing
reference evidence below still applies, but requesting access to a preexisting
environment is no longer the next step.

The same missing tvOS IORegistry/disk0 reference evidence has remained pending
since the initial issue investigation. Independent work has produced the RAM
ADT inventories, a pinned upstream-port investigation, a matching native
baseline module build and the PMGR-only hardware snapshot. These do not replace
the issue's reference acquisition and storage-driver acceptance requirements.

| Issue requirement | Current authoritative evidence | Result |
| --- | --- | --- |
| A1625 ANS/storage topology from hardware | Live RAM ADT with identity checks; checked-in sanitized inventories. No live ASP service tree, geometry or GPT reference. | Partial |
| Internal NAND enumerated in Linux | Live `/proc/partitions` contains zram0 and synthetic ans1ramtest0. No ANS controller binding. | Not achieved |
| Kernel-enforced read-only initial driver | Unbound block frontend rejects non-read requests; RAM tests exist. No NAND-backed disk registered or verified. | Partial implementation only |
| Matching tvOS/Linux GPT and sector hashes | Neither tvOS reference sectors nor Linux NAND reads acquired. | Missing |
| Repeated/random reads without corruption, hang or USB/SSH loss | SSH available after RAM tests; no NAND reads performed. | Not tested |
| Cold-boot reproducibility | No storage-enabled boot or cold-boot acceptance run. | Not tested |
| RamOnly default rejects internal storage | Restore wrapper unchanged and retains its non-zram rejection. | Preserved |
| No storage writes while write path disabled | No controller startup or NAND command executed. Firmware startup includes outgoing settings with unresolved persistence; host write rejection does not constrain them. | Startup requirement unproven |
| Reproducible kernel/DT patches and payload hashes | Probe source/build inputs are locked; no storage kernel/DT patch or boot payload exists. | Partial |

## Why automatic power-on is not the next justified hardware action

Pinned firmware analysis now establishes startup payloads to selectors
0x480, 0x7080, 0x7180, 0x8580 and fallback 0xb080. Their persistence is
unknown, and panic/mailbox shutdown does not prove DMA quiescence. See
`linux/controller-integration.md` and `inspect-live-ans-image.py` for exact
call sites and conditions. Diagnostic RAM disk preparation also remains
blocked by unaudited storage initialization and unknown installed-version
compatibility; editing the restore daemon alone does not resolve either.

The current RAM ADT records `pre-loaded=1`, `running=1`, `power-managed=1`,
and `no-shutdown=1` for the ANS nub. These are boot metadata, not a current
CPU-state register read. The PMGR snapshot reports ANS/DEBUG target and actual
OFF. That combination does not establish what the IOP will execute when power
returns, nor does it establish a quiesced storage controller.

The RAM m1n1 stage log reports `d5a10ac`, matching the upstream revision already
investigated. Its `src/main.c` calls `nvme_shutdown()` before the next stage;
this alone is not proof of a completed old-ANS1 shutdown. The PMGR initializer
repairs parent power relationships; it does not demonstrate a per-ANS quiesce
handshake. The PCIe power helper is therefore a lifecycle reference only, not
permission to copy its transition sequence to storage.

Relevant fixed sources:

- [m1n1 main](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/main.c)
- [m1n1 PMGR](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/pmgr.c)
- [m1n1 ANS1](https://github.com/HoolockLinux/m1n1/blob/d5a10ac52a6468484854419a6c5130f1d62073eb/src/ans1.c)

No power-on/CPU-start/mailbox operation has been executed to resolve this
uncertainty experimentally. No claim is made that powering on necessarily
writes NAND; the required read-only behavior is simply not established.

## Remaining reference acquisition

The owner has answered that no existing SSH/diagnostic environment or captures
are available, and the installed tvOS version is unknown. Do not repeat those
questions. A temporary diagnostic image is being investigated offline.
The next acquisition must establish the A1625 service topology, block geometry,
primary/backup GPT and bounded reference hashes, plus a justified controller
transition/stop sequence. Raw device-specific captures remain private.

Native image extraction and HFSX editing have now been demonstrated, but they
do not prove that the candidate can boot or avoids internal writes. This work has not installed a
jailbreak, restored tvOS, changed partitions or made an internal-storage write.
Do not close Issue #5 or mark the overall goal complete.
