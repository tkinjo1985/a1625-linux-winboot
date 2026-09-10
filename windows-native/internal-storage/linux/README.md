# Linux ANS1 components under development

The RTKit draft exports `apple_rtkit_ans1_endpoint` for explicitly opted-in
ANS clients after successful boot. It selects only advertised endpoints:
protocol 10 prefers 6 then 5; protocols 11/12 require 32. Stopped RTKit, boot
failure, missing endpoints, disabled opt-in and unsupported versions return
zero. The read client's start checks its configured endpoint against this
selection before sending anything. Host tests cover selection, mismatches and
the lifecycle path; both `rtkit.o` and `ans1_core.o` compile for ARM64.
This requires the companion RTKit patch and does not prove a live endpoint map.

`ans1_read_client_start` now arms READY reception before calling
`apple_rtkit_start_ep`, then checks tag 254/status 10 within a three-second
deadline that includes send time. Registration requires this successful start.
Start failure, timeout, wrong tag or abort latch failure without retry. RTKit
boot and endpoint discovery must already have succeeded, and the receive
callback must be attached before start. Tests cover immediate READY delivery
inside the start call and the complete start/register/identify/read/stop path
with mocks. ARM64 compile/link passed; real firmware startup and handshake
remain unverified. No device operation was performed for this change.

The read client can now initialize with zero capacity, register its buffer,
then issue one identify command (cleared 128 bytes, opcode/tag zero). It uses
the same three-second completion deadline and DMA barriers as reads, but
decodes the inline response at command +0x30. Successful decoding sets capacity;
until then reads are rejected. Failed/pending/unformatted responses quarantine
the client without retry, and leave the caller's geometry output unchanged.
An already-known capacity cannot be replaced through another identify call.
Host mocks exercise identify followed by a valid read and seven failure cases.
The ARM64 combined object compiled/linked successfully. Firmware startup and
a real READY/identify response are still unimplemented/unverified.

`ans1_geometry.h` decodes the first 24 bytes of the identify response body
using the AppleTV5,3 16M568 instruction/diagnostic-string evidence in
`../tvos-readonly-analysis.md`. It requires nonzero LBA count, 4096-byte LBAs,
nonzero UserArea formatted state and zero at the word tvOS waits on. Short
responses and failed validation leave the output unchanged. Capacity and
preferred-buffer-size products use u64; the preferred size never determines
capacity. Auxiliary formatted state is reported separately. The read client
calls this parser after completion and a DMA barrier; the parser itself does
not establish firmware compatibility or obtain live geometry.
Host tests cover byte order, truncation, rejected states and maximum u32 counts;
the offline runner now passes 16 suites.

`prepare-core-build.py` regenerates the companion mailbox/RTKit drafts and
stages the block, DMA and read-client sources in `artifacts/ans-core-build`.
It records source/generated hashes and uses the draft RTKit public header.
Building target `ans1_core.o` with the baseline ARM64 kernel successfully
compiles all three objects and links them together. The resulting object SHA256
is `3acb40892d617fcf890ae340ffb700ad72ae2e74d5449adcb819f0bf966641b4`.
`llvm-nm --undefined-only` shows kernel/RTKit dependencies but no unresolved
`ans1_*` references. This is a relocatable compile/link check, not a loadable
driver: no module entry, controller probe, firmware startup or hardware binding
is provided. The manifest records preparation, not successful compilation.

The read client now performs command-buffer registration using its matching
opaque DMA owner. It publishes ownership before sending the buffer address,
waits at most three seconds for tag 253/status 10, then sends tag 0's mapping.
The pinned m1n1 implementation does not wait for a tag-mapping ACK, so success
means that mapping was sent, not independently acknowledged. Reads remain
disabled until registration succeeds. Wrong ownership is rejected before any
send; timeout, wrong reply, send failure or concurrent abort quarantine the
client and retain published DMA. Registration cannot be retried in that state.
Actual-source mock tests cover these cases and ARM64 compilation passed.
The controller must verify READY before invoking registration and route/drain
callbacks correctly. No controller startup, live registration or NAND read has
been performed. The offline runner currently passes all 15 suites.

