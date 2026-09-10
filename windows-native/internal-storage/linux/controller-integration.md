# Initial controller integration decision

## RTKit callback adapter

`ans1_rtkit_client.c` connects process-context RTKit RX/crash callbacks to
an initialized read client and delegates shared buffers to `ans1_shmem`.
The bridge exists before RTKit initialization; reader attachment follows
endpoint discovery. A latched pre-attachment crash rejects attachment,
and an attached crash aborts the reader. Subsequent RX is ignored and
new shared-buffer setup fails. Destroy only detaches the descriptor,
preserving the shared-memory owner's publication rules.

A mutex serializes attachment, detachment, RX and crash handling. Stop and
drain reads before detachment, keep the bridge alive through RTKit callback
drain, and retain the owner/device mappings after publication. There is no
hardware binding or startup path yet. Actual-source mock tests cover early
and attached crashes, RX routing, duplicate attachment and shared-buffer
delegation. The full offline suite passes.

## Startup includes outgoing setting payloads

The +0x628 condition is enabled during fresh context initialization:
0x30fc8 checks context +4, 0x30fd0 sets r5=1, and 0x31006 stores that
halfword at +0x628 (byte +0x628=1, +0x629=0). The separate +0x38 guard
comes from the Chip ID version comparison (>0x104ff). Consequently the
conditional settings cannot be dismissed as retained-runtime-only paths.
This proves their initial guard values, not the absence of later writers.
The inspector records the source of both conditions and was rerun.

The earlier 0x3077a call, conditional on context bytes +0x38 and +0x628,
enters 0xbf58 with arguments (context, 1, 0). It sends selector 0x7080
with four-byte value 1 through 0xb8c4. On success it caches the value at
context +0x114 and calls 0xbfa0, which sets bit 1 in mapped register
+0x2000 by read-modify-write. Failure skips that register change and
returns false. Both helper bodies are now included in the pinned inspector.
This identifies a paired device-setting/controller-register transition;
its semantics and persistence remain unverified, so it is not executed.

The following call at 0x314e8 enters 0x308ac and sends four-byte value 1
to selector 0x8580 through 0xb8c4. If that returns nonzero, it retries with
selector 0xb080 (0x8580 + 0x2b00), also with value 1. Either success sets
context +0x3c to 1; both failures set it to 2 for manufacturer byte 0x98
or to 0 otherwise. The inspector now reproduces this entire fallback body.
Neither these feature meanings nor the earlier 0x480 meaning are resolved.
These newly identified outgoing operations remain part of the startup
audit; a host-level read-only disk flag cannot constrain them.

The path at 0x314de calls 0x3084c after successful post-probe queries.
For every selected channel, 0x30884 calls helper 0xb8c4 with selector
0x480 and a four-byte caller buffer containing 1. Separately, 0x3080a
conditionally calls the same helper with selector 0x7180 and value 0.
These are **outgoing payloads**, not output buffers: for these selectors,
0xb9fc loads each caller word and 0xba00 sends it through 0x38980.
The helper has trace label `SF<`, waits for context +0x108 to clear, and
reads one status byte. No timeout is present in that synchronous wait.

The inspector reproduces both call sites and the entire helper body.
The feature meanings and whether they persist remain unresolved; no
claim is made that they program NAND. Nevertheless, startup contains
more than read queries, so prohibiting host block writes alone is not
adequate evidence for a read-only startup. No setting was sent on hardware.

## Post-probe comparison and queries

The 0xdffc helper called at 0x312ce compares six bytes at context +0x1c
and sixteen bytes at +0x28 using the already traced byte comparator 0x16e8.
It returns zero only when both match. There is no peripheral access in this
helper; mismatch causes the caller to store status 7 at aggregate +0x264.
This removes one unknown operation from the PreNand startup path.

The later path still calls query helper 0xc174 with selector 0x85 (10 bytes,
conditional on context +0x38), 0xa180, 0xa080, and 0xa181 (16 bytes each).
A loop additionally queries u16((index << 8) + 0x82), requesting 16 bytes
per selected parameter +0x38 entry. Their arguments and bounds are recorded,
but their device semantics are not established merely by the destination
buffers. The pinned inspector emits the comparison and subsequent query
windows and ran successfully. No hardware query or startup occurred.

## Startup parameter transfer remains a hardware gate

The 0xda0c call to transfer-mode helper 0x3876c passes zero for all five
arguments after the context. If cached context +0xe0 (word) and +0xe4
(byte) are already zero, it returns without submitting a pair. Otherwise
it clears those fields and submits [0, 0x200000] twice via 0x3886c before
returning. The later additional-buffer branches in this helper require a
nonzero third argument and are therefore not reached by this call. This
narrows the startup path without assigning an unverified hardware meaning
to 0x200000. The pinned inspector now emits the full helper code and this
caller-specific result. Public searches did not supply a matching primary
specification for the PPN command words; unrelated NAND opcodes must not
be used as evidence of their semantics.

The post-transfer tail is now traced through its return. Its embedded label
is `anc_validate_device_parameters`. Validation failures log the channel
and return 3 through 0xd84c; successful validation stores the quotient of
parameter +0x34 and context +0x60 at context +0x64, then returns 0 through
the same epilogue. Failures from the transfer-bracketing helpers instead
reach the previously identified panic dispatcher at 0x27d6. These are
distinct failure paths, not an interchangeable recoverable error.
The inspector emits the remaining validation and return windows and was
rerun against the pinned capture. Its earlier validation-window endpoint
was corrected from 0xdc5c to 0xdc5e to avoid splitting a Thumb-2 instruction.
This closes the post-transfer control-flow gap; the transfer semantics and
other PreNand initialization calls remain separate startup safety gaps.

The next `anc_reprobe` phase (0xd9aa..0xdaee) is bracketed by `RDP<`
and `>RDP` trace labels. It submits additional control words through
0x38980, takes an indexed pair from the table addressed by literal 0xdb44,
and calls 0x3886c twice (0xda7e and 0xda8a). That helper writes both input
words to mapped register +0x100, with a queue count at context +0xa8.
It waits while the count is >=64 and refreshes it from mapped +0x18 bits
8..14. The caller also waits for context +0x108 to clear, yielding through
0x3b574, with no timeout in that loop. These waits are not host timeouts.

Subsequent checks require `ppn->caus_per_channel` in 1..64 and
`ppn->cau_bits` in 1..7. This supplies parameter-validation context; the
trace label and checks alone do not establish the command semantics or
exclude persistent effects. The inspector now reproduces the bounded
windows, literals, stores, and waits against the pinned capture. It ran
successfully. No startup or NAND command was executed on hardware.

## Host-owned RTKit buffers (compile-only)

`ans1_shmem.c` now supplies a bounded owner for host-allocated RTKit system
buffers. It retains independent allocation records before returning from
setup, so descriptor clearing, send failure, panic, and RTKit teardown cannot
free possibly published DMA memory. Detach only clears the descriptor's
private pointer. Owner destruction returns EBUSY after successful setup.
Four lifetime allocations of at most 1 MiB each are host policy limits, not
inferred firmware requirements. Firmware-provided IOVAs are rejected until
a mapping plan is verified. Failed allocations leave the slot available.

The owner is compiled into the unbound core; controller callback adapters,
device/IOMMU lifetime retention, and verified post-publication teardown are
still required. No hardware start or physical buffer transfer occurred.
Actual-source mock tests verify failure unwind, limits, zeroed buffers, and
retention after descriptor destruction. The complete offline suite and
ARM64 core compile/link pass. This does not establish firmware startup
safety or satisfy issue #5's live storage-read requirements.

## Pristine iBoot comparison: complete text match

The ANS1 opt-in RTKit initializer now requires both shmem_setup and
shmem_destroy before allocation or mailbox acquisition. Without them,
generic RTKit teardown would directly free its coherent system buffers
after only stopping host work, which is insufficient for this device's
unverified DMA quiescence. The generated-preflight test covers all eight
mode/callback combinations and NULL ops; default-mode behavior remains.
Full offline tests and AArch64 rtkit.o compilation pass. This guard
requires an ownership implementation; it does not supply one or prove
that arbitrary callbacks are safe. Controller integration must retain
published allocations independently when RTKit clears its descriptors.

Panic idle helper 0x2fa0 is now fully bounded. It checks byte +1 of
0xd0484; zero selects DSB/WFI/return. Nonzero temporarily clears bit 2
of CP15 c1,c0,0, executes DSB/WFI and restores the register before
returning. There is no peripheral store or nested call in this helper.
Therefore the surrounding panic loop establishes CPU waiting, not DMA
quiescence. The earlier report function 0x9864 also contains a nested
panic-count guard that loops at 0x98a2 when the count is already >=5.
The inspector emits these windows. A panic notification remains
insufficient evidence to free published shared buffers or restart ANS.

