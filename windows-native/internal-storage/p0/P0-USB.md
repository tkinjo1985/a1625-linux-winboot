# P0-USB: transport only

The previous session ended at Windows `SetCommState` error 31, before the first
proxy packet. It was **not an ANS bring-up failure**. No USB capture was collected;
the unconditional CDC SET_LINE_CODING STALL in the actually used source is a
code-level candidate, not a measured bus-level cause. Driver corruption is not
established. HostReadOnlyExperimental and RamOnly defaults remain unchanged.

## Preserved evidence

`artifacts/p0-usb/before/` preserves the previous manifest, complete P0 patch,
payload and `smoke.py`, with SHA-256 in `hashes.json`. The actual failed host
invocation was inline Python from the task, **not smoke.py**: it imported
`m1n1.proxy` and constructed `UartInterface('COM6')`; construction failed before
NOP/get-base/get-bootargs/readmem. There was no on-disk script or execution-time
hash of that inline invocation. Do not present the saved smoke.py hash as the
hash of the program actually executed. The task transcript retains the inline
invocation. New probes use a real, hashed file.

## CDC change

The pinned source and applied P0 source had identical `usb_dwc2.c` before this
change. VID/PID remain 1209:316D; configuration declares management/data pairs
0/1 and 2/3. No descriptor, driver, ANS firmware or ANS safety policy was changed.

SET_LINE_CODING now accepts only 0x21, control interface 0 or 2, wValue 0,
wLength 7. It arms OUT in the same SETUP-completion handler invocation; it does
not defer the timing-sensitive receive to a later poll. The existing DMA buffer
receives the data. A DMA read barrier and DOEPTSIZ0 residual check precede the
seven-byte commit. Short transfer stalls the status IN; a valid transfer sends
an IN ZLP and rearms SETUP on completion. GET returns the saved seven bytes with
validated request fields. New SETUP invalidates the old receive destination;
simultaneous stale IN completion cannot advance the old state. USB reset clears
pending receive state, resets line coding and drops DTR readiness. Unknown OUT
completion no longer receives a success status. DTR ON remains required; repeated
DTR ON does not rearm a second bulk OUT. No timing-sensitive printf was added.

`test_usb_cdc.py` executes the actual request/completion and EP0 interrupt bodies
with mocked registers: valid interfaces, all wrong request-type bytes, wrong
value/length/interface, short OUT, GET, DTR edges, interrupted SETUP, simultaneous
IN completion, immediate receive arming and status-to-SETUP progression. These
tests do not establish actual DMA timing or bus behavior. USB reset hardware
behavior is not covered by the mock tests. The actual software-state reset prefix
is tested with a pending receive: both line codings reset, destinations are
discarded and both DTR-ready flags clear. Endpoint-abort waits and reset MMIO
effects remain outside this mock's coverage. Native payload build passes.

## Probe and remaining physical gates

`Collect-TransportInventory.ps1` only enumerates 1209:316D candidates and records
PnP instance, interface (if explicit), location, product/serial, driver and
status. It does not open a COM port. The old session's inventory was saved:
usbser/OK, expected m1n1 product, but **no MI interface number in the instance**.
Do not fill this missing field by assuming COM6 or interface 0.

The collector currently derives interface number only from an `MI_xx` instance
suffix. Its absence is therefore a limitation of this evidence, not proof that
the device lacks interfaces or that usbser is broken. The source device descriptor
uses class/subclass/protocol 02/00/00. Microsoft's documented automatic composite
parent matching uses class 00 or EF/02/01; see
https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/enumeration-of-the-composite-parent-device .
This explains why expecting an MI child unconditionally is unjustified; it does
not identify which CDC pair the current usbser instance selected. Do not change
the descriptor or drivers merely to make the inventory predicate pass. A live
configuration/selected-interface observation is needed to resolve that mapping.

Session `artifacts/p0-usb/session-20260910-b` reached Pongo and transferred the
revised payload successfully. Its m1n1 enumeration matches the DFU connection
location and expected product/VID/PID, with usbser/OK, but still lacks an MI suffix.
No COM open or proxy packet was attempted in that session. The stage records hash
the actual saved `Invoke-UsbBootStage.ps1`, helper, executable and payload inputs.

