# HostReadOnlyExperimental preflight

The owner explicitly authorized one boot session under the controlled-host
operation boundary. Backup: none. Data the owner needs to preserve: none.
DFU recovery environment: available (owner statement). This is not authorization
to execute a tvOS restore. RamOnly defaults and Issue #5 acceptance are unchanged.

Authorization and technical readiness are separate manifest fields. The old
firmware-internal-selector hold is removed. `preflight_verified=false` currently
reflects the concrete incomplete gates below, not uncertainty about selector
semantics. Do not bypass it by editing a Boolean.

## Current evidence and remaining gates

| Gate | Evidence / next required change |
| --- | --- |
| Storage operations | `ans1_exec_command` allows IDENTIFY/READ_USERAREA only. Tag 0, length 1, LBA 0/1 and flags 8; read buffer aligned and representable. `ans1_read_main_storage` enforces two attempts per LBA. Host tests do not audit all management/MMIO operations. |
| Management/endpoint allowlist | **Incomplete.** `rtkit.c` boot, endpoint start, buffer response and power switching call `iop_ops->send` directly; only routing through `rtkit_send` would miss them. Add state/value/endpoint/count validation at `rtkit_akf_send` (and account for direct `akf_send` callers), plus negative-path tests before use. Include exact command-buffer/tag registrations; do not classify all mailbox words as storage opcodes. |
| Timeout and budgets | Boot/power waits and mailbox sends have timeouts; RX batches are limited to 64. **Incomplete:** no cumulative per-session TX/RX bound, and system acknowledgement errors are sometimes only logged by `rtkit_recv`. Add bounded session accounting and propagate the first error to DEAD before another storage command. Crash record parsing is now skipped for P0, retaining raw data instead of entering its unbounded record walk. |
| MMIO and firmware mapping | **Incomplete.** `akf_init` accepts ADT register base, and `akf_map_preloaded_fw` writes the returned region directly. `akf_fw_get_region_new` forms a bounding range without proving non-overflow or a common phys/IOVA offset for all segments. Require exact current-device ADT bounds, permitted offsets/write counts, validated contiguous mapping and heap non-overlap before these writes. |
| Shared-memory lifetime | P0 unwind now retains command/RTKit/AKF owners and mappings even if CPU start bit clears. RTKit free/unmap entry points reject AKF release; uncertain buffer-reply failure retains memory. Repeated buffer requests, nonzero firmware-provided buffer addresses, zero or >1 MiB requests are rejected. Allocations are rounded before allocation to match map size. Read buffer remains allocated. **Still required:** validate actual firmware reservation against boot heap and inventory every published region on the live route. |
| Next-stage exclusion | Smoke tool performs no chainload, reboot or freeing. **Incomplete:** generic m1n1 proxy/transport still exposes memory writes, free, call and boot operations. Enforce a session lock for this experimental path before claiming next-stage reuse is prevented in code. |
| Target individual | `ans1_init` checks T7000 and board 0x34. Existing Windows boot tools have an exact private ECID gate. **Incomplete:** smoke entry point is not bound to that current-boot identity and payload verification. A COM port or command-line hash assertion is insufficient. No identity pass is claimed for this session. |
| Hashes | Exact base/origin and current patch/payload are recorded by `write-manifest.py`. Historical firmware capture hash is recorded in `firmware-selectors.md`; loaded firmware must still be hashed and compared before use. |
| Recovery | Owner declarations recorded above. Retaining RAM and requesting a manual power cycle does not guarantee preservation of data. |

## Stop behavior

Attempt graceful sleep and CPU start-bit clear/readback once. CPU clear is an
observation, not proof that DMA stopped. Do not free/unmap/reuse firmware,
command/read buffers or RTKit logs. Do not disable power as a substitute for
proving DMA stopped, or automatically chainload/warm reboot. Save observations
and report manual power cycle required. No manual cycle has been performed by
the agent, and no power cycle is certified as preserving data.

## Six-part result (no device experiment executed)

1. Host storage tests/build: offline evidence only; complete host send allowlist pending.
2. Real ANS firmware handshake: not executed.
3. Real NAND read: not executed.
4. Stop observation: host fault injection only; no live CPU or DMA-stop proof.
5. tvOS cold boot: not performed.
6. Firmware-internal persistent side effects: absence is not guaranteed.