`ans1_dma.c` owns two coherent 4 KiB allocations, checks command/data address
representability and rejects overlapping page addresses. Allocation failures
unwind unpublished buffers. The opaque owner retains a device reference and
refuses freeing after publication (`-EBUSY`), with no Boolean quiescence bypass.
ARM64 compilation passed. This is intentionally incomplete reclamation: a
verified hardware-quiescence path is required to reclaim published allocations.
A device reference alone does not preserve IOMMU mappings during driver unbind;
the future controller must also manage that lifetime. No device currently calls
this allocator, and it does not configure DMA masks or start hardware.

The read client now has abort/stop operations. Abort quarantines state and wakes
the waiter under the state lock; stop then waits for the request mutex in process
context without holding the state lock. Tests cover abort during submission,
stop before a read and repeated stop, with no subsequent sends. ARM64 compilation
passed. This drains host reading/copying only: callbacks must still be detached
and firmware DMA quiescence verified before freeing context or buffers.

`test_read_client.py` executes the actual client source with deterministic
RTKit/clock/completion mocks. Successful reply copies data and retires the tag;
send failure, no reply through the three-second deadline, and wrong-tag reply
preserve destination bytes and prevent another send. Identical command/data
DMA addresses are rejected. The test passes; real callback concurrency and DMA
visibility are not modeled. No real ANS transaction has been submitted.

`ans1_read_client.c` connects the read encoder and transaction policy to RTKit:
one serialized command, a three-second absolute deadline including send time,
receive-side completion validation, coherent-DMA barriers, and data copy only
after successful completion. Failure quarantines the client without freeing
DMA. Its read function matches the block frontend callback signature.
The ARM64 object compiled; no controller instantiates this client yet. Init
assumes two independently owned coherent 4 KiB allocations, verified geometry,
and completed command-buffer registration; it cannot establish those facts
from pointers. Only call init once on a fresh context, never to recover an
in-flight failed controller. End-to-end fault injection and callback teardown
validation remain required before binding or real NAND reads.

`prepare-block-selftest.py` prepares a synthetic RAM frontend test under
`artifacts/ans-block-selftest`. Only frontend disk/major names change to
`ans1ramtest0`/`ans1ramtest`; the request implementation is identical. The module
checks J42d/T7000, supplies 16 synthetic 4 KiB pages, and deliberately fails
page 15 to test error latching. Pages 0–14 contain byte `(lba ^ i ^ (i >> 8))`.
No controller, DMA, firmware or MMIO interface is used. The combined ARM64
object compiled; module finalization, load/read-only-ioctl/unload tests have
not yet run. Do not treat synthetic data as NAND evidence or include this in
the normal RAM-only boot path.

The block frontend's `set_read_only` callback now rejects clearing read-only
with `-EROFS` and permits reasserting it. Baseline `block/ioctl.c::blkdev_roset`
calls this callback before changing the block-device flag and returns immediately
on error. The request-level rejection of all non-read operations remains in
place independently. ARM64 compilation passed; a live BLKROSET test still
requires an instantiated frontend and has not been performed.

The block frontend now latches any controller read error under its request
mutex; later reads fail without calling the controller, even if it would report
success again. There is no runtime clear/retry interface. The host test verifies
this and unchanged destination data. ARM64 compilation passed. Baseline
`block/genhd.c::__del_gendisk` waits for queue freeze/drain, synchronizes queue
timers and cancels MQ work before return; the controller cookie must outlive
frontend destroy. This is host-request lifetime evidence, not proof of IOP DMA
quiescence after an error.

`test_block_request.py` executes the real request handler with host mocks:
all non-read operation byte values are rejected without controller calls,
misalignment/out-of-range/incorrect segment totals are rejected, callback
failure leaves destination bytes unchanged, and success copies across two
vectors. This passed and is included in the offline runner (12 suites).
Actual queue registration, ioctl read-only overrides, concurrent teardown and
kernel request lifecycle behavior still need runtime tests.

`ans1_block.c` is an unbound block frontend draft. It registers a read-only
disk only when explicitly called with verified 4 KiB-page capacity and a
controller read callback. Its request handler rejects every operation except
read, checks one-page alignment/length/capacity before invoking the callback,
and copies data to the request only on callback success. Queue depth is one;
the callback must finish within three seconds and retain failed DMA buffers
outside the CPU copy buffer. No ioctl/passthrough/write implementation exists.
The ARM64 object compiled, but no client calls create, no disk was registered,
and no runtime block-layer or teardown test has run. Callback lifetime,
read-only override attempts and request fault injection must be validated
before this frontend is enabled. This is not storage acceptance evidence.