USBHUB3 ETW Rundown (keyword 0x8000, two seconds, stopped afterward) supplied the
live configuration descriptor without opening COM or reconnecting. The event was
selected by its target VID/PID device-interface path; its 97 descriptor bytes are
saved as `live-configuration.bin` with hashes in `descriptor-hashes.json`. It lists
control/data interfaces 0/1 and 2/3, CDC unions 0→1 and 2→3, and endpoint sets
81/02/83 and 84/05/86, matching this source. Hub connection information reports all
six pipes open. Neither observation uniquely identifies the COM-to-pair binding.
The ETL contains other devices' rundown metadata too; keep it local. This was a
configuration snapshot, not a capture of the earlier SetCommState failure.

Later approved COM-open captures in sessions b and d show A1/21, wIndex 2,
wLength 7 (GET_LINE_CODING). Session b records unsuccessful completions after
approximately 30 seconds and an OS resend. Session d's host watchdog stops the
open after 15 seconds. Neither session sent P_NOP or ANS requests. SET_LINE_CODING
was not observed. These observations do not establish which device EP0 stage
stalled. The control-read status CNAK correction (08399ae) did not produce a
successful COM open in session d.

The proxy startup wait calls iodev_handle_events before can_read; its USB wrapper
does not gate handle_events on DTR. Thus a direct DTR-before-EP0 circular wait is
not present in that call path. The mock test now explicitly exercises the observed
interface-2 GET through IN completion, OUT status and rearmed SETUP. It passes;
the test cannot prove the hardware delivered those interrupts or DMA data.

Sessions e/f failed before Pongo during checkm8 re-enumeration. Inspection of the
actual generated `artifacts/openra1n-build/openra1n.c` shows serial acquisition
already temporarily raises the transfer timeout to 500 ms, then restores the
checkm8 timeout. A short-circuit expression combines device-descriptor transfer,
string-descriptor transfer and length checks, so the generic serial-read error
does not identify which failed. The wrapper deliberately stops on that error
before another reopen/attempt. Do not claim a 5 ms descriptor timeout caused these
failures, remove the identity gate, or silently allow automatic exploit retries.
Further diagnosis needs per-transfer status/length evidence, not another blind
DFU repetition. No host executable, retry behavior or driver was changed for
this inspection.

Session `artifacts/p0-usb/session-20260910-g` used the diagnostic host build and
stopped at the Checkm8 gate without an automatic retry. The exact failing
transfer was the first 18-byte device descriptor request (type 1, index 0),
which returned libusb `-7` after the temporary 500 ms descriptor timeout. Thus
the generic serial-read message in this run did not describe a failed string
descriptor transfer. The identity and connection-location gates passed before
the open, but checkm8, Pongo, payload, COM configuration and P_NOP were not
executed. This result neither exercises nor invalidates the CDC fixes. A new
physical attempt requires a fresh session record and the existing explicit
approval; do not reuse session g or retry automatically.

After a manual return to clean DFU, approved session
`artifacts/p0-usb/session-20260910-h` passed the initial device and string
descriptor reads and the exact CPID/BDID/ECID checks. Checkm8 stages 1 and 2
reported success. The following re-enumeration then timed out on its 18-byte
device descriptor request after 500 ms, before `TRIGGER_HANDOFF`. The wrapper
therefore marked Checkm8 failed and did not run Pongo, payload, COM or P_NOP.
No automatic retry was made. Unlike session g's failure on the initial open,
session h establishes a repeated post-stage-2 re-enumeration failure point;
it still provides no CDC hardware evidence.

The host build now retries only a failed identity descriptor transfer on the
same already-open libusb handle: at most two retries, with 250 ms between
attempts. It does not reopen or reset the device and cannot repeat a checkm8
stage. The existing wrapper still stops on failure after those bounded attempts,
so it does not enable blind exploit retries. CPID/BDID/ECID validation remains
after complete device and serial descriptor acquisition. The native build with
this change passes; hardware behavior is not yet tested.