The query's special error handler 0xb83c is now identified by the
embedded message `%s:%d assert failed:GEB panic`. It calls 0x27d6,
which disables interrupts, calls 0x9864, then calls 0x2794 with 4.
The latter stores 4 at 0x60200 and enters 0x9110; that function disables
interrupts and loops calling 0x2fa0 without returning. This is not a
normal query-error return or a demonstrated recoverable stop. The
inspector emits the entire bounded chain; effects of 0x9864/0x2fa0
and DMA quiescence remain separate questions. No panic was induced on
the device.

Helper 0xc174 selects its special DMA path only for selector 0x380
with size >0x100, so the traced version selectors take its ordinary
response path. At 0xc32c it reads one status byte, then at 0xc336
reads the requested payload through 0xb764 and clears context +0x108.
The status is decoded at 0xb7ec; bytes 0x50/0x51 map to result 5,
which diverts the caller to 0xb83c instead of its normal return.
The inspector emits the complete query body and status decoder. This
resolves response handling, not the effects of submitted selectors or
the exceptional handler. No live query was issued.

After the special invalid versions, anc_reprobe rejects a version above
0x1ffff with return 4, using literal 0x104ff plus 0xfb00. It sets
context byte +0x38 according to version >0x104ff, then calls helper
0xc174 with selector 0xc080 and size 1. A successful result equal to
1 enables further selectors 0xc280/0xc180/0xc380. Later selector
0x9080 requests 16 bytes into context +0x28, logged as PPN FW version.
The inspector records this window and the helper entry. That helper
has state and size checks followed by command submission, so its
complete effects still require analysis; these calls are not assumed
read-only merely from their result buffers or log labels.

The second anc_reprobe phase sends address word 0x12000030 and reads
six bytes into context +0x22, logged as Manufacturer ID. It compares
the first three Chip ID bytes with exactly `PPN` using byte-compare
helper 0x16e8; mismatch logs no NAND detected and returns 5. It then
forms a 24-bit version from Chip ID offsets +0x1f/+0x20/+0x21 in
big-endian byte order. Value 0xffffff logs missing/corrupted firmware
and returns 1; 0xfefefe takes a separate error branch. The inspector
records these checks and bounded windows. These are firmware checks,
not live device responses or proof of safe subsequent operations.

Function 0xd700 is identified by its log strings as anc_reprobe.
Its initial sequence uses the previously traced 0x38980 submit helper,
then calls 0xb764 to read six bytes into context +0x1c and logs them
as Chip ID. Helper 0xb764 polls mapped +0x24 mask 0x7f00, reads
32-bit words at +0x1c0 and copies the requested bytes into RAM. The
inspector emits both bodies for this phase and records the log string,
command words and result offsets. This identifies a chip-ID read phase,
not the full behavior of anc_reprobe; later commands remain unaudited.
No chip-ID request was sent to the live device.

The conditional call to 0x38980 at 0xd4c8 is not established as a stop
operation. It waits while context +0xac is >=0x80, refreshing that
count from mapped +0x1c bits 8..15 and optionally yielding. With room
and context byte +0xb1 zero, it writes its second argument to mapped
+0x140 and increments the count. Main initialization supplies zero.
The device meaning of that value remains unresolved. The inspector now
emits the full function and records this path; it must not be used as
a recovery or quiescence primitive on this evidence. Captured contexts
have different nonzero counts, which do not determine post-reset state.

ANC initialization has three unbounded register polls: after writing
0x10 to +0x2004 it waits for bit 4 to clear at 0xd426; after writing
0x80 there it waits for bit 7 at 0xd442; after writing 4 to +0x1004 it
waits for bit 2 at 0xd45e. No counter, deadline or yielding call exists
inside those loops. Later it copies 61 words from template 0x3fdbc to
mapped offset 0x3000, substituting configuration values for words whose
masked high bits equal 0x38000000 (low16 selector bounded to 0..5),
then writes zero at +0x2000 before returning. The inspector extracts
the template and full tail window. A host communication timeout cannot
by itself stop firmware spinning in these loops; recovery/quiescence
must still be established separately. No firmware was started.

Helper 0xbcf8 is now fully bounded through its assertion paths. It
writes selected context +0xc mapped-region offsets 0x201c=0x0f080f0f,
0x2018=0xf0f, 0x2014=0xe08, 0x2010=0x104040, 0x2020=0,
0x202c=1 and 0x2024=0, checking the mapping flag before each access.
Its embedded assertion identifies source src/drivers/apple/anc/anc.c
and expression (anc->handle)->rdi_mapped. This supplies firmware-source
evidence identifying the ANC driver behind this helper; it does not
give register semantics or establish write-free startup. The inspector
extracts the strings/constants and the full helper window. No live
device operation was performed.

Initialization reaches two further mapped regions through context +0xc.
The assignment at 0x31028..0x3103a loads pointer 0xd0658 from 0x3fd20
for context zero and 0xd066c from 0x3fd24 for context one. Main startup
sets these to physical 0x208800000 and 0x208900000, each size 0x100000.
After writing shared-region +4=2, 0xd34c onward writes the selected
region +4=1, +8=0xffffffff, +0x14=0x80040 and +0x10=0x20. It invokes
object 0x4c2e8's table slots +0x14/+0x1c, passing Thumb 0x38d31 to the
latter, then writes +0xc=0x5f983. Later calls include 0xd064 and 0xbcf8;
the window also contains writes at +0x2038 and +0x2004. The inspector
records these literals and the bounded window. These are verified
register accesses in the firmware, not proof of NAND program/erase or
of absence of such effects. No live register writes were made.

Both initial register groups in 0xd170 are now bounded. Context zero
uses offsets 0x40/44/48/4c=2, 0x50=0xff00, 0x58=0xff00ff and
0x54=5; context one uses the same sequence shifted by 0x28. The
following SoC helper 0xa530 copies the _COS parameter at 0x4800c.
For 0x7000 (also 0x7001), context zero additionally writes 0x60=6,
0x64=3 and context one writes 0x88=6, 0x8c=3. The common final store
is at 0xd328. These are offsets within the previously resolved
0x208081000 region. The inspector records both groups and emits the
SoC helper and branch windows. This is an initial subset of the
function, not a complete programming sequence or permission to run it;
the register semantics and persistent effects remain unresolved.

The mapped initialization descriptor is now linked to main startup.
Literal 0x31328 supplies context base 0xd06bc; the initialization loop
uses two contexts separated by 0x744. At 0x3103c..0x3103e the literal
0x31344 (0xd0680) is stored into each context +0x10. This is the same
descriptor initialized at 0xa5b0 with physical base 0x208081000 and
size 0x1000 before mapping. Thus the nonzero-context branch in 0xd170
targets offsets in that region, rather than an unidentified pointer.
This identifies the register region, not the meaning of its writes or
their persistence effects. The inspector emits the assignment window
and extracts both literals; no host MMIO access was made.

PreNand initialization follow-up: 0xbdd4 is a bounded six-entry lookup
in the table starting at 0x4c794 with stride 0x54, comparing two words
against input +0x48/+0x4c and returning a matching pointer or zero.
It performs no stores or nested calls. Later, 0x31168 passes r6 to
0xd170 after buffer initialization. That function checks the input's
first word and mapping flag before its nonzero branch writes through
input +0x10 -> descriptor +4 at offsets 0x68/0x6c/0x70/0x74 (2),
0x78 (0xff00), 0x80 (0xff00ff), and 0x7c (5). These are mapped
stores, not yet identified NAND program operations; the descriptor's
identity and the other branch still require tracing. The inspector
emits these exact bounded windows and lookup literal. No live writes
were performed and no persistence conclusion follows from this alone.

PreNand entry 0x3b9ac calls 0x30f4c at 0x3b9ba before inspecting
its request-state words. The initialization starts with RAM zeroing,
but also calls 0xbdd4, 0xd170, 0x32858, 0x31860, 0xd700 and 0xdffc
within the newly emitted 0x30f4c..0x31318 window; it is not a simple
empty-queue wait. Their effects require analysis before startup can be
classified as read-only. PostNand entry 0x38e20 clears its task mask,
calls 0x9724, then loops through 0x3b408 and 0x38e6c for two objects
separated by 0x744. The inspector records the entry windows and exact
literal for the first object. Neither task name nor the absence of host
write requests proves these initialization paths are write-free.

Main startup explicitly initializes the host command state at 0xa8a0:
literal 0xa8e4 is 0xd654c; after clearing 0x2e4 bytes, the halfword
store at 0xa8cc writes zero at +0x9d, including the host-write gate
0xd65e9. This is post-worker-registration initialization, independent
of the earlier BSS clear. It is not firmware-wide NAND write protection.
At the end of main, 0xb000 calls 0x3b6e8. That function returns if
0xd0484 +0xe is nonzero; otherwise, if current-task word 0xec750 is
zero, it calls selector 0x3b4e4, stores its result, and signals result
+4 via 0x37c14 when nonzero. This matches the object offset waited on
by the worker trampoline. Thus a conditional task-release path is
connected to startup; which task is first depends on scheduler state.
The inspector now records the literals and these bounded windows.