OSLOG field-validation tests now pass against the generated buffer helper:
the literal successful reply, unaligned DMA, DMA beyond its 36-bit page field,
and a custom setup returning size beyond the 20-bit byte field. A custom normal
buffer of non-page-multiple size is also rejected. Rejections preserve allocation
records and perform no send. This does not establish that OSLOG is required or
usable on A1625's old AKF protocol; endpoint negotiation remains authoritative.

RTKit shared-buffer replies now check field widths before encoding: normal
buffer address/size fields and OSLOG page-address/byte-size fields reject
truncation with `-ERANGE`, retaining the allocation record. OSLOG DMA addresses
and normal buffer sizes must also satisfy their page alignment requirements.
A host test confirms an unrepresentable normal DMA address causes no send;
all eleven suites and ARM64 RTKit compilation pass. OSLOG-specific fault
injection and a controller-wide fatal-error policy remain pending.

`test_mailbox_receive.py` executes the generated locked/public poll functions
with a FIFO model. A 100-message input returns 64 then 36, with decoded endpoint
and payload order preserved; empty FIFO returns zero and stopped polling makes
no register reads. The modeled lock is released on each path. Eleven host
suites pass. Delayed-work cancellation, real spinlocks and IRQ scheduling are
not simulated by this test.

`test_mailbox_send.py` executes the generated send function with counted MMIO
mocks: stopped/invalid input causes no register access, FIFO-full causes no
write or IRQ/wait operation in either calling mode, and success emits exactly
one expected 64-bit word. All exits release the modeled lock. Ten host suites
now pass. This is sequential control-flow validation, not a kernel concurrency
or device bus-ordering test.

`ans1_queue.h` encodes the pinned m1n1 command-buffer registration format for
one 128-byte command, tag zero. It rejects addresses exceeding the 40-bit field,
unaligned addresses, overflowing allocations and out-of-allocation commands.
The caller must wait for buffer-ready tag 253 before sending tag registration;
the encoder does not send either message. Ownership and DMA quiescence remain
external requirements. Literal wire fixtures and boundaries pass, bringing the
offline runner to nine host suites.

`a1625-ans-draft.dtsi` records the verified firmware reservation and a disabled
polling mailbox node. The mailbox has no guessed interrupts or power-domain
references. No controller node binds it yet. The fragment is not included by
any boot target; `test-ans-draft.dts` is only a syntax fixture and is not a board
DT. Native baseline dtc compiled it without diagnostics. Firmware retention,
reservation handoff before Linux, PMGR ownership and binding schema validation
remain prerequisites for enabling anything. The `no-map` reservation alone
cannot prove the firmware contents survived the earlier boot stages.

`ans1_fw.h` validates up to 32 sorted, non-overlapping firmware segments before
deriving one physical/IOVA interval. It rejects overflow, inconsistent address
translation and any segment outside the supplied reservation; output is
unchanged on rejection. This assumes independently verified ownership of the
entire reservation, including gaps. It does not parse ADT records, verify live
firmware bytes or perform MMIO. The new interval tests and the existing seven
host suites pass through `test-offline.py` (eight suites total).

AKF start/stop now take a mailbox lifecycle mutex, including the cleanup action;
concurrent lifecycle calls cannot overlap PM transitions or cancellation.
Receive callbacks must still never call start/stop, since stop waits for the
polling worker. This supersedes the earlier caller-only serialization requirement.
The baseline mailbox header is now hash-checked before modification. Both ARM64
objects compiled after this layout change and all seven host suites passed;
the host suites do not model this new mutex or kernel scheduling races.

Lifecycle update: AKF send/poll check active under their respective locks and
return `-ESHUTDOWN` without MMIO after stop. Stop clears active, cancels delayed
work, then drains RX and TX lock holders separately before runtime-PM release.
RX and TX are never held together because a receive callback may send. A devm
cleanup action stops AKF before its managed PM/MMIO resources are released.
ARM64 compilation passed. Start/stop serialization by the consumer and callback
restrictions still apply; lockdep/concurrency fault injection is pending.