Approved session `artifacts/p0-usb/session-20260910-i` exercised all three
same-handle attempts on its initial device descriptor read; each returned
libusb `-7`. No exploit stage ran. This proves same-handle settling alone was
insufficient for that occurrence. The host path now permits close/reopen only
while identity acquisition is incomplete, capped at three opened handles. Each
handle still has only the original attempt plus two settled descriptor retries.
Exhaustion emits `DFU_IDENTITY_REOPEN_LIMIT` and stops before an exploit stage.
The stage wrapper continues to stop immediately on target-identity rejection,
the reopen limit or `TRIGGER_HANDOFF`; generic transient descriptor errors no
longer preempt the bounded reopen path. The native build passes, but this second
bounded behavior is not yet hardware-tested.

Approved session `artifacts/p0-usb/session-20260910-j` exercised that reopen
bound. All three opened handles exhausted all three same-handle device
descriptor attempts: nine 18-byte reads, each returning libusb `-7` at 500 ms.
The explicit `DFU_IDENTITY_REOPEN_LIMIT` stopped the process before any checkm8
stage. Reopening is therefore not a sufficient recovery for the device state
present in session j, and increasing these bounds is not justified. PnP
presence alone does not establish a responsive DFU EP0. A manual physical
return to DFU and a fresh read-only responsiveness check are required before
another approved device-affecting session. Pongo, payload, COM, P_NOP and ANS
requests in session j were zero.

Comparison with the preserved successful Checkm8 logs from sessions b and d
shows that the reset/reopen sequence itself is not new: both earlier runs
completed stages 1, 2 and 3 and reached `TRIGGER_HANDOFF`. The diagnostic build
added synchronous log output after every successful device and string
descriptor read, despite its earlier comment claiming no timing change. Since
these reads occur between timing-sensitive checkm8 stages, the success-path
logging is now removed. Descriptor metadata is emitted only for an error or
short transfer; bounded failure retries and all target gates remain. This
restores the prior success-path instruction/I/O behavior except for failure-only
branches. Hardware retest requires a fresh manual DFU entry because session l
left the current instance unresponsive after stage 2.

Approved session `artifacts/p0-usb/session-20260910-m` then completed Checkm8
stages 1, 2 and 3 plus the patch/trigger, and the wrapper stopped at
`TRIGGER_HANDOFF` as designed. The same CPID/BDID/ECID and connection location
re-enumerated with `YOLO:CHECKRA1N`, PnP status OK and service `WINUSB`.
The separately approved Pongo stage was rejected before creating `Pongo.json`
or starting openra1n because the wrapper required `libusbK` while YOLO was
still on `WINUSB`. Subsequent inspection of the preserved successful two-phase
procedure established that WinUSB is only the parked handoff state: the exact
YOLO 05ac:1227 instance must be rebound to `libusbK` before `--upload-only`.
The temporary Pongo=`WINUSB` gate was incorrect and is reverted. Every boot
stage requires `libusbK`, while clean/YOLO identity checks remain stage-specific.

Two separately approved Pongo calls were then rejected by the location gate
before creating `Pongo.json` or starting openra1n. The saved and current paths
were textually identical. Reproduction under the actual Windows PowerShell 5.1
host showed the cause: piping the deserialized JSON array back through
`ConvertTo-Json` produced a wrapper object with `value` and `Count`, while the
live `System.String[]` serialized as a JSON array. The gate now casts both sides
to `string[]` and compares count, order and exact strings with `Compare-Object
-SyncWindow 0`. That expression reports equality for the current two saved
paths under Windows PowerShell 5.1. The gate is not weakened to set comparison,
and neither rejected call transferred Pongo data.

After the location fix, the approved Pongo process passed the temporary WinUSB
gate but repeated `libusb_open(05ac:1227)` calls returned Input/Output Error,
matching the vendored release note. It transferred no Pongo data. The child
openra1n remained alive after its parent execution cell ended; the exact
verified PID was stopped, and the stage record finalized as failed. No retry
followed. A new Pongo attempt requires an explicitly approved driver rebind of
only this YOLO instance, with its current driver recorded for rollback first.