Startup worker registration is resolved at 0xa780..0xa7f0: it creates
eight tasks with common Thumb trampoline 0xf7f1 and table 0x404d0,
stride 12. The entries are Null/0x3007d, Update/0x3dc19, Cmd/0x3ad1d,
BG/0x10c75, Push/0x2214d, PreNand/0x3b9ad, PostNand/0x38e21 and
Timer/0x13879. The trampoline increments the started-task counter,
waits via 0x37d04 on the task object +4, and after further checks calls
the corresponding entry at 0xf864. The literal there independently
resolves to the same table. Registration alone therefore does not prove
the NAND-related tasks have been released. The preceding 0x3004c call
is identified by its strings as Krnl_SetRecoveryMode: it conditionally
logs and stores a byte at 0xd0493, rather than initializing NAND itself.
New bounded windows and table extraction reproduce these findings;
the task-release conditions remain the next startup question.

Repeated syslog initialization now frees the previous message scratch
buffer and invalidates both layout fields before processing the new
metadata. Zero entries/size and allocation failure leave logging disabled
instead of retaining stale metadata. The handler runs on RTKit's ordered
workqueue. Tests count allocations through three successful replacements,
allocation failure and both zero-field cases; the allocation count returns
to zero. Full offline tests and AArch64 rtkit.o compilation pass. Shared
firmware buffer ownership is unaffected by this scratch-buffer change.

The host RTKit syslog handler now rejects idx >= entry count, a zero
message length, and any entry not fully contained in its backing buffer
before copying. Previously idx == count passed and backing size was
checked only for nonzero. The pinned draft generator carries the fix;
test_rtkit_syslog.py exercises the actual generated handler with counted,
bounds-asserting copies, valid first/last entries, exclusive upper bound,
one-byte-short backing and zero-size/uninitialized metadata. Notifications
still receive the existing acknowledgement on rejected entries. The full
offline suite and AArch64 rtkit.o compilation pass. This is host receive
hardening for upcoming firmware communication, not a live boot result.

The retained selector-2 dispatch chain is now resolved through its
transport: registry[0] at 0x4c5e4 points to 0x700f8; entry +4 points
to object 0x4c23c, whose vtable 0x47b08 slot +0x10 is Thumb 0x384b9.
Function 0x384b8 tests object +0x10 bit 0, reads mapped base + control
offset, and tests bit 16 before sending. In the captured object the
base is 0xcc840b80, control offset 0x20 and data offset 0x30. The
non-full path at 0x385ae..0x385ba loads two payload words and stores
them with STRD at base + data offset. The full path can yield and retry;
the inspector emits the complete body and extracts the pointer chain.
This establishes a firmware-side message transport for this callback,
not a direct NAND operation at this call site. It does not establish
the effects of recipients, startup-wide read-only behavior, or physical
addresses from these mapped pointer values.

Callback 0x857c's remaining body has a response-dependent path: after
calling 0x38024 at 0x8710, it loops at 0x871a..0x872e until context
+0x54 becomes nonzero, yielding through 0x37a24. It later walks pending
ring indices at 0x8786..0x87b0 and calls 0x38024 with r2=0x500000
for each. The captured selector at context 0x4c0e4 +0xa8 is 2.
Function 0x38024 uses selector bits 8..10 to select a registry entry
and its low byte to select a subordinate entry. At 0x381f2 it invokes
a function pointer from the selected object's table +0x10. Thus these
calls require downstream dispatch analysis; they cannot be classified
as NAND writes or harmless RAM updates from this body alone. Full
bounded callback/dispatch windows and the captured selector are now
included in the inspector. No device operation was performed.

The normal downstream path of callback 0x7860 is now bounded: 0x77c4
increments RAM word 0x4c60c and calls 0x7b2a(1) only on the first
reference. The callback's release path decrements the same word and
calls 0x7b2a(0) on the last reference. Function 0x7b2a..0x7b56 contains
CP15 register updates and DSB/ISB barriers, with no further call or
peripheral load/store. This describes only this callback's normal path,
not all effects of changing CPU memory behavior or other callbacks.
The separate captured record table contains one record at 0x6e7a0:
Thumb callback 0x857d, context 0x4c0e4, saved state 0xa. Its entry
returns for equal states or either state 9; the decreasing-state path
can wait for context +0x84 ring counters to match, yielding via 0x37a24.
The inspector now extracts the bounded table and emits these code
windows. Registration and full effects of callback 0x857c remain open.

One power-callback registration path is now resolved. In mapping function
0x78c0, the successful path after 0x3610 loads the sixth argument from
[r7,+0xc] at 0x798c. The LSLS #22 / MI condition tests bit 9; when set,
0x7994..0x7998 loads literals 0x4c650 and 0x7861 and stores the latter
at object +0x44. Caller 0x84fe supplies flags 0x200 on the stack at
0x84d0..0x84d6, confirming a path that requests this registration.
The inspector emits the full mapping function and this caller's bounded
setup window, plus the actual object/callback literals. This resolves a
writer of the retained pointer, but does not yet establish when this
caller runs during startup or the effects of all power callbacks.

The explicit task setup at 0xa638 supplies name `power`, Thumb entry
0x9251 and context 0x4c650. Its entry compares context +0x20/+0x24;
when different, it conditionally invokes context +0x44 at 0x92e8,
iterates +0x28/+0x2c callback records of stride 12 at 0x9308, then
conditionally invokes +0x44 again at 0x9322. In the retained capture,
+0x44 is Thumb 0x7861 and the callback-record count is 1. In the pinned
pristine image both are zero (also the callback table pointer is zero).
Thus the captured callbacks must not be treated as initial boot state.
The retained callback includes conditional calls to 0x77c4 and 0x7b2a;
its registration and downstream effects remain to be traced. The
inspector emits the dispatch and callback bodies and saved context;
power-task-context-comparison.json pins both input hashes and records
the pristine/captured words. This adds no live startup authorization.

Startup main-path follow-up resolves the heap branch: literals 0xa7f4/
0xa7f8 point to 0BHR/0SHR. When both are nonzero, 0xa69a calls 0x7018;
its zero return branches back to 0xa58c, while its nonzero return calls
0x3cac and then also branches to 0xa58c. Thus supplying the prepared heap
does not bypass the previously identified platform initialization call.
After that call succeeds, 0xa5b0..0xa610 fills three resource descriptors
and calls 0x60b0 for each: object 0xd0680 has physical 0x208081000 and
size 0x1000; objects 0xd0658/0xd066c have physical 0x208800000/
0x208900000 and size 0x100000 each. These are descriptor inputs, not
claims about the peripherals' identities or proof of storage writes.
The later task-table bounds at 0xa828/0xa82c are both 0x601c4, so the
0xa6c4 loop is empty for this image; explicit calls before and after it
still run. The inspector now emits these three bounded windows and
the parameter/resource/table literals. Downstream startup side effects
remain unresolved; no firmware was started by this analysis.

The actual power preflight passed on the live J42d/T7000 RAM kernel 7.2.0.
The separate ans1_power_check.ko module has SHA-256
6261ef9494bfcbf7f8a6f90576bb94a4f169de9cae70269ef771acb764eda62a.
One insmod command produced PASS logs at uptime 19826.504666 and
19826.524231, followed by the intentional -ECANCELED result; the module
was absent from /proc/modules afterward. Successful return requires
the exact ANS 0x0f000200 and DEBUG 0x00000200 register snapshots.
No power write or ANS register access was performed. This validates the
kernel API path but does not establish power ownership or DMA quiescence.
Evidence: power-kernel-selftest.json.

The read-only power preflight now has host tests against the actual C
implementation. They cover both root compatibility checks, missing or
mismatched PMGR nodes, address conversion failures, incorrect resource
base/span, clock/reset/hwlock properties, regmap lookup and both read
failures, and all single-bit deviations from the two accepted snapshots.
They verify node-reference release and absence of register reads before
the topology guards succeed. The complete offline suite passes, including
test_power.py. This remains an instantaneous state check; it provides no
power ownership, DMA quiescence, or evidence of safe firmware startup.

Live exclusive reservation selftest passed: claim of the fixed 10 MiB
region succeeded, a competing claim returned -EBUSY, and release then
reclaim succeeded. No mapping or target-memory access occurred. The
module's ordinary-RAM firmware test also passed. After intentional
-ECANCELED termination, /proc/modules and /proc/iomem show no retained
test module or reservation claim. Evidence: reservation-kernel-selftest.json,
module SHA-256 0bb31a675cc5f61ec47442d6d6686ec3522e5e8a28489671c34009a57dfbf2bc.
This establishes resource arbitration, not DMA isolation or CPU quiescence.

