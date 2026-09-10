# A1625 tvOS 12.4 read-only predicate analysis

Offline analysis of the AppleTV5,3 16M568 kernel, SHA256
`935841b4ef66f868ffc85a4c10604a3416e4de88ff0aa9c518e5a63eaef7fc68`.
Addresses below are unslid addresses in this exact binary, not addresses for
another build or for the running Linux kernel. No patch or device action was
performed.

## A1625 identify geometry field evidence

Additional offline inspection of `GetNANDGeometry` (same hash above) follows
the successful opcode-zero path at `0xfffffff006d9dd04`. Five u32 words from
command offsets 0x30/0x34/0x38/0x3c/0x40 are copied into object offsets
0xd8/0xdc/0xe0/0xe4/0xe8. The following diagnostic calls identify their uses:

| Command offset | Object offset | Evidence-backed meaning |
| --- | --- | --- |
| 0x30 | 0xd8 | Num LBAs; loaded at 0xfffffff006d9dd70 |
| 0x34 | 0xdc | Bytes per LBA; loaded at 0xfffffff006d9dd8c |
| 0x38 | 0xe0 | Multiplier used with bytes/LBA for preferred buffer size, not a second capacity |
| 0x3c | 0xe4 | lbaFormatted; tested as a u32 Boolean |
| 0x40 | 0xe8 | utilFormatted; tested as a u32 Boolean |

The multiply at 0xfffffff006d9ddac uses object words 0xdc and 0xe0 for
the preferred-buffer-size diagnostic. `inspect-identify-labels.py` verifies
the kernel hash and extracts the exact labels from mapped Mach-O strings;
it was run successfully against the saved AppleTV5,3 16M568 kernel.
String addresses are 0xfffffff00634098a (Num LBAs), ...09b6 (Bytes per LBA),
...09e2 (Preferred buffer size), ...0a0e (lbaFormatted), ...0a41 (utilFormatted).

With the independently identified 0x30-byte command header, these correspond
to response-body offsets 0/4/8/12/16. The pinned m1n1 structure leaves body
offsets 8..15 unknown; do not treat its unknown area as padding or omit the
formatted-state check in an A1625 decoder. The separate word at command 0x44
is polled until zero before consuming geometry; its precise semantics remain
unknown. No actual geometry values, live response, transport compatibility,
firmware write behavior or reference sectors are established by this analysis.

## Identify request initialization