Polling update: the AKF descriptor now skips both IRQ resource requests and
uses delayed work to poll up to 64 messages per pass, scheduled again after
2 ms (subject to jiffy resolution). Stop clears active and synchronously cancels
the worker before runtime-PM release. Start/stop must be serialized by the
consumer and stop must not run inside the polling callback. Concurrent sends,
external polling and provider removal still need lifecycle protection before
binding. Host polling cancellation is not IOP DMA shutdown.

The mailbox header layout now includes delayed work. Regenerate the mailbox
before RTKit; its generator copies this modified header so structure offsets
agree. Both patches and all clients must be rebuilt together. Earlier notes
below about mandatory AKF IRQ resources are superseded by this polling update.

Run `python windows-native/internal-storage/linux/test-offline.py` from the
repository to regenerate the pinned drafts and execute all seven host test
suites. `artifacts/ans-offline-tests/results.json` records outputs and hashes
of the tested sources and compiler. A previous success is invalidated before
starting. This runner does not compile kernel objects or contact hardware;
passing it cannot satisfy Issue #5's storage acceptance requirements.

No controller driver, DT binding, MMIO access or block device is registered by
these files. They are components for the pending Issue #5 Linux implementation.

The current kernel's RTKit implementation already supports protocol 10 and
its application endpoint base 6 (verified in `rtkit-internal.h`). The pinned
m1n1 ANS client also supports endpoint 5, which this Linux baseline would
classify as an unknown system endpoint; the draft opt-in below addresses this.
Its mailbox implementation in
`drivers/soc/apple/mailbox.c` supports ASC/M3 variants with separate message
and endpoint words, not the old AKF layout. A new AKF transport must preserve
the existing RTKit interface and pack the endpoint into bits 63:56, with data
in bits 55:0, matching pinned m1n1 `rtkit_akf_send/recv`.

`ans1_wire.h` implements that conversion and rejects overflow instead of
silently truncating a message or endpoint. It leaves output unchanged on
failure. `test_ans1_wire.c` covers every endpoint, boundary data, a literal
application wire word, and all forbidden data bits. Passing these tests
proves only the arithmetic conversion, not protocol/IRQ/hardware operation.

Build the native host test with MSYS2 UCRT64 GCC:

```sh
gcc -std=c11 -Wall -Wextra -Werror -O2 \
  windows-native/internal-storage/linux/test_ans1_wire.c \
  -o artifacts/diagnostic-ramdisk-research/windows-tools/test_ans1_wire.exe
artifacts/diagnostic-ramdisk-research/windows-tools/test_ans1_wire.exe
```

Pending integration needs an AKF register backend, verified A1625 interrupt
roles and power lifecycle, bounded RTKit initialization, DMA ownership and
the read-only ASP block driver. Do not bind a device merely to test this codec.

## Draft mailbox backend

`prepare-mailbox-build.py` prepares a separate build directory and
`mailbox-akf-draft.patch` from the hash-checked baseline mailbox source.
The patch requires copying `ans1_wire.h` beside the kernel's mailbox.c.
It adds single-word send/receive, rejects invalid messages before MMIO, and
sets the AKF mailbox enable bits after runtime resume. The resource is the
mailbox window at IOP base + 0x1000, with offsets from pinned m1n1 AKF v1.
Existing descriptors retain the two-word path.
If the AKF transmit FIFO is full, send returns `-EAGAIN` immediately without
writing a message or enabling the send-empty interrupt. This applies to both
atomic and sleepable calls. A future caller must use bounded, scheduled retries
within its absolute transaction deadline; the companion RTKit draft below
adds a per-send retry budget. Other mailbox variants retain their original
wait behavior. The AKF draft still requests both IRQ resources at probe, so
this does not eliminate the need to establish their identities before binding.

The prepared `mailbox.o` compiled for the matching baseline ARM64 kernel.
It was not linked into a boot kernel, loaded, or given a DT node. The draft
compatible `apple,t7000-akf-mailbox` has no deployed node or binding schema.
Probe rejects roots without both `apple,j42d` and `apple,t7000`, and missing,
reversed, unaligned or shorter-than-0x40 register resources before mapping.
AKF receive draining is capped at 64 messages per invocation; existing ASC/M3
draining is unchanged. This bounds the number of callbacks, not their duration
or repeated interrupts. Continued draining requires a verified IRQ retrigger
policy; the cap alone does not prevent an interrupt storm.