Reservation preflight was revalidated on the current live kernel:
System RAM ends at 0x87e9f2000 except the 0x87e9f6000..0x87e9fa000
island, and display memory ends at 0x87ed7e000. The ANS interval
0x87f600000..0x880000000 overlaps neither. Repeated read-only PMGR
snapshots at uptime 18973 show ANS 0x0f000200 and DEBUG 0x00000200,
both target/actual zero. No physical-memory write was made. This is
a current snapshot only; a controller must claim the physical resource
and enforce the power/ownership conditions during placement, not rely
on an earlier report. Evidence: reservation-preflight-live.json.

Live kernel firmware selftest passed on RAM Linux 7.2.0: the module
requested the pinned image from the confirmed RAM rootfs, verified its
SHA-256 using kernel crypto, built the 10 MiB ordinary-RAM staging image,
checked heap geometry and the zero tail, then freed all allocations.
It intentionally returned -ECANCELED and did not remain in /proc/modules.
The log reported PASS at uptime 18864.447895 and 18864.474455; both
messages were observed from one insmod command. Evidence and exact
module/image hashes are in firmware-kernel-selftest.json. This validates
the kernel preparation path, not physical ANS memory, startup or reads.

Read-only live clock/revision snapshot: selector 0x85100000, PLL4
registers [0x80032010, 0x40000000, 0x88480348], revision register
0x20e02a010 = 0x00090011. Two successive snapshots match. The decoded
PLL rate is 2400000000 Hz, ANS rate is 266666666 Hz and revision fields
produce RCOS 0x11, matching the retained parameters. Raw values and
helper hash are in ans-clock-revision-live.json. The freestanding helper
opens /dev/mem read-only, maps PROT_READ and validates J42d/T7000.
No power change, firmware start, mailbox or NAND access was performed.

`CCNA` cache writer is resolved: 0x14dcc populates slots 8..56 at
0xb72bc; target 0xb739c is slot 56. Descriptor 0x4ea30 + 56*0x68
= 0x500f0 points to control register 0x20e0100c0. If bit 31 is clear,
the computed rate is zero. Otherwise bits 24..29 select a source-slot/
divisor pair, and the source's cached frequency is divided by that
divisor. The observed 12 pairs are preserved in the report (including
the terminal zero pair); do not index outside that proven descriptor
or divide by zero in Linux. Actual register selector and source rates
must be obtained before constructing `CCNA`; the retained numeric value
alone is insufficient. No clock MMIO was accessed in this analysis.

Remaining parameter sources: clock id 0x90 dispatches through byte
0x4ea0d to 0x14f00, which reads cached word 0xb739c. `CCNA` therefore
depends on clock initialization rather than being a literal frequency
in its callback; the cache writer remains unresolved. For `GKTS`,
0x36a30 passes the entire record payload and stored length to 0x337b4
(wrapper around 0x335e0), after which the caller forces one selected
payload byte to zero. Reusing the retained `GKTS` value is not justified.
The lookup and fill wrappers are now preserved as bounded windows.

`ans1_firmware_validate()` now joins pinned SHA-256, fwsg metadata,
the 16 packed parameter headers, and finite heap preflight in the
compile-only kernel core. It rejects other reservations and leaves
output unchanged on failure. The core builds with CONFIG_CRYPTO_LIB_SHA256=y.
`test_firmware.py` exercises the actual C validator with Windows BCrypt
as the SHA backend: the acquired image passes, five image mutations
fail -EBADMSG, and invalid size/base/span/null inputs fail before hashing.
Evidence is in artifacts/ans-offline-tests/firmware-validation.json.
This does not validate kernel crypto execution on the device or load
firmware; a controller, reservation ownership and safe startup remain.

`ans1_fw_heap()` now implements a bounded preflight calculation for the
finite IOVA-zero allocation mode: sorted nonoverlapping memory extents,
file-size <= memory-size, reservation overflow checks, 4 KiB alignment,
and image-extent >= rounded segment end. It returns the physical/IOVA
heap interval, capped by the requested size, without changing memory.
The pinned segment fixture yields 0x87f6f1000 / 0x90f000, matching the
retained parameters; overlap, overflow, undersized extent and exhausted
reservation cases reject without modifying output. The offline suite
passes. Image authentication, fwsg file-offset parsing and actual loader
integration remain required; this helper alone cannot authorize a boot.

Start-time fault preflight now reads both AKF controls before either
enable write. Observed fatal bits latch the fault, release the acquired
runtime-PM reference and return -EIO without scheduling work. The new
generated-function start test covers each bit in each direction,
persistent rejection, PM-resume failure, successful start and repeated
start. All offline tests and the arm64 mailbox.o build pass. This adds
host-side failure handling only; no device module was replaced.

The AKF fatal-status guard described below is now implemented in the
mailbox preparation script and regenerated draft patch. Bits 18/19 on
either control register latch `akf_faulted`; the detecting operation
returns -EIO before data access. Later public sends/polls and starts
reject the latched state; delayed polling stops rescheduling, while
normal stop retains responsibility for releasing the PM reference.
There is no software fault reset. TX/RX retain separate locks, so an
already in-flight operation on the other direction is not retroactively
cancelled; this guard is not DMA quiescence. Counted MMIO tests cover
each bit and persistent rejection after the status clears. The full
offline suite passes, and the generated mailbox.o compiles against the
pinned arm64 kernel. No updated module was loaded on the device.

Send/receive comparison found an outstanding transport guard: iBoot
0x21dec tests send-control bit 16 before a single 64-bit write;
0x21ef0 tests receive-control bit 17 before a single 64-bit read.
These match the draft's full/empty bits and word widths. However both
paths also test mask 0xc0000 (bits 18/19) and enter an assertion path
when either is set. The current Linux preparation script has no matching
fault-status check. Before live use, add an AKF-only latched fault that
rejects subsequent sends and suppresses receive delivery when these bits
are observed; test this before exposing the transport to a controller.
Do not inherit iBoot's ordering that may access data before asserting:
the Linux check should precede data access. Exact names of these status
bits remain unknown, so describe them as observed fatal-status bits.

Mailbox initialization: resource zero +0xb0 points to vtable 0x4a010
and +0xb8 to layout 0x4e8b0. Its first six 32-bit offsets are
0x1008, 0x1020, 0x1010, 0x1038, 0x1000, 0x1004, corroborating the
existing AKF single-64 transport's control/data positions relative to
0x208040000. Layout +0x18 is zero, so the optional 0x1111 register
write in 0x21d94 is skipped for ANS. That initializer registers two
interrupt callbacks via 0x7264. The post-CPU-start vtable +0x20 call
resolves to 0x21ff4, enabling both interrupts via 0x7208 when passed 1.
The Linux polling transport does not need iBoot's interrupt registration,
but its control/data setup still requires checking against the complete
send/receive paths. The pinned layout and relevant vtable functions are
now included in the offline evidence.

Power enable is now traced: 0x5dbc iterates resource entry +0x28's
32-bit gate slots, stopping at 0xffffffff, and calls 0x5ea4 for each.
Resource zero's list starts [99, 0xffffffff], so exactly gate 99 is
enabled. 0x151a8 computes 0x20e020000 + gate*8 = 0x20e020318,
matching the ANS PMGR address already derived from ADT (device id
0x16 is distinct from this register index 99). It preserves other bits,
sets the low nibble to 0xf, then polls until low nibble equals bits
4..7. iBoot's loop has no observed timeout; a Linux implementation
must use a bounded poll and stop on failure. This path establishes
power enable, not a separate reset pulse or proof of DMA quiescence.
The gate list and bounded disassembly are now in comparison outputs.

The extra +0xc2 startup path is a counter transfer: 0x20bc8 branches
to 0x504, which executes ISB then reads CNTPCT_EL0. The caller clears
bit 1 of resource-base +0x80c, writes the physical counter low/high
halves to +0x810/+0x884, and writes original control OR 2 back to
+0x80c. Helpers 0x3a314/0x3a37c bracket this with a nesting counter;
the outermost transitions execute DAIFSet/DAIFClr #3 via 0x5b4/0x5c0.
Thus these helpers mask interrupts for the counter update, rather than
performing cache maintenance. Register semantics beyond the observed
counter transfer are not inferred. The low-address primitives and
critical-section helpers are included in regenerated disassembly.

ANS start path: 0x748c calls 0x33d5c, whose ordinary path reaches
0x33e00 and passes configuration +0x4c, +0x40 and +0x48 (resource
index, region base, size) to 0x5ed8. The linked configuration's index
is zero. Resource zero's +0xc0..+0xc7 bytes are 0100010000000000.
For its initial +0xc3 = 0 path, 0x5ed8 sets register offset metadata,
calls 0x5dbc, converts the region address via 0x3a5a8 if possible,
then writes resource-base offsets +0x10/+0x14 = 0, +0x18/+0x1c =
size low/high, +8/+0xc = converted base low/high, and +0x20 = 1.
The +0xc2 = 1 path also performs additional register setup at
0x6104..0x615c; this needs interpretation before implementing it.
Finally 0x6194..0x61a4 writes 0x10 to resource-base +0x28, corroborating
the known CPU start bit. This is a static sequence, not authorization
to skip the unresolved power, timer/cache and read-only startup checks.
The entire bounded 0x5ed8..0x6200 function is now emitted for analysis.