The request allocator at 0xfffffff006d9b188 obtains the command pointer through
0xfffffff006d9bbfc, then calls stub 0xfffffff006da8cb4 with length 0x80.
That stub loads pointer 0xfffffff006fd98e8, which resolves to
0xfffffff0070996c0 (`_bzero` / `___bzero` in this kernel's symbol table).
`inspect-identify-labels.py` now verifies and reports this resolution.
GetNANDGeometry then writes opcode zero at 0xfffffff006d9dc20.
ExecuteCommand writes the tag at command byte 1 (0xfffffff006d9c438), and
constructs doorbell 0xff003 with tag bits 11:4 (0xfffffff006d9c454..460).
This supports a cleared 128-byte tag-zero identify request for the draft.
The live firmware version and request compatibility remain unverified.

## Verified predicate

Function `0xfffffff006d9d1f8` identifies itself through its diagnostic string as
`ASPIsReadOnly`. Its instructions implement:

1. Initialize a local 32-bit argument value to zero.
2. Derive a default predicate from object halfword at offset 0x158: true when
   bit 3 is clear.
3. Call `PE_parse_boot_argn("nand-readonly", &value, 4)`.
4. If the argument exists, replace the default with `value != 0`.
5. Return the predicate (logging branches do not change it).

The call at `0xfffffff006d9d22c` goes through stub `0xfffffff006da8924`.
Its pointer at `0xfffffff006fd9598` contains `0xfffffff0075b0540`, which the
kernel symbol table identifies as `_PE_parse_boot_argn`. This verifies the
interpretation of the call rather than inferring it only from a string.

## RAM-root exception in callers

Function `0xfffffff006d9d370` identifies itself as `ASPIsRootDeviceRamdisk`.
It reads `rd`, falling back to `rootdev`, into a 32-byte buffer and checks
the first three bytes for `md0`. A match sets object halfword bit 4 at 0x158
and returns true. It does not require string termination after those bytes.

Four direct BL references to ASPIsReadOnly were found in the prelinked code:

| Call address | Observed control flow |
| --- | --- |
| 0xfffffff006da0b38 | Read-only result selects additional helper calls; those helpers are not yet fully interpreted. |
| 0xfffffff006da0dc8 | Read-only result selects additional helper calls; those helpers are not yet fully interpreted. |
| 0xfffffff006da2118 | Preceding call to ASPIsRootDeviceRamdisk at 0xfffffff006da210c bypasses the read-only test when true. Otherwise true read-only branches to 0xfffffff006da227c. |
| 0xfffffff006da3b88 | Preceding call to ASPIsRootDeviceRamdisk at 0xfffffff006da3b7c bypasses the read-only test when true. Otherwise true read-only selects return value 0xe00002c4 and skips to 0xfffffff006da3c48. |

These two exceptions prove that `rd=md0 nand-readonly=1` alone is **not** a
universal command-submission guard. They do not by themselves prove that an
unmodified diagnostic boot necessarily writes NAND; the functions and all
command paths still need classification. No argument-only boot recipe is
approved by these findings.

The binary also contains `nand-enable-reformat` and a message saying NAND
formatting is disabled when it is absent. That observation is only a string
finding at present; it is not a substitute for inspecting the format command
gate or controller firmware behavior.

## Next analysis needed

### Caller classification from embedded diagnostic names

Additional inspection identified the two exception-bearing methods:

- The method containing call `0xfffffff006da2118` logs
  `ASPNVRAM::%s - Entry` with the method name `sync` at string address
  `0xfffffff006341202`. Nearby strings include “Actual sync!”, restoring a
  shadow, and registering the NAND NVRAM service. This is not a required
  reference-sector read operation. Its complete startup/sync lifecycle has
  not been audited.
- Function `0xfffffff006da3b10`, containing call `0xfffffff006da3b88`, logs
  `ASPDiagnostic::%s - Entry` with method name `writeRegion` at
  `0xfffffff006341935`. This identifies an actual write-oriented diagnostic
  path that the RAM-root exception permits past its read-only gate.

The earlier caller around `0xfffffff006da0b38` is adjacent to the diagnostic
“LBA FORMAT promoted to UTIL FORMAT”. This is further evidence against using
the read-only predicate as a complete submission policy; the formatting path
and its enabling conditions still need full control-flow analysis.

The string “NAND is not writable!” is referenced near `0xfffffff006d99fb0`.
The surrounding code continues through several initialization helpers after
printing it. It must **not** be described as a proven per-write rejection
gate based only on the log wording.

An ASPStorage `ExecuteCommand` implementation was located around
`0xfffffff006d9c300`: it indexes a request table from its second argument and
enters work-loop/state handling. The entry, command layout, send operation and
all callers have not yet been fully mapped. No opcode allowlist has been
implemented from this partial evidence.

### Verified request-to-send path

Further instruction inspection established the following path for the
diagnostic write request in this exact kernel:

1. `ASPDiagnostic::writeRegion` places opcode `0x44` or `0x47` at the first
   byte of its stack command (0xfffffff006da3bb0 / 0xfffffff006da3bd8), then
   calls wrapper `0xfffffff006d9cdb8` at 0xfffffff006da3c20.
2. The wrapper receives the command pointer in x1, allocates a request, and
   copies exactly 128 bytes to the request's shared buffer at
   0xfffffff006d9ce58–0xfffffff006d9ce74. It uses byte 2 bit 3 and the 32-bit
   field at offset 8 for request preparation. It separately reads byte 0 for
   its opcode diagnostic.
3. Helper `0xfffffff006d9bbfc` looks up the request at
   `this + 0x170 + 8 * tag` and returns its buffer pointer from request+0xc8.
   Its tag check compares against 0x21; this is not evidence that 33 tags
   should be copied into a Linux implementation.
4. Wrapper call 0xfffffff006d9cf00 invokes `ExecuteCommand` at
   **0xfffffff006d9c2e0** with the tag in w1, not the opcode.
5. ExecuteCommand obtains that same buffer in x22, updates its tag byte at
   offset 1, invokes a memory-related virtual method, builds a message from
   `0x000ff003` with tag bits 11:4, and invokes a virtual send at
   0xfffffff006d9c494. The send failure diagnostic names `sendMessage()`.
6. The wrapper checks the ExecuteCommand return value, copies the 128-byte
   command back, and calls cleanup helper `0xfffffff006d9c600` at
   0xfffffff006d9cf38. Other callers' cleanup behavior is not yet proven.

The observed first-byte opcode and byte-one tag agree with the pinned m1n1
`ans1_cmd_hdr` layout. Its names for 0x44/0x47 are write-control-bits and
write-syscfg, respectively; these names are supporting upstream evidence,
not independently acquired A1625 storage contents. The upstream also warns
that its write-unlock command does not gate NVRAM/PANICLOG writes. Simply
omitting a write-unlock command would therefore not establish the required
host-command policy.

Any future filter must inspect the buffer's opcode, not confuse the request
tag argument with an opcode. Inserting a failure after the lock/accounting
operations could strand requests; entry filtering and each caller's cleanup
must be verified before building a bootable patch. Coverage of this one
diagnostic path does not prove that all commands pass through ExecuteCommand.

### Direct caller inventory and failure handling

`inspect-asp-callers.py` checks the exact kernel hash, reads the Mach-O segment
table and scans both main and prelinked executable segments for direct B/BL
targets. It finds 29 BL sites and zero literal 64-bit pointer byte matches.
The full result is `artifacts/diagnostic-ramdisk-research/asp-direct-callers.json`.
This does not rule out computed references, indirect calls or alternate sends.

Additional inspected cases:

- Caller 0xfffffff006d97c3c sets opcode 0x51, checks the return status and
  completion status, and reaches request cleanup at 0xfffffff006d97c6c.
  The meaning and necessity of opcode 0x51 are not yet established.
- Caller 0xfffffff006d9c268 sets opcode 0x14, checks the return/completion
  status, and reaches cleanup at 0xfffffff006d9c29c. Its semantic effect
  is not inferred merely from proximity to other command values.
- Caller 0xfffffff006d9dc38 explicitly sets opcode zero, matching the pinned
  upstream identify command. On successful submission/completion it checks
  the response word at offset 0x44. If nonzero, it delays with argument 0x32
  and resubmits at 0xfffffff006d9dc90. This local loop has no visible counter
  limit. Errors branch through a diagnostic and cleanup at 0xfffffff006d9dcd8.
  The diagnostic helper's failure semantics remain unverified.

No blanket early-return patch has been applied. It would prevent identify
and could break initialization; allowing unknown initialization commands
would also defeat a read-only guarantee. The remaining 24 direct sites,
indirect-path coverage, command semantics and full cleanup behavior are not
yet audited (the generic wrapper was inspected separately above).

### Command-byte inventory across all direct sites

All 29 sites now have saved 88-instruction disassembly windows in
`artifacts/diagnostic-ramdisk-research/asp-call-sites/`. The manually inspected
byte assignments are recorded in `tvos-command-sites.json`. This is not an
allowlist: a nearby assignment does not prove every path or subcommand safe.

The two format callers explicitly set 0x16 and 0x15, and the write-unlock
caller sets 0x19, consistent with the pinned m1n1 definitions. Seven sites
set 0x80 and six set 0x81; these need subcommand-level classification rather
than unconditional admission. The selector-driven caller at
0xfffffff006d9f19c uses 0x79 when its selector is zero and 0x76 when one;
other selectors branch away before submission.

Two sites remain without a fixed opcode classification: the generic
caller-supplied wrapper and the larger I/O path at 0xfffffff006d98864. The
latter includes scatter/gather setup and several earlier control-flow paths;
a short backward instruction window is insufficient to establish its opcode.
The inventory advances command classification, but does not complete the
failure-path audit described above.

### Normal block I/O classification

The larger path at 0xfffffff006d98864 is now identified by its embedded
method name as `ASPBlockStorage::asyncReadWrite`. The command buffer returned
by helper 0xfffffff006d9bbfc is held in x23. A virtual method called at
0xfffffff006d98350 returns a direction value: equality to 2 selects opcode
0x11 at 0xfffffff006d9837c–0xfffffff006d98380; the other branch selects 0x10
at 0xfffffff006d983bc–0xfffffff006d983c0. The branch log strings explicitly
say `WRITE cmd` and `READ cmd`, respectively. This is A1625 binary evidence,
not only correspondence with the upstream opcode table.

The code then places two 32-bit values at command offsets 4 and 8 and builds
scatter/gather entries from offset 0x30, consistent with the upstream header
layout. Complete range/direction validation in the surrounding IOKit layers
has not been reconstructed.

A nonzero ExecuteCommand return branches to 0xfffffff006d9891c. It calls a
diagnostic helper at 0xfffffff006d98950, performs a virtual request operation
at 0xfffffff006d9896c, then calls cleanup 0xfffffff006d9c600 at
0xfffffff006d9897c. It ultimately selects return value 0xe00002bc.
The diagnostic helper's semantics remain unknown, so this sequence is not
yet proof that a newly injected rejection returns cleanly without a panic.

The fixed command classification now covers 28 direct sites. The remaining
site is the generic caller-provided command wrapper, which is inherently
variable. This does not reduce the remaining subcommand and failure-path
verification requirements.

### Failure diagnostic resolved

The stub at 0xfffffff006da8dbc loads its target from
0xfffffff006fd99c0. That pointer is 0xfffffff0070deaac, identified as `_printf`
by the kernel symbol table. Thus the previously unresolved diagnostic call
on the inspected error paths is printing, not a direct panic call. This
resolves that specific uncertainty; it does not prove that all surrounding
virtual operations or cleanup are safe under an injected error.

### Configuration request selectors

All 13 direct 0x80/0x81 sites write a selector at command offset 0x38:

| Send site suffix (prefix 0xfffffff006) | Opcode | Selector | Other observed fields |
| --- | --- | --- | --- |
| d9a3c4 | 0x81 | 0x10 | Page-address value and length 4 at 0x30/0x34 |
| d9aaf4 | 0x80 | 0xae | No further field classified in this window |
| d9b020 | 0x80 | 0x26 | Variable word at 0x44 |
| d9e02c | 0x80 | 4 | Variable word at 0x44 |
| d9e160 | 0x80 | 7 | No further field classified in this window |
| d9e54c | 0x80 | 0x22 | Variable word at 0x44 |
| d9e678 | 0x81 | 0xe | Word 3 at 0x3c; variable word at 0x44 |
| d9e834 | 0x80 | 0x97 | Variable word at 0x44 |
| d9efbc | 0x81 | 0xc | Page-address value and variable length at 0x30/0x34 |
| d9f3f0 | 0x81 | 0xa | Page-address value and length 0x70 at 0x30/0x34 |
| d9fc58 | 0x81 | 0xb | Page-address value and length 0x60 at 0x30/0x34 |
| da110c | 0x80 | 6 | Variable words at 0x48 and 0x4c |
| da14b4 | 0x81 | 9 | Word 1 at 0x3c; page-address value and length 0x1000 at 0x30/0x34 |

The combined selector/word constants for d9e678 and da14b4 were verified
directly at 0xfffffff006342d30 and 0xfffffff006342d38, respectively.
These are observed fields, not approved values. Names, persistence effects,
buffer direction, and necessity during initialization still need validation.
In particular, classifying 0x80 or 0x81 globally as read-only is unsupported.

### Configuration names and two verified boot-argument gates

Embedded method/log strings near the configuration paths identify:

| Opcode / selector | Observed name or associated diagnostic |
| --- | --- |
| 0x81 / 0x10 | AppleNANDFailureData; NAND initialization diagnostics |
| 0x80 / 0xae | nand-fragmentation query (verified result consumer; see below) |
| 0x80 / 4 | SetNandPowerGate; NAND power-gate interval |
| 0x80 / 7 | SetNandQual; NAND qualification mode |
| 0x80 / 0x22 | SetNandIOLog; enable-IO-log |
| 0x81 / 0xe | SetNandTLCSim; NAND TLC read delay |
| 0x80 / 0x97 | SetBDRFactor; BDR accelerating factor |
| 0x81 / 0xc | GetMarketingName |
| 0x81 / 0xa | Nearby result fields include caus and cau-bits; full operation name unresolved |
| 0x81 / 0xb | Nearby result fields include tRC and tREA; full operation name unresolved |
| 0x80 / 6 | ASPSendTime; calendar and wall time |
| 0x81 / 9 | ASPGetTemperature; temperature sensor |

The 0x80/0x26 operation remains unnamed. These labels are not persistence or
read-only guarantees. The nearby ASPNotifyDeviceReady/kASPWriteReady strings
previously associated with 0xae did not establish its operation name.

`SetNandQual` begins at 0xfffffff006d9e0a4. The parse call at
0xfffffff006d9e0cc and condition at 0xfffffff006d9e0d4–0xfffffff006d9e0dc
skip allocation/submission unless the `nand-qual` argument both exists and
has a nonzero value. The no-request path returns zero.

`SetNandTLCSim` begins at 0xfffffff006d9e5c0. After parsing
`nand-tlc-read-delay` at 0xfffffff006d9e5e8, absence branches at
0xfffffff006d9e5ec to the exit path before request allocation. Thus these two
test-related requests can be avoided by omitting their arguments; they need
not be admitted to an eventual command allowlist to support the reference
acquisition. No final boot argument string or bootable patch has been issued.

### Fragmentation query correction and selector 0x26

Function 0xfffffff006d9aa84 sends 0x80/0xae. On successful submission it copies
the returned command word at offset 0x44 to the pointer supplied as argument
two (instructions 0xfffffff006d9ab00–0xfffffff006d9ab04). Its direct caller at
0xfffffff006d9a7c4 first checks a provider property named `nand-fragmentation`;
after success it publishes the returned value under the same property name,
with width 32. This is stronger evidence than neighboring log strings and
identifies a fragmentation query, not an initialization-complete notification.
It still does not independently prove the firmware implementation has no
persistent side effects.

Function 0xfffffff006d9afac sends 0x80/0x26, placing its second argument at
command offset 0x44. Two direct callers were found: 0xfffffff006d99ffc sends
3 conditionally during initialization; 0xfffffff006d9af54 chooses 0, 1 or 3
based on object state and a virtual boolean result, then saves an object
pointer at this+0x308. The selector's semantic name and persistence effect
remain unresolved. Do not treat these observed values as approved settings.

### Selector 0x26 notification source

The caller beginning at 0xfffffff006d9aea8 is a notification-style callback.
It compares its saved event argument against 0xe0024100 at
0xfffffff006d9aecc–0xfffffff006d9aed8. For a matching event it reads an object
property whose name at 0xfffffff00633e22c is **RestrictedMode**. It compares
the resulting object against the previously saved pointer at this+0x308,
and only a changed value reaches the earlier 0/1/3 selection and the
0x80/0x26 sender.

This identifies the host-side trigger as RestrictedMode changes. It does
not establish the firmware selector's full meaning, whether any NAND
metadata changes result, or whether a diagnostic boot requires it. The
separate initialization caller sending 3 remains relevant. No command
permission has been inferred from the property name.

Identify the two exception-bearing operations and all storage command
submission paths, then determine whether an explicitly read-only temporary
kernel can reject writes, erase/format and utility commands at their shared
submission boundary. Any patch must retain identification/read/handshake
operations and be verified against this exact A1625 build. Firmware-internal
startup behavior remains a separate question. No guessed offsets or existing
SSHRD generic kernel patch should be used as proof of read-only behavior.
