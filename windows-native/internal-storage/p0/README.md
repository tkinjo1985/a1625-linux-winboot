# Issue #5 P0: m1n1 ANS1 smoke test

Scope: A1625 / J42d (board 0x34) / T7000 only. No Linux block-driver work.
Base: HoolockLinux/m1n1 idevice d5a10ac52a6468484854419a6c5130f1d62073eb.
Feature origin 8a8bc21922b21a909330d7dbec53e8a763e9fa34 is verified as an ancestor.

## Current status

Native Windows ARM64 build and host fault-injection tests pass. No P0 payload
has been transferred or executed on hardware. This is not P0 acceptance.

The owner has authorized HostReadOnlyExperimental for one boot session.
Unmodified firmware-internal selector transmissions are no longer an execution
blocker; see [firmware evidence](firmware-selectors.md). Firmware safety and absence
of persistent side effects are not certified. RamOnly defaults are unchanged.
`execution_authorized` is true; `preflight_verified` remains false for the concrete
host-code/identity/mapping gaps in [preflight-audit.md](preflight-audit.md).
The smoke tool rejects execution before opening a serial port until those gaps
are resolved. Do not substitute a Boolean edit for completing the preflight.

## Implemented

- Boolean rtkit_sleep result, bounded boot/power-state waits and bounded RX batches.
  AKF transport has a cumulative 128 TX-attempt / 512 RX-message limit, including
  boot's timed RX path. TX failure latches an error; system ACK failures propagate.
  A stateful outbound management/registration policy runs at the AKF RTKit
  transport boundary; see [rtkit-allowlist.md](rtkit-allowlist.md).
- ANS1 one-attempt-per-boot latch; fresh endpoint/READY state; target check before power.
  The four ANS register ranges and compatible must match the saved J42d ADT
  inventory before power enable; this is separate from the private ECID gate.
- Unified init unwind, one sleep attempt followed by explicit CPU-start-bit
  clear/readback. CPU clear is not DMA-stop proof: retain command/RTKit/AKF
  owners, mappings and power even after clear. RTKit rejects AKF buffer freeing
  and unmapping, including on send failure. No restart or recovery selector.
- ANS1_P0 build required. Only IDENTIFY and READ_USERAREA constants/sender allowed.
  Requests must use tag 0; reads use one page, flags 8, LBA 0 or 1, a non-null
  4 KiB aligned buffer representable by the 44-bit SGL.
  The C read entry point enforces at most two attempts per LBA per boot.
- IDENTIFY occurs after endpoint/command registration; geometry must report
  4096-byte blocks and at least two LBAs. Reserved proxy slot 0xf07 copies its
  saved 128-byte response; it does not send another storage command.
- AKF_UNK_80C write compiled out. CPU before/after, firmware physical/IOVA/size,
  RTKit version, endpoint and command fields are logged.
- smoke.py collects IDENTIFY, two rounds of LBA 0/1, raw 4 KiB captures and
  SHA-256 values, checks matching repeats and EFI PART, then requests shutdown.
  Its data buffer is retained for the rest of the boot, including on failure.
  It imports the proxy directly, avoiding m1n1.setup hardware side effects.
  Buffer preparation seals generic proxy and raw-write entry points for the
  rest of the boot; see [session-lock.md](session-lock.md).

## Build and verification

Requires MSYS2 UCRT64 clang/GCC, existing linker wrapper, Python, Cargo and the
Rust target aarch64-unknown-none-softfloat. The source checkout is under
third_party/HoolockLinux-m1n1-p0. Get-PinnedSources.ps1 includes that exact pin;
its existing policy refuses to overwrite existing source directories.

Run build.sh using MSYS2 bash from Windows. It verifies the revision and exact
patch, and builds build/m1n1.bin using CHAINLOADING=1 and ANS1_P0. Then run
write-manifest.py with Windows Python to record source revision, feature origin,
patch hash, Cargo lock hash, linker-wrapper hash and m1n1.bin SHA-256.

Run test_commands.py, test_unwind.py, test_rtkit_retention.py, test_rtkit_budget.py,
test_rtkit_policy.py, test_firmware_region.py, test_session_lock.py and test_mmio_identity.py
with Windows Python. They exercise
actual source function bodies with mocked transports/allocators. They cover
all 256 opcodes, invalid tag/length/LBA/flags/address, failure latching, bool
sleep results and retention regardless of CPU readback. They do not prove live
firmware behavior, all initialization failure interleavings or DMA quiescence.

## Remaining acceptance

Resolve the concrete preflight-audit gaps before any device action. Independently
verify the loaded P0 binary before selecting a proxy serial port; a supplied
hash argument alone is not remote attestation. Then collect device console,
IDENTIFY, repeated LBA hashes, EFI PART and shutdown CPU readback. Finally verify
a cold boot into normal tvOS. Host-only tests cannot certify firmware-internal
write/unlock/flush/format/auxiliary operation counts. No acceptance item requiring
hardware is currently marked passed. Linux driver work must wait for P0 acceptance.