This is not hardware-ready: IRQ roles and retrigger policy, stop/DMA
ownership, suspend behavior, and the IOP firmware lifecycle remain unresolved.
This is not a bounded probe implementation. No claim of hardware validation
follows from compilation.

## Single-page read command

`ans1_read.h` encodes only UserArea read (0x10), tag 0, flags 8 and
length 1 into a fully cleared 128-byte command. Layout follows pinned
m1n1 d5a10ac52a6468484854419a6c5130f1d62073eb `ans1.c`:
LBA at 4, length at 8, and a 32-bit DMA page number at 0x30.
It rejects LBA truncation, access outside supplied capacity, unsupported
sector size, unaligned/unrepresentable DMA addresses, interval overflow,
and a page outside the caller's DMA allocation. Failure preserves output.
There is no write or arbitrary-command interface.

Only verified 4096-byte logical sectors are accepted by this initial path;
this is a restriction, **not evidence of A1625's actual sector geometry**.
DMA ownership, address translation, cache ordering, completion/timeouts and
quarantine after a failed command still belong to the pending controller
driver. This encoder alone does not make a device safe to operate or enforce
block-layer read-only behavior. Nothing currently submits its output.

`test_ans1_read.c` passed native GCC with `-std=c11 -Wall -Wextra -Werror -O2`.
It checks a literal command fixture, maximum wire LBA/page values, first
out-of-range values, capacity and allocation edges, overflow, unsupported
geometry, and unchanged output on rejection.

## Completion decoding

`ans1_reply.h` distinguishes startup-ready (tag 254/status 10), command-buffer
ready (tag 253/status 10), and single-tag read completion (tag 0/status 0).
These fields follow the same pinned m1n1 source. Only the exact type-4 word
is classified as a notification. Wrong endpoint/tag, unsupported status,
wrong type and any high reserved bit are rejected. Status 1/2 is a command
error, never successful data. This stricter handling of reserved bits is a
fail-closed draft policy, not a claim that all firmware revisions use them
identically.

The caller must serialize requests, enforce an absolute deadline even during
notifications, reject unsolicited completions and quarantine DMA after timeout
or protocol failure. A late tag-0 reply cannot identify a new request after a
timeout; therefore tag reuse is forbidden until controller/DMA quiescence is
proven. The classifier itself does not implement those lifecycle guarantees.

Native GCC tests passed with warnings as errors: literal startup responses,
all 65,536 low-word read responses, every high reserved bit, endpoint mismatch,
phase mismatch and invalid phase. No hardware operation was performed.

`ans1_transaction.h` adds a serialized request lifecycle with an absolute
monotonic deadline (maximum three seconds, following the upstream timeout).
Notifications do not extend it. Timeout, transport failure, malformed/error
reply and unsolicited completion permanently quarantine this transaction;
there is no retry/reset API. Successful completion must be consumed and
explicitly retired before reuse. Tests cover notification flooding, completion
at the exact deadline, late completion, timer-only expiry, time overflow,
transport failure and successful retirement.

This is a policy component, not an active kernel timer or DMA quarantine
implementation. Integration must supply locking, the timer, DMA barriers,
allocation retention and a verified controller lifecycle. Even after success,
tag 0 cannot distinguish a duplicate old reply arriving during the next read;
the firmware's exactly-once completion behavior remains a hardware validation
requirement. Do not clear the structure to recover a live failed controller.

## RTKit retry draft

`prepare-rtkit-build.py` verifies the baseline RTKit source hash and creates
`rtkit-retry-draft.patch` plus a separate compile directory. Sleepable sends
retry only `-EAGAIN`, sleeping 1–2 ms between attempts against one 500 ms
deadline. Atomic callers receive `-EAGAIN` immediately. The deadline is checked
after sleeping, before resubmission; crash state also stops retries. This
depends on the AKF backend's guarantee that `-EAGAIN` means no message was
enqueued. Other errors are never retried. Endpoint start now propagates the
management send error instead of unconditionally returning success.
Endpoint-map handling also propagates failures of its ACK or system endpoint
starts into `boot_result`, instead of completing initialization successfully.