Region id 2 is now resolved: 0x3b620/0x3b628 searches 0x20-byte
records by their first 32-bit id and returns record +8 (base/size pair).
The provider chain 0x3b450 -> 0x3b2b4 -> 0x19bec -> 0x138fc returns
the table at 0x54338 with count 15. Its first record is id 2, base
0x87f600000, size 0xa00000, exactly matching the captured ANS ADT
reservation. Thus the pinned iBoot's actual ANS load path uses that
10 MiB region, not an inferred other-device allocation. The comparison
report includes a literal table-vs-reservation check. This resolves the
base/size source for the heap calculation but does not validate firmware
startup side effects, DMA isolation, or NAND read-only behavior.

ANS loader linkage is confirmed at 0x7430: 0x3b620 is called with
region id 2, and its returned base/size pair is written to 0x54140/
0x54148 (configuration +0x40/+0x48). The callback structure at 0x54190
is passed to 0x33a24, which saves it as the loader object's first field;
its first pointer is 0x870054100. The initialized loader is then passed
to 0x33c70 at 0x7484. This establishes the runtime base/size source
and the connection to the analyzed allocation path. Region id 2's
underlying allocator still requires analysis. Earlier transcription of
the configuration pointer as offset 0x54188 was wrong: it is 0x54190;
the report has been corrected against the binary and instruction stream.

ANS-named configuration candidate: image offset 0x54100 begins with
pointers to `ANS` (0x4819f) and `arm-io/ans/iop-ans-nub` (0x481a3).
Pointer 0x54190 references this object; the nearby callback pointer at
0x541b8 references 0x798c. That function writes raw tag `CCNA` with
the result of 0x14e6c called with id 0x90, providing another concrete
ANS-specific startup parameter source. The candidate's +0x18/+0x28/
+0x30/+0x38/+0x40 fields are initially zero; runtime mutation and its
linkage to the loader must still be traced before choosing an allocation
branch from these static bytes. The raw template and callback window
are included in the comparison output. No device I/O was performed.

Allocation source selection: 0x35020 tests 32-bit configuration fields
+0x18, +0x28, +0x30 and +0x38, returning true if any is nonzero.
The false path at 0x353a4 builds a finite physical interval from config
+0x40 (base) and +0x48 (32-bit size), with all-ones base handling.
The true path instead uses encoded descriptors at +0x18 and +0x28,
including a compatibility predicate at 0x357c8. ANS configuration
initialization is still required to select the applicable branch.
Separately, 0x64d8 obtains allocation alignment from resource-table
entry +0xc8; entry zero is 0x1000. This explains the 4 KiB rounding
source for that entry, independently of the `ARcM` property. Selection
of resource index zero for this specific startup call remains unproven.

The heap allocation object is specifically a remaining-span descriptor.
At 0x33cf8, 0x352b0 receives a stack output buffer as its fourth argument;
success passes that buffer to 0x3604c. At 0x35718..0x3572c, 0x352b0
calls 0x359b0 on its selected allocation descriptor and copies the
64-byte result into that output buffer. For finite ordinary bounds,
let P = input +8, Q = input +0x10, V = input +0x18 and W = input +0x20.
0x359b0 produces physical interval [P+(W-V), Q) at output +8/+0x10
and corresponding address interval [W, W+(Q-P)-(W-V)) at +0x18/+0x20.
All-ones bounds have special handling and are not covered by these
finite equations. Consequently, the heap setter translates its requested
start from the latter interval into the remaining physical interval.
The selected source allocation's creation and ANS-specific branch
selection remain to be established; do not mistake this tail descriptor
for an independently allocated heap. Three bounded disassembly windows
now preserve the caller, output copy and transform evidence.

Heap callback context is now traced one level upstream. Function 0x3604c
looks up `__TEXT` and `__DATA` via 0x36238 in the 0x48-stride segment
list at its first argument +0x928. At 0x360f4 it builds a stack context
whose +8 is `__TEXT` field +0x10 (zero if absent) and whose +0x10 is
the original second argument to 0x3604c. At 0x36120 it registers
0x362d8 with that stack context as the second of three callback pairs.
Dispatcher 0x36640..0x36650 passes each pair's context in x0 and the
parameter table in x1. Thus the heap calculation's allocation object
comes from the original second argument to 0x3604c, not directly from
the fwsg bytes. Its initializer still needs tracing before reproducing
the calculation in the controller. Bounded setup, segment lookup and
dispatch windows are regenerated by the comparison script.

Parameter mutation follow-up: 0x34e50 calls 0x34fd8/0x34e9c to
find the first matching raw 32-bit tag between the table's start/end
pointers, advancing by stored length + 8 without alignment rounding.
It rejects a requested length different from the record's stored length
and only then copies bytes to record +8 through 0x2e430. Missing tags
return false. This confirms packed, potentially unaligned parameters
and exact-size updates. The offline comparison now rejects duplicate
tags and verifies the expected 16-record terminal boundary; its emitted
setter window includes lookup and argument handling. The iBoot lookup
itself does not establish malformed-input safety, so a future Linux
loader must validate all record boundaries before any parameter update.

Heap parameter follow-up: function 0x362d8 saves its first argument as
x20 and its parameter-table argument as x19 through 0x369e4. It reads
`ZSTR`, adds it to first-argument field +8, and checks the result against
allocation-object field +0x20 (object pointer at first-argument +0x10).
It then translates the resulting address using allocation fields +8
and +0x18, writes `0BHR`, and limits `0SHR` to the remaining span.
The allocation's upper bound is field +0x10; all-ones is special-cased.
Caller field initialization remains untraced, so this is not yet a
reimplementation specification. Snapshot arithmetic is consistent:
0x87f600000 + 0xf1000 = 0x87f6f1000, and adding retained heap size
0x90f000 reaches exactly 0x880000000, the reservation end. The comparison
report now records this check and includes the complete bounded function
window and argument-save helper. No firmware parameters were changed.

`ARcM` lookup follow-up: 0x2ed04 resolves property id 0xe00 through
0x2eb6c and checks byte +6 against requested type 0x30000 >> 16.
The property pointer table 0x52678..0x52890 contains a matching entry
at 0x52688, pointer 0x87004b890 (image-relative 0x4b890 using the
0x870000000 pointer base). That record has id 0xe00, metadata 0x30000
and value 0x1000 at +8. The ordinary value path of 0x2ed74 reads +8;
the function-pointer/dynamic-value flags are absent for this record.
This corroborates the observed 4 KiB parameter for this pinned build;
it is not a generic guarantee for other firmware or SoCs. The property
lookup/value windows and record bytes are now included in comparison
outputs.

Parameter source follow-up: 0x14544 returns literal 0x7000. Function
0x1454c reads 0x20e02a010 twice and combines fields (bits 19..21 to
output 4..6, bits 16..18 to output 0..2); `RCOS` is therefore hardware
derived, not a fixed revision constant. Resource getters 0x6534/0x6580
use a 0x108-byte-stride table at 0x530d0; entry zero contains base
0x208040000 and secondary value zero at +0x10. The entry index comes
from the caller's object+0x4c and still needs its assignment traced.
Function 0x36960 obtains `ARcM` through 0x2edf4 with arguments 0xe00
and 0x30000, so its observed 0x1000 value is not yet classified as a
hardcoded platform constant. No new MMIO reads were performed; all
of these observations are disassembly of the pinned iBoot candidate.

iBoot parameter writers located: at 0x36514 `_COS` receives the return
of 0x14544, at 0x3652c `RCOS` receives 0x1454c, at 0x36548 `dApC`
receives 0x6580, at 0x36564 `dArW` receives 0x6534, and at 0x3657c
`ARcM` receives 0x36960. Helpers 0x34ed8 and 0x34f2c pass 4-byte and
8-byte values respectively to 0x34e50. The separate path 0x36338..0x363b4
reads `0SHR`, computes an address for `0BHR`, and bounds `0SHR` by
available space. Thus these are calculated host-side boot parameters;
retained values are not a reusable constant set. The comparison script
now regenerates bounded AArch64 iBoot windows for these paths.

The 16 packed parameter records at 0x48000..0x480d1 have identical
tag/length headers in pristine and retained images but several changed
payloads. For example raw tag `_COS` changes from 0xffffffff to 0x7000,
`RCOS` from 0xffffffff to 0x11, and `dArW` from zero to 0x208040000.
`ARcM` changes from 0x4000 to 0x1000. The two records `0BHR`/`0SHR`
also differ (including a retained physical address). Names here preserve
raw tag-byte order; semantic names and ownership are not inferred from
spelling alone. The comparison script now validates all record headers
and emits both payloads. Do not blindly copy retained values into the
pristine image: some are per-boot addresses or state. These differences
show that extracting identical code does not supply a complete validated
boot configuration. The writer and lifetime of each required parameter
remain part of controller integration.