After that failed process was stopped, a later read-only PnP check found the
same YOLO instance already rebound externally to `libusbK` 3.1.0.0 using
`oem149.inf`; this task did not run a driver-change command. The earlier WinUSB
service and Apple provider had been observed, but its version and INF were not
captured and are recorded as unknown rather than inferred. The current and
prior observations plus exact-instance rollback instructions are saved in
`session-20260910-m/driver-before-pongo.json`. The Pongo stage gate is restored
to require `libusbK`.

After a manual physical return to DFU, read-only probe
`artifacts/p0-usb/dfu-readonly-20260910-k` performed exactly one standard
control-IN request for the 18-byte device descriptor. It returned all 18 bytes
within the 500 ms transfer window. The probe made no configuration change,
interface claim, USB reset, control-OUT request or checkm8 call. This establishes
that the fresh DFU EP0 was responsive before the next device-affecting attempt;
it does not establish continued responsiveness across checkm8 re-enumeration.
`Build-DfuDescriptorProbe.ps1` now rebuilds this minimal probe, rejects the
forbidden mutating libusb tokens, and records source/executable/libusb hashes
and the fixed operation count in a build manifest.

`transport_probe.py` requires a reviewed identity bound to the new boot, then
re-enumerates and compares it before open. Incomplete/ambiguous identity is a
no-send failure. If Windows again exposes no explicit interface, descriptor /
driver-interface mapping evidence is still needed; the current probe deliberately
does not infer it. Save enumeration and stop if it cannot be established.

The probe creates logs before open; uses 115200 8N1, no flow control, DTR ON,
finite read/write timeouts and a three-second/64 KiB receive limit per request.
It sends only three fixed P_NOP frames, validates response framing/checksum and
statuses, and stops on the first failure. No reconnect/retry or m1n1 imports.
Finally closes only the host handle; it never calls ANS shutdown. Fault injection
verifies open-error persistence and exactly three P_NOPs on mock success.

Before a physical test, manually power-cycle the previous session, then use the
existing identity-gated DFU/Pongo path once, retaining connection-location
evidence across enumeration. Do not automatically reboot, change drivers or
run smoke.py. Include source/patch/manifest/payload/probe/inventory-script hashes
in the session evidence. `preflight_verified` remains false.

Current result: **USB transport not yet validated on hardware**. Correct interface
binding, COM open/configuration and real P_NOP response remain unconfirmed.
ANS initialization/NAND read requests in this work: zero. No NAND or DMA-stop
claim follows from these USB tests.

Approved session `artifacts/p0-usb/session-20260910-n` opened the same CPID
7000/BDID 34/ECID and connection location through `libusbK`. The uploader
reported all 135,598 Pongo bytes sent and Windows then enumerated 05ac:4141 as
PongoOS 2.6.3 on that location. The payload uploader reported 1,163,264 bytes
uploaded and `bootm` sent; Windows enumerated the expected 1209:316D
`m1n1 uartproxy v1.6.0-137-gd5a10ac-dirty` through `usbser` as COM6 on the same
location. Both wrapper records nevertheless say `failed` because the bounded
process returned a null exit code. Preserve those records as the actual wrapper
result. The wrapper now records the exit code but determines these two stages
from the completion message plus exact post-stage USB identity, service, product
and location checks.

The session-n COM-only probe opened no proxy protocol and sent no P_NOP, ANS or
NAND request. `Serial.open()` did not return within 30 seconds, so the host run
was terminated and its exact residual `trace_open.py` process was stopped. Its
pre-open record still says `com_configured: false`. This repeats the observable
COM-configuration hang with the revised payload but, without a trace from this
attempt, does not establish which control request or EP0 phase failed. Do not
claim SET_LINE_CODING hardware success from this session and do not send P_NOP
until COM configuration has completed.

`Invoke-TracedComOpen.ps1` is the next-session diagnostic wrapper. It accepts
only one currently present 1209:316D m1n1 identity with `usbser`, expected
product and unchanged connection location. It starts the USB UCX ETW provider,
runs exactly one `trace_open.py` COM-only attempt, stops that exact child after
the 5--30 second bounded deadline, and always stops and converts the trace.
The wrapper records zero P_NOP, ANS and NAND-read requests and refuses an
existing output directory, so a failed session cannot be silently repeated.