The ARM64 `rtkit.o` compiled against the baseline. No kernel was linked or
booted. This is a per-send budget, not an overall boot/transaction deadline;
the pending controller must account for it in its absolute deadline. Scheduler
latency can delay return beyond 500 ms. Existing internal buffer/log ACK callers
still ignore some send errors and need a fatal-error/quarantine policy before
hardware use. Runtime fault-injection and concurrent lifecycle checks remain
outstanding; compilation alone does not validate those behaviors.

Shared-buffer requests now reject duplicate ownership records before modifying
them and reject zero-sized requests before allocation. If publishing a new
buffer fails, the helper reports the error and retains its allocation record;
it does not run the error path that clears the record. This is not complete
DMA quarantine: callers still need to stop protocol progress on that error,
and teardown must not release retained buffers until DMA quiescence is proven.
This revision also compiled as ARM64 `rtkit.o`; allocation/send fault injection
remains necessary before integration.

`test_rtkit_retry.py` now extracts the generated send function (rather than
reimplementing it) and runs it with deterministic clock/sleep/mailbox mocks.
Passing cases include persistent FIFO-full through the deadline, success after
two retries, no sleep in atomic mode, no retry on I/O error, crash during sleep,
and refusal of a non-running application endpoint. These host tests verify
control flow only; real scheduling, locking, MMIO and DMA ordering are not
modeled.

`test_rtkit_buffer.py` extracts the generated shared-buffer helper and passed
host fault injection for zero size, allocation failure, publication timeout,
duplicate request with unchanged ownership record, and successful publication.
The literal system-log reply word is checked. These cases cover the default
allocation path; custom `shmem_setup`, OSLOG encoding, asynchronous DMA and
teardown are not modeled and still require separate validation.

The RTKit draft adds `apple_rtkit_ops.ans1_endpoint5`: only an explicitly opted-in
client uses application base 5 under protocol 10. Defaults remain 6, and protocol
11/12 remains 0x20. This lets both early and worker receive paths deliver EP5
to the application rather than treating it as an unknown system endpoint.
No client currently enables it. The public ops layout changes, so all clients
must be rebuilt; do not load this against an existing kernel/module ABI.
The compile-only directory substitutes its local modified public header;
the patch modifies the real public header path. ARM64 compilation passed.

HELLO negotiation now rejects a reversed firmware version interval and
propagates HELLO-reply transmission failure to `boot_result` while waking the
endpoint-map waiter. This avoids waiting for an endpoint map after a failed
negotiation send. HELLO and endpoint-map handlers now retain the first negative
`boot_result`: later negotiation messages return without changing it. Those
handlers run on the existing ordered RX workqueue. Reinit resets the result
only after mailbox stop and workqueue flush. ARM64 compilation passed.
This latch covers negotiation failures, not a complete startup state machine:
out-of-order messages before failure, boot-wait timeouts, power ACKs and DMA
quiescence remain unresolved. Reinit's existing DMA-free behavior is still
unsafe to invoke on an unquiesced ANS controller.

`test_rtkit_hello.py` passed against the generated HELLO function with mocked
transport/completions: protocol 10/11/12 with opt-in both on and off, literal
negotiated reply words, reversed/unsupported intervals, transmission timeout,
and a later HELLO preserving the first error without another send or wake.
It does not exercise endpoint-map dispatch, concurrent boot waiters, or hardware.

Endpoint-map handling rejects an unnegotiated/unsupported protocol version
with `-EPROTO` before changing the endpoint bitmap or sending an ACK. Reinit
clears `version` and restores the same pre-HELLO application threshold as init,
after RX work has been flushed. This prevents stale version state from accepting
an endpoint map before a fresh HELLO. ARM64 compilation passed; full boot
message-order fault injection remains pending.

The HELLO host test now also executes the generated endpoint-map handler:
pre-HELLO map rejection without bitmap mutation/send, retained failure on a
later HELLO/map, map-ACK failure, system endpoint start failure, and a successful
protocol-10 map all passed. Bitmap and start operations are mocked; this does
not yet cover multipart protocol-11/12 maps or asynchronous power-state traffic.