Format cross-check: the independent
[fwsg parser source](https://github.com/nlitsme/AppleC4000/blob/master/loadfwsg.py)
uses a trailer at EOF-32 and 32-byte `<Q4L8s` segment entries, matching
the observed A1625 candidate. Its flag after the magic is explicitly
unknown, so the local script no longer calls that field a version.
The table end equals the trailer start and the trailer is exactly
32 bytes before the end of the 0x60240-byte candidate. These checks
support the container extent. The reference targets a different device
and is used only to corroborate the file layout, never hardware behavior
or A1625 boot compatibility.

An offline comparison candidate was extracted from Apple's AppleTV5,3
17L256 IPSW (the installed tvOS version is still unknown). Its decrypted
iBoot SHA256 is 119cbaa86cb775d0c7f224971a700c7e5797ee7b987104ced1de0cb4c785ef95.
The ANS candidate starts at iBoot offset 0x55000. Its observed `fwsg`
trailer describes __TEXT at offset/address zero, file/memory size
0x47b88, and __DATA at offset/address 0x48000, file size 0x181c4,
memory size 0xa8bc4. The entire __TEXT segment matches the retained
capture byte for byte, SHA256
ab4ebe816a30b1e01b79fc6e1d0b4486cd59d03ba16f3a2b99623a05eb9db368.
All 991 differences below 0x48000 are after the __TEXT end. This
establishes code identity for the analyzed windows, not installed tvOS
identity, live controller state or absence of firmware-originated writes.
The pristine resource object has physical pair 0x208040000 and mapped
flag zero, while the retained object contains the mapped low word and
flag one. Reproduce with `../compare-ans-pristine.py`; acquisition and
comparison reports are under artifacts/ans-pristine-candidate. No device
transfer or restore was performed. A generic firmware loader and the
semantics of the fwsg trailer are not validated by this comparison.

## Restart clears the retained state used in earlier traces

Mapping body 0x6edc confirms the split address interpretation. It derives
the input page number from low>>12 OR high<<20, saves low&0xfff as
the byte offset, and searches existing ranges using translated addresses
from 0x34a4. A new mapping calls 0x7282 for pages and then 0x3610;
success returns allocated_page<<12 OR original_offset at 0x6fde.
The reuse path at 0x7002..0x700e returns a page-adjusted address with
the same byte offset. Thus the value written back by 0x60b0 is a
32-bit mapped address, not the original low half of a physical pair.
The captured resource object is outside the startup-zeroed interval,
so restarting this raw retained image requires analysis of retained
mapping flags and stale addresses as well as cleared BSS. Do not treat
the DRAM capture as a pristine reloadable firmware image.

Correction to the retained resource-address interpretation: helper 0x60b0
tests resource+0x10 bit 0, passes +4/+8 and size +0xc to 0x6eac only
when not already mapped, writes the nonzero return value to +4 ONLY,
then sets bit 0. The capture's object 0x4c6d8 has bit 0 set. Thus
concatenating its +8/+4 into 0x2cc840000 is not evidence of a physical
address: +4 has been replaced by a mapping result while +8 is retained.
The mapping wrapper delegates to 0x6edc. Its complete address-translation
behavior remains to be inspected. This resolves the earlier apparent
alternate-physical-base discrepancy without guessing a host MMIO address.

The platform callback 0x1e78 dispatches operation 1 to 0x1ebe via an
eight-entry TBH. It propagates fields from object 0x4c6d8 into resource
objects 0x4c328, 0x4c2e8 and others. When object+4/+8 are both zero,
it reads an eight-byte descriptor payload at 0x48034+8 and sets the
resource size to 0x20000. That payload is 0x0000000208040000, matching
the ANS register base in the ADT. This is a fallback: captured object
+4/+8 instead contain 0x00000002cc840000, so the descriptor is not
necessarily selected. The reason for that alternate retained address
and subsequent resource mapping is unresolved. Do not substitute the
descriptor or retained value into a host MMIO action without resolving
the address spaces. New bounded platform-dispatch/resource windows
preserve this startup distinction.

Post-zeroing trace: after MMU setup, entry calls 0x3a7c, 0x16c0,
0x2f6c, then 0xa54c with argument zero. Function 0x2f6c iterates two
function-pointer arrays, but both are empty in this image: bounds
0x47a72..0x47a72 and 0x601c4..0x601c4. It therefore does not restore
the cleared state via these arrays. Main entry 0xa54c has parameter-
dependent paths; its fallback dereferences object 0x4c6d8's table
0x47a74 and calls Thumb target 0x1e79 with arguments (object,1,0,0).
That object/table are below the default zeroed interval. This identifies
the next startup call to inspect, not a proof of storage initialization
or its safety. Earlier calls 0x3a7c and 0x16c0 also remain in scope.

At Thumb entry 0x2c86..0x2c9e, two eight-byte parameter payloads are copied
from descriptors 0x4807d and 0x4808d. Both payloads are zero in the pinned
capture. The fallback at 0x2ca2..0x2cb4 therefore selects start 0x60200
and end 0xf0bc4 from literals 0x2f2c/0x2f30. The special-page exclusion
compares start with 0x480e0; this fallback start is above that address,
so it goes directly to the zero-fill call at 0x2cd4. ARM helper 0x1a5c
replicates its byte argument and fills the requested length; here the
byte is zero.

Consequently, replaying this entry with these parameter contents clears
the retained geometry, writable flag, worker state, allocator state and
task-event state examined below. Their captured values are useful for
reverse engineering but cannot justify a post-restart branch prediction.
Subsequent initialization must reconstruct them. This invalidates any
attempt to use the saved worker's early-exit condition as a boot safety
argument; no such restart has been performed. The existing `thumb-entry`
window plus new `bootstrap-memset` window and zeroing literals reproduce
this conclusion. Host modifications to the parameter descriptors would
require separate analysis and are not assumed here.

## Host command enabling writes

Allocator wakeup source resolved: in the no-available-range path at
0x32bca..0x32bd4, code dereferences the task pointer at 0xec750, loads
its first halfword, ORs it into allocator+8 (0xf0778), and calls the
previously identified scheduler at 0x3b574 before retrying the range scan.
This is a waiting-task mask, not a fixed storage-operation event. The
pinned capture has mask zero. That only describes the saved instant;
new allocations after restart can register different waiting tasks.
The inspector records the mask and task-pointer literal and emits the
bounded registration window for reproducibility.

Release-call follow-up: 0x2db68 routes request tags 0xb0 and 0x85 to
0x2e0e8; all others go to the already traced 0x3b3b8 completion path.
0x2e0e8 passes request words +0x10/+0x14 to 0x32a98 and tail-calls
0x3b734. Function 0x32a98 updates a bitmap or coalesces sorted ranges
in the RAM object at 0xf0770. Its non-assertion path has no further
function calls, but at 0x32b2e it consumes object+8 and atomically ORs
that value into event word 0xec74c when nonzero. Thus allocator release
can wake other tasks; absence of a direct NAND call in this function is
not proof of globally write-free execution. The inspector now includes
the complete bounded bodies of these three functions.

For the saved-image values only, the worker entry would follow the early
exit branch: state 0xdc1f0 = 0, selector 0xdb3a6 = 0xff, enabled byte
0xdc24c = 1, pending word 0x95d68 = 0. The pending check at 0x2c7be
therefore branches to 0x2d20a. That path reaches calls to 0x2db78 and
0x2dc68 before clearing the callback pointer. This is not a bare return:
0x2db78 traverses ten request lists and calls 0x2db68 for each entry;
0x2dc68 conditionally calls 0x32a98 and resets buffer bookkeeping.
These callees and the post-reset state remain relevant to the startup
audit. Saved values do not prove the same branch occurs after restart.

The shared call to 0x2c724 is not itself a write-enable check: it checks
byte 0xd05b0 (object 0xd057c +0x34), installs Thumb callback 0x2c761
at 0xdc270, and signals event mask 0x10 via 0x2d488. Worker 0x2c760
checks the same byte, then processes state from object 0xdc1f0. Thus
the worker-entry guard and host write permission at 0xd65e9 are distinct.
The bounded worker-entry window does not establish that its downstream
operations are read-only. The fact that both the Clog Read-Only path and
write-enable command schedule this worker must not be used as proof that
the worker can safely be skipped, or that it only runs after write enable.

Captured firmware dispatch at 0x3d3ba compares host opcode with 0x19;
the matching branch selects internal opcode 0x1f and joins the internal
opcode store at 0x3d450. Internal TBH entry 0x1f selects 0x18c70.
There, object 0xd654c byte +0x9d is checked, and when zero is set to 1
at 0x18c86 before calls to 0x2c724 and 0x1757c. This is the same flag
checked by the host-write path. Host opcode 0x19 must remain outside
the read-only command allowlist; do not send it as generic initialization.

The captured byte at 0xd65e9 is zero. This establishes only the retained
flag value and the identified command transition. It does not rule out
other writers (including bulk initialization) or background NAND writes,
and does not authorize starting the controller on that assumption.
The inspector emits both bounded windows and the computed internal table
target. No enabling command or flag modification has been performed.

## Captured firmware identify producer located

Resolved entry literals: r5 = 0x7e028, configuration object = 0x9597c,
r12 = 0x78f28, and the pending-state source object = 0xd654c.
In the pinned capture, pages at 0x7e040 = 7,812,500, implying
32,000,000,000 bytes at 4096 bytes/page; the preferred factors at
0x95b8c and 0x95b94 are 8 and 4. The formatted byte at 0x78f54 is 1.
The pending source word at 0xd65d4 is 6, so CLZ(value)>>5 yields 0.
Function 0x2f48c returns a boolean: mode at configuration+0x234 equal
to 3 selects byte 0xdc24c; other modes select word 0x7e030. The capture
has mode 2 and word 2, therefore that function would return 1.
These are retained-image inputs, not a live identify response and not
authority to register a disk, issue an LBA read, or assume controller state.
The inspector records the raw inputs separately from protocol observations.

The dispatcher at 0x18316 loads the internal request byte +0x1d with
writeback, subtracts one and bounds the index below 64. TBH at 0x1834e
uses table 0x18352; internal opcode 0x1b selects halfword 0x03cb at
0x18386 and branches to 0x18ae8. This resolves the earlier search gap:
the writeback operand was printed as decimal `#29`, unlike ordinary
offset loads printed as hexadecimal.

That branch gathers values and joins 0x19138/0x1913a. At 0x19198 the
original request's tag at +0x18 indexes table 0xc9828. The resulting
command receives words at +0x30 through +0x5c. In particular,
0x191cc..0x191d0 stores literal 0x1000 at +0x34, independently supporting
the decoder's 4096-byte page size. +0x30 comes from the object loaded
into r5 at entry, offset +0x18; +0x38 is the product of another object's
+0x210 and +0x218; +0x3c is a byte from the entry r12 object's +0x2c;
+0x40 is the return of 0x2f48c. +0x44 is derived from CLZ of a word at
+0x88 followed by a five-bit right shift (zero -> 1, nonzero -> 0).
The object identities and semantic meaning of each field still need
validation; this is not runtime geometry or a NAND read.

The hash-checked inspector emits three bounded windows and computes the
opcode 0x1b table target directly from captured bytes. No firmware changes,
power changes or mailbox transactions were needed for this result.

## Captured-image completion path follow-up

Further bounded inspection confirms a decrement of the per-index halfword
at +0x2e2 in 0x3b79a..0x3b7a0 inside 0x3b734. At 0x3d734 the index is
bounded below 128; its active bitmap bit is required and cleared, and the
aggregate active count at +0x38 is decremented. The status byte at
+0x448 maps values 0..5 to success for ordinary commands, 0x10 to 1,
0x0b to 2, and other values to 3 (opcode 0x80 has a separate table).
The path calls 0x3ce14 with the index and mapped status at 0x3d7e4.

At 0x3ce22..0x3ce36, the completion word is assembled as
`0x0600000000000002 + (tag << 4) + (status << 12)` for the bounded
ordinary tag/status values. At 0x3ce7e..0x3ce86, it passes endpoint 6 and
the two word halves to 0x38024. This supports the existing low-16-bit
completion decoding in `ans1_reply.h` for this captured firmware. It does
not prove endpoint advertisement, readiness or an actual mailbox exchange;
the runtime endpoint-selection gate remains required. These routines do not
produce the identify geometry. Reproduce their windows with the inspector's
`request-release`, `tag-completion`, and `completion-wire` outputs.

The hash-checked inspector now emits `ans-fw-request-completion.txt` for
0x3b3b8..0x3b3ec. This function reads request byte +0x1e and halfword +0x18,
calls 0x3b734, and uses the latter value as an index into the object whose
literal at 0x3b3ec is 0x95bfc. It keeps the unsigned maximum of the byte value
and object[0x448 + index]. It returns when the halfword at
object[0x2e2 + 2*index] is nonzero; otherwise it tail-calls 0x3d734 with the
index. This is consistent with aggregated status and a remaining-request
count, but those field names remain interpretations pending inspection of
their writers. It does not identify the geometry producer.

The additional `ans-fw-range-index-bounds.txt` window excludes the apparent
0x1b comparison at 0x35c8c as direct opcode dispatch: it bounds two function
arguments (r2 <= 0x1a, r3 <= 0x1b), then iterates indexed 16-byte entries.
The next useful trace is the producer/consumer chain around 0x3b734 and
0x3d734, rather than treating each immediate 0x1b as identify handling.
Both windows were regenerated successfully from the pinned capture; no
controller start or device transaction was performed for this analysis.

## Identify handler search: excluded candidates

A linear Thumb disassembly of 0x2c20..0x3fd00 was generated as a search index
(`ans-fw-thumb-linear.txt`). It includes literal pools and ARM fragments, so
matches are candidates only. For example, the apparent `cmp r0,#0x1b` at
0x3f654 is a literal word 0x4281b, not proven executable control flow.

The indirect table at 0x3fff0 is also **not** a valid identify-handler lookup:
its caller 0x36968 loads the request halfword at +0x1d, masks its low byte with
0xfc and requires the result to be below 0x14 before reaching the table lookup
at 0x369b0. Operation 0x1b fails that guard. Interpreting entry 0x1b from this
table would read unrelated data, not establish an identify function pointer.
The capture inspector now reproduces the guard/lookup window.

The internal operation-0x1b handler and response stores have not yet been
located. Consequently the live-image response layout is still unverified;
the existing decoder's 16M568 host-driver evidence remains its stated basis.

## Captured host-command dispatch and writable gate

At 0x3cf82 the firmware loads command byte 0. It subtracts 0x10 and dispatches
0x10..0x13 through TBH at 0x3cfa4. The table resolves to 0x3cfb0 (0x10),
0x3d1d4 (0x11), 0x3d062 (0x12), 0x3d140 (0x13). The first two match the
pinned upstream UserArea read/write opcode assignments. The command's u32
words at +4 and +8 were copied into an internal request at +0xc/+0x10;
flag bits from command byte +2 are also copied before dispatch.

The 0x11 path checks a byte at object+0x9d (0x3d20a) and takes a diagnostic
failure branch when zero. The base was loaded from literal 0x3d1b8, value
0xd654c. Another gated path at 0x3d650 checks the same byte and reaches
`Command %d requiring writable is in violation` (string 0x4744b, literal
0x3d71c, log call 0x3d66a). It rechecks before its diagnostic failure branch.
This is actual command-path writable-state evidence, unlike the Clog timestamp.
The byte's initialization, writers and coverage of background NAND activity
remain unknown; it was not modified and must not be used as a blanket inhibit.

Opcode 0 reaches the zero test at 0x3d4f6, sets internal operation byte 0x1b,
then joins request return through 0x3d450/0x3d452. This supports the draft's
identify opcode against the captured firmware, but the internal identify
handler, completion and response geometry still need to be traced. No command
was sent. The capture inspector saves these windows and decodes the TBH table.

## State-bit consumer follow-up

The captured image has 32 aligned literal references to 0xec74c below 0x48000.
This is not an exhaustive instruction/reference analysis. A confirmed consumer
at 0x3b4e4 loads that address and calls 0x3b3f0 with mask 0xffffffff. The latter
atomically clears masked bits and returns their previous values. Subsequent
code combines those values with other masks, uses CLZ to select a table entry,
and indexes a 12-byte-entry table at 0xec6e4. Before return it ORs remaining
bits back through helper 0x2ffe4.

The first eight captured table entries have low-halfword masks
1,2,4,8,16,32,64,128. The entry with mask 4 contains two pointers 0x6b740.
The surrounding caller 0x3b574 switches through entry+4 and later returns to
the previous entry. These observations support a task/event scheduling role
for the word, rather than a dedicated NAND write-protect control. The precise
task name and actions associated with mask 4 are not yet identified. No bit was
changed, and no inference of safe startup follows from its captured zero value.
The capture inspector records the literal candidates and first eight table
entries and saves the consumer/selection disassembly for reproduction.

## Meaning of the captured firmware's Read-Only string

The literal pointer at image offset 0x1229c points to the string at 0x41f8b,
`%s:Clog Read-Only - timestamp : %d ms`. Thumb code at 0x12116 loads that
pointer into r3 and calls 0x9120 at 0x12118, after calculating elapsed time.
Nearby strings also report `Init` and `Util` timestamps. This is evidence of
an initialization milestone log, not a firmware-wide write-protection option.

Execution continues after the log: 0x1211e stores value 6 into an object at
offset 0x88; 0x12122 calls 0x2c724; 0x12128 calls 0x10c38 with argument 4.
The latter loads address 0xec74c from literal 0x10c40 and atomically ORs its
argument into that word using LDREX/STREX. Thus this call sets bit 2 in a
firmware state word. The consumers and meaning of the bit remain unknown;
it must not be described as a hardware NAND write-disable bit.

The pinned capture inspector now reproduces these disassembly windows with
Thumb hardware-division decoding enabled and records the literal reference.
No firmware patch, state-bit modification, or device startup was performed.

## Captured firmware bootstrap analysis

`../inspect-live-ans-image.py` pins the complete capture hash and creates an
ELF container solely for offline ARM/Thumb disassembly with native LLVM tools.
The raw firmware is not edited and the ELF container is not a boot payload.
Outputs are `ans-fw-analysis.json`, `ans-fw-bootstrap.txt` and
`ans-fw-thumb-entry.txt` under ignored `artifacts/ans-offline-tests`.

Verified instructions in the captured image (offsets relative to its base):

- At 0x0, ARM branch targets 0x20; other initial vectors loop on themselves.
- Bootstrap at 0x20 configures CPU state and translation/cache-related state.
- At 0x36c, it loads r4 from literal 0x464; the literal is 0x2c21.
- At 0x370, `bx r4` switches to Thumb entry 0x2c20. Thumb decoding there
  yields a function prologue and further startup logic.

This confirms an ARM/Thumb execution path in the retained image. It does not
establish that reset/restart against retained mutable data is safe. Strings
include format routines and `Clog Read-Only`, but neither presence nor absence
of such strings proves write protection, and no writable firmware entry was
executed. The next firmware audit must trace actual control flow and state,
not infer a safe mode from these labels.

## Successful read-only DRAM capture (2026-09-09, after read() rejection)

The arm64 `mmap()` range validator differs from the `read()` validator: it
checks the physical address width. After reviewing this path, the fixed-range
freestanding helper `../probe/ans-fw-page.c` was built natively with clang/lld
for AArch64 Linux. It checks j42d+t7000 compatible strings, opens `/dev/mem`
O_RDONLY, maps PROT_READ, copies into its own buffer, unmaps and emits stdout.
It accepts no addresses/lengths from users; builds allow only 4096 bytes or the
exact 10485760-byte saved-ADT region starting at 0x87f600000. No ANS registers,
power transitions, endpoint messages or persistent storage writes occur.

First-page helper SHA256:
`54d85cc6476402559620982ad481bba02f58ee0a6f484101ec106fa02734a61d`.
Full-region helper SHA256:
`28cbb03fd85daa8825fd842687f23ade510cc7740d0e051f6bc73a335ed44f3b`.
Both were uploaded to RAM /tmp and their hashes checked before execution.
Execution was bounded by `timeout 5` and `timeout 15`, respectively; both exited
zero. Full-region compilation defines `ANS_FW_CAPTURE_BYTES=10485760`.

Capture results, with remote/local hash agreement:

| Capture | Bytes | SHA256 |
| --- | --- | --- |
| First page | 4096 | 45feeb6241625cb9e22548650454ed9a51c29f88f65d54b0974b588a634c5ba8 |
| Complete ADT region | 10485760 | 41ce142b90ce7b4fe51a4ea078dcbc6a936d19129b7f8709fcbe5a4e674a1482 |

Local ignored artifacts are `artifacts/ans-offline-tests/ans-fw-live-page.bin`
and `ans-fw-live-region.bin`. The full capture's first-page hash matches the
separate page capture. There are 909306 nonzero bytes. Selected ASCII markers:

- offset 0x3fd00: `RTKit_iOS-1264.100.25.release`
- offset 0x3feaf: `8PPNAppleStorageProcessorANS1-710.500.1~1315~20200222@134216`

The first words resemble AArch32 exception-vector branches (first word
0xea000006, following words 0xeafffffe). This and the markers provide evidence
of retained ANS firmware content, not a complete integrity/authenticity check.
The installed tvOS version is still unknown. The 16M568 static driver analysis
is a different provenance and must not silently be treated as this firmware's
matching host driver. Snapshot consistency beyond the matching first page,
firmware initialization state, remapping and write-free startup remain open.

## Current RAM-session retention check (2026-09-09)

Read-only SSH revalidation returned kernel 7.2.0 and exact root compatibles
`apple,j42d`, `apple,t7000`, `apple,arm-platform`. Partitions are zram0 and the
old 64 KiB synthetic ans1ramtest0; there is still no NAND block device.
The reserved-memory tree still has only the two flash regions described below.

A single bounded attempt to read the first 4096 bytes of the ADT-described ANS
DRAM interval at physical 0x87f600000 through `/dev/mem` returned
`dd: /dev/mem: Bad address` (exit 1). No firmware bytes or hash were obtained.
The command's output path was RAM `/tmp/ans-fw-first-page.bin`; it is not valid
capture evidence. No ANS MMIO, power transition or mailbox send was performed.

The matching kernel's `arch/arm64/mm/mmap.c:43` requires both
`memblock_is_region_memory(addr, size)` and `memblock_is_map_memory(addr)` for
`read()` access. `drivers/char/mem.c:94` returns EFAULT before its copy loop when
this check fails. The ANS interval is outside this boot's reported System RAM,
so the result is consistent with the kernel range check. It does not show that
the physical DRAM is absent or that firmware has been erased. No alternate
mapping or repeat attempt was made in this check. Retained firmware contents
and safe startup remain unverified.

## Polling transport

The first ANS1 controller should use a bounded polling transport, based on
pinned m1n1 `src/akf.c` at d5a10ac52a6468484854419a6c5130f1d62073eb.
That implementation checks FIFO control bits and performs one 64-bit transfer;
it does not request interrupts. Therefore unknown ADT IRQ roles need not be
guessed to implement the initial polling path. The generated mailbox draft now
has an AKF-only polling path, compiled and exercised with host mocks; it has
not been bound to real hardware.

Integration requirements (draft implementations exist; hardware validation is
still required before claiming these requirements are satisfied):

1. Add an explicit AKF-only polling transport mode, with no IRQ requests,
   enables or disables on that path. Keep ASC/M3 behavior unchanged.
2. Poll from a cancelable process-context worker with a per-pass message budget
   and scheduled delay; no unbounded loop with interrupts disabled. RTKit must
   receive management messages while its boot caller waits.
3. Stop new sends and synchronously cancel polling before detaching callbacks.
   Never cancel synchronously while holding a lock needed by the worker.
   Stopping host polling does not stop IOP DMA.
4. Implement controller-owned DMA lifetime separately. Retain published buffers
   after failure until hardware quiescence is independently established.

The firmware remapping helper is not sufficient validation to copy into Linux:
`akf_fw_get_region_new` takes independent minima of physical and IOVA addresses
and a physical maximum. It does not check arithmetic overflow, segment record
remainder, a constant physical-to-IOVA translation, or ownership of gaps in the
enclosing interval. A Linux importer must validate those conditions against the
actual A1625 segment metadata and reserved-memory ownership before any remap.

The upstream CPU-stop helper only clears control bit 4. It contains no DMA-idle
acknowledgement. Treating that bit clear as permission to free DMA buffers would
exceed the evidence. Current ANS power-off metadata also does not establish that
the preloaded firmware remains intact. No hardware startup is authorized by
these source observations alone.

This decision removes IRQ identification from the critical path for the first
polling implementation; it does not satisfy NAND enumeration, read-only block
registration, reference-sector comparison or cold-boot acceptance.

Saved A1625 ADT validation with `../inspect_ans_firmware.py`: the two segments
have one consistent physical/IOVA translation, no overlaps and no gaps. Their
combined physical interval is 0x87f600000..0x880000000, IOVA base 0, size 10 MiB.
Source ADT SHA256 is 518966e6bbb52544f1b361cbf25386fdadfdd85d5380c4936c790bd5dca9e344.
Both remap fields are nonzero and one unknown field is nonzero; their semantics
remain unresolved. This validates layout arithmetic only, not retained firmware
contents or reserved-memory ownership. The decoder uses the pinned `src/adt.h`
packed layout (three u64 fields and two u32 fields, 32 bytes per record).

Earlier live read-only revalidation (SSH, before synthetic block tests): root compatibles
are `apple,j42d`, `apple,t7000`, `apple,arm-platform`; kernel is 7.2.0 and
`/proc/partitions` then contained only zram0. The later synthetic tests left
`ans1ramtest0` present because this kernel cannot unload modules; it is RAM,
not NAND. See `block-selftest-evidence.md`. `/proc/iomem` ends ordinary RAM at
0x87e9f2000 (exclusive), with a small separate reserved RAM range at
0x87e9f6000..0x87e9fa000 and simpledrm ending at 0x87ed7e000. The ANS interval
0x87f600000..0x880000000 has no entry. The live FDT `reserved-memory` directory
contains only flash@87e9f6000 and flash@805849000, with no ANS reservation.
Thus an importer cannot currently obtain an ANS reserved-memory phandle from
this FDT. Being outside allocatable RAM does not prove firmware retention or
controller ownership. No /dev/mem mapping, firmware read, power transition or
mailbox transaction was performed during this revalidation.
