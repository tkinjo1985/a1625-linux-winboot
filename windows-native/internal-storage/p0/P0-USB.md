# P0-USB: transport only

The current measured boundary is Session v: standard enumeration, the first
GET_LINE_CODING, DTR=0 and SET_LINE_CODING all completed successfully on the
Windows host, then the immediately following GET_LINE_CODING stalled with zero
bytes. The host-completion-to-dispatch interval was about 5.2 microseconds; the
second GET dispatch-to-STALL-completion interval was about 8.919 milliseconds.
Neither interval exposes the device's internal interrupt order. COM open and
P_NOP remain unverified, and ANS initialization/NAND access remain unexecuted.
HostReadOnlyExperimental and RamOnly defaults remain unchanged.

Historically, the first recorded session stopped at Windows `SetCommState`
error 31 before the first proxy packet and had no USB capture. That historical
observation remains preserved below, but its earlier “SET_LINE_CODING not
reached” boundary does not describe the current Session v build.

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

Approved trace session `artifacts/p0-usb/session-20260910-o/com-trace` made one
bounded COM-open attempt against that same already-running session-n payload.
UCX recorded one pending CDC `GET_LINE_CODING` control transfer
(`bmRequestType=0xA1`, `bRequest=0x21`, `wIndex=2`, `wLength=7`, URB
`0xFFFFE20A029A6FA8`) and no matching completion. It recorded zero
`SET_LINE_CODING`, P_NOP, ANS and NAND-read requests. Because this was the
already-wedged boot rather than the first COM open after a fresh payload boot,
it identifies the outstanding request but does not independently establish
that every fresh boot fails at the same point. The ETL SHA-256 is
`BB88FA19C4843ED1C0A1320143ED159D712E96C7A138800BBED7A8748DCB57A8`; the
converted XML SHA-256 is
`49592B8F4D229396E73113545013942942F319D4BA0E7E62BCBE915B6149B8FD`.

Source inspection also found that the P0 DWC2 proxy iodev still selected CDC
pipe 0, while Windows binds COM to management interface 2 and data interface 3,
which are CDC pipe 1. The `ANS1_P0` build now selects
`iodev_usb_dwc2_sec_ops`; non-P0 builds retain pipe 0. This fixes the later
P_NOP data path but is not claimed to fix or validate the controller-wide EP0
`GET_LINE_CODING` completion. The rebuilt P0 payload SHA-256 is
`A3ACCAB2E941F666B4B8863EB7FFA4F775FD3D920A972315792DB56C067A0DEC`, and the
reproducible patch SHA-256 is
`2548A6515311F0CFABC35AC2DCFE23A3564B2E030212CB59CF4FBC827BB1373E`. Symbol
inspection of the final P0 `usb.o` found only the DWC2 pipe-1 proxy operations.
At that point the device still contained the older payload; session p below is
the first hardware exercise of this build.

## Session p: fresh-boot result after the pipe-1 change

Approved session `artifacts/p0-usb/session-20260910-p` ran one device-affecting
stage at a time against the owned A1625. The Checkm8 stage verified CPID 7000,
BDID 34, the configured ECID, `libusbK`, and the saved physical connection
location, then completed with status `passed`. Its record SHA-256 is
`1246379FC78C5B47E54C033E342EDF7A6F7B6864A597F3511FFA7C4C6300CF52`.

The first Pongo call was rejected by the pre-transfer driver gate because the
YOLO instance still reported `WINUSB`; it transferred no Pongo data and was not
automatically retried. After the user changed that exact instance to
`libusbK`, a new explicit approval was obtained. The one approved retry passed,
and PongoOS 2.6.3 enumerated as 05ac:4141 with the same CPID, BDID, ECID and
connection location. The Pongo record SHA-256 is
`FDE8D496BB2EEAF2E7DFA47621921BCD6EDFB29992D063113B8FAAF6294C2388`.

The payload stage verified the manifest, source revision, patch and binary,
then RAM-booted the pipe-1 P0 build. Windows enumerated 1209:316D through
`usbser` as COM6 with product `m1n1 uartproxy v1.6.0-137-gd5a10ac-dirty` on the
same connection location. The payload SHA-256 was
`A3ACCAB2E941F666B4B8863EB7FFA4F775FD3D920A972315792DB56C067A0DEC`; the
payload-stage record SHA-256 is
`186C0EDE9ACB7A05A1D5F92671BB66591DA8CBF60B86D22AE358A976001624AF`.

Before any proxy request, the fresh enumeration was saved to
`before-com.json`. One ETW-traced COM-open attempt was then made with a
15-second host deadline. `Serial.open()` did not return, the exact child was
stopped and confirmed stopped, and no retry occurred. UCX recorded the fresh
boot's first CDC request as `GET_LINE_CODING` (`bmRequestType=0xA1`,
`bRequest=0x21`, `wValue=0`, `wIndex=2`, `wLength=7`, URB
`0xFFFFE209F9E86FA8`). Its completion arrived about 30 seconds after submission
with status `0xC0010000`, transfer length zero. No `SET_LINE_CODING` request was
issued. The ETL SHA-256 is
`C9848216545F4C0AD0981EDE10A97C818F6338CBC0BD0CBC7AA82508A5D799DA`; the XML
SHA-256 is
`9083871099B58E017C35F1CFB1626B61CB056C963353821172073C0BB582D506`.
The COM-session and analysis record SHA-256 values are respectively
`3A8208D0E4D49F9D3F3FC46E16E3E8F6C9EF81AA6D630A56F1252E43E52E919C` and
`9D0A57371E431A66B7149AC3BC48B7FDAA2C99E6BC14F8F43E4E61DE6C54867A`.

This fresh-boot trace establishes that selecting pipe 1 did not resolve the
EP0 control-IN failure. It does not establish whether the device failed to
consume the SETUP packet, failed to arm EP0 IN, or armed DMA but failed to
complete it; those alternatives remain hypotheses pending further
instrumentation. `SET_LINE_CODING` handling therefore remains untested on
hardware because Windows never advances to that request. P_NOP was not sent,
so its pipe-1 data path also remains unvalidated on hardware.

### Current boundary and next work

Completed in session p: Checkm8, PongoOS RAM boot, P0 m1n1 RAM boot, exact
post-stage identity/location checks, and one bounded traced COM-open attempt.
Not completed: successful COM configuration, hardware `SET_LINE_CODING`, or a
normal P_NOP response. ANS initialization, NAND read/write and persistent
storage operations were not executed; their request counts remain zero.

Do not reuse the failed COM trace directory or repeat the current boot's COM
open. The next device session requires a reviewed EP0 diagnostic/fix, a new
payload hash, a manual clean DFU entry and fresh approval. Keep the same
identity, location and artifact gates. Stop after COM configuration and three
validated P_NOP responses; do not proceed to ANS initialization or NAND access.

## Proposed EP0 reachability diagnostic (review required)

This section describes a prepared diagnostic build only. It has not been
transferred to hardware and does not change session p's conclusion. In
particular, the pipe-1 change is not established as a fix, and hardware has not
reached `SET_LINE_CODING`.

### Actual GET path

For the observed `A1/21, wValue=0, wIndex=2, wLength=7` request, DWC2 places the
SETUP packet in the logical EP0 OUT DMA buffer. `usb_dwc2_handle_interrupts_ep`
handles `DWC2_DOEPINT_SETUP`, performs `dma_rmb`, clears EP0 stalls and calls
`usb_dwc2_ep0_handle_setup`. The class dispatcher calls
`usb_dwc2_ep0_handle_class`, maps interface 2 to pipe 1, validates the complete
request tuple, points `ep0_buffer` at pipe 1's seven-byte line-coding value and
sets `DATA_SEND`.

The same interrupt pass calls `usb_dwc2_ep0_handle_xfer_not_ready`, which calls
`usb_dwc2_ep0_start_data_send_phase`. That copies seven bytes into the fixed
EP0 IN DMA buffer; `usb_dwc2_ep_hw_send` executes `dma_wmb`, writes DIEPDMA0 and
DIEPTSIZ0, then enables EP0 IN with CNAK. An EP0 IN transfer-complete interrupt
passes `DATA_SEND_DONE` through `usb_dwc2_ep0_handle_xfer_done`, changes state to
`DATA_RECV_STATUS`, and arms one EP0 OUT packet for the host's zero-length
status phase. Its OUT completion changes the state back to setup reception and
arms EP0 OUT for the next SETUP.

### Fixed observation record

The proposed `ANS1_P0`-only code records one byte in RAM. Each checkpoint is a
single OR operation; it adds no synchronous printf, allocation, retry or wait:

| Bit | Value | Device observation |
| --- | ---: | --- |
| 0 | `0x01` | the exact target SETUP was visible after `dma_rmb` |
| 1 | `0x02` | the validated GET handler was entered |
| 2 | `0x04` | the seven-byte EP0 IN transfer was armed |
| 3 | `0x08` | EP0 IN transfer-complete was handled |
| 4 | `0x10` | EP0 OUT status reception was armed |
| 5 | `0x20` | EP0 OUT status completion was handled |
| 6 | `0x40` | a subsequent SETUP superseded/followed the target GET |

The normal unit-test path reaches `0x3f` at status completion and `0x7f` when
the next SETUP arrives. Values are cumulative; an unexpected non-prefix
combination is treated as an instrumentation/state anomaly rather than forced
into one of the four hypotheses.

### Recovery without COM, proxy or UART

The byte is exposed only in the P0 diagnostic build as unadvertised USB string
descriptor index 4, formatted as fixed `P0Ehh`. `Read-Ep0Trace.c` first queries
the parent hub connection and refuses anything except the current 1209:316D
device. It then performs exactly one standard control-IN
`GET_DESCRIPTOR(String, index 4, lang 0x0409, length 12)` through
`IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION`. This path opens the parent USB
hub, not COM, and sends no proxy, P_NOP, ANS or NAND command. The hub instance
and connection port must be derived from the already-reviewed identity and
location record; they must not be guessed.

The diagnostic descriptor request is itself a new SETUP. If the target GET has
entered its handler, its arrival records bit 6 before the snapshot is formatted. The
existing new-SETUP handling is intended to let it supersede a stuck transfer.
This recovery path is not yet hardware-validated. If the hub request fails or
returns malformed data, no device-side reachability conclusion is allowed;
host ETW alone still cannot identify the internal checkpoint. Do not fall back
to an unverified UART, COM/proxy, a USB reset, driver replacement or automatic
retry. `Invoke-Ep0TraceRead.ps1` is the only future entry point: it enforces the
saved InstanceId, 1209:316D, `usbser`, product, parent hub and exact ordered
location paths; derives one connection port from that reviewed location;
verifies source, executable, manifest and identity hashes; refuses an existing
output directory; and records one bounded attempt. Do not invoke the C helper
directly.

### Interpretation of one future trial

After exactly one fresh COM-open attempt and exactly one trace-descriptor read:

| Returned trace | Supported conclusion |
| --- | --- |
| `0x00` | the exact target SETUP was not consumed by the instrumented handler |
| `0x01` | SETUP was observed, but the validated GET handler was not reached |
| `0x43` | GET handler ran, but the seven-byte IN was not armed; bit 6 is the diagnostic read itself |
| `0x47` | IN was armed, but no IN completion was handled; bit 6 is the diagnostic read itself |
| `0x4f` | IN completed, but OUT status reception was not armed; bit 6 is the diagnostic read itself |
| `0x5f` | OUT status was armed, but its completion was not handled; bit 6 is the diagnostic read itself |
| `0x7f` | GET including OUT status completed and a later SETUP was seen |

A successful Windows GET control transfer is also required before claiming
GET success. `0x7f` with a failed host transfer indicates disagreement
that requires investigation, not success. Only after COM configuration itself
succeeds may the existing bounded probe send its three P_NOP requests.

### Prepared difference and host-only verification

The reproducible patch adds only the P0-only byte/active flag, seven checkpoint
ORs and string index 4. The recovery helper source is
`Read-Ep0Trace.c`. The diagnostic patch SHA-256 is
`FEBF60EE6B74100E38ED91D73A032C94BFCB570E48C17AABBE78DCFE07A348FF`; the
unrun diagnostic m1n1 binary SHA-256 is
`314022A8732FD3343F5281001CBFD1A59A39AC518B38B5240B0AB00ACB104979`.
The helper source and locally built helper SHA-256 values are respectively
`CAC6512096B1B90A7606D00A4EDC39114CAF1E9D3797E9EF8B7D0D965FC28563` and
`9FDA3295F53DE5C24DD6F30ACAC716CB599AEF537308CFC87F476288C41512AA`.
The guarded wrapper and reader-manifest SHA-256 values are respectively
`58C16A52B2EB5AA3E1AFA0929CEF0723819DEFD22CCED5899C45ED2767CC9BAA` and
`45346C9C43E8B7BC089C9BF4824328B417895D943022A6691544BB08A4EA662F`.

The full P0 build completed with only the pre-existing linker placement warning.
All thirteen existing P0 host tests passed; the CDC test executes the actual
instrumented functions and verifies the `0x3f` then `0x7f` sequence. The helper
build passes GCC 16.1 with `-std=c11 -Wall -Wextra -Werror -municode`. No helper
or diagnostic payload was run against the device.

`test_ep0_trace_reader.py` additionally verifies the exact single descriptor
control-IN, absence of COM write/reset/libusb/proxy operations, complete live
identity/location/hash gates, five-second one-attempt bound, zero P_NOP/ANS/NAND
counts and reader-manifest hashes. This is a host-side policy test only; it does
not establish that the hub IOCTL can recover the descriptor after a live EP0
failure.

Review must resolve the diagnostic record, hub-IOCTL recovery assumptions and
one-trial interpretation before a new approval is requested. The future trial
retains the current identity, location, artifact and one-stage-at-a-time gates.
It ends after COM plus three valid P_NOP replies at most; ANS initialization and
all NAND access remain out of scope.

## Session r: diagnostic recovery result

Approved session `artifacts/p0-usb/session-20260910-r` passed Checkm8, PongoOS
RAM boot and the hash-bound diagnostic m1n1 RAM boot. Every stage retained the
same A1625 CPID/BDID/ECID and ordered connection location. The payload was
exactly
`314022A8732FD3343F5281001CBFD1A59A39AC518B38B5240B0AB00ACB104979`.

The one fresh ETW-traced COM open again failed. UCX recorded exactly one
`GET_LINE_CODING` (`A1/21`, `wValue=0`, `wIndex=2`, `wLength=7`) followed about
30 seconds later by a zero-byte `0xC0010000` completion. It recorded no
`SET_LINE_CODING`, P_NOP, ANS or NAND request. The ETL and XML SHA-256 values are
`AD0F9F86B7931DEA905DFDA99D9B733ABE6ABA2B683DD2C784584BD359C0F07B` and
`688217511CDF84AA1960352845AEF6836B4024F50EF15B3A772D9D1713807868`.

The first attempted trace-reader launch was interrupted before its output
directory or process existed, so it performed no device request. After the
user supplied a new comprehensive authorization, filesystem and process checks
confirmed that absence. One new trace read was then run through the guarded
wrapper. All identity, parent-hub, location and artifact gates passed, and the
helper made its one allowed string-descriptor request. That request did not
return within five seconds; the exact child was stopped and no retry occurred.
Its stdout is empty. Stderr contains only a truncated start of the helper's
failure message and is not interpreted as a device result. The session record
SHA-256 is
`2DA423132E9C65697D07E48FE95F9950318638D50D9B5017C4A3A6CF63D78299`.

No `P0Ehh` value was recovered. Consequently none of the four internal
reachability hypotheses is resolved by session r. In particular, ETW does not
prove that the device consumed SETUP, entered the GET handler, armed IN, or
handled status. The post-failure index-4 read design is not a usable recovery
channel for this observed failure and must not be retried or described as
validated.

The next diagnostic must establish its recovery channel while EP0 is healthy
and arrange an autonomous, bounded report after the failing GET, rather than
depending on a new request to the already-unresponsive EP0. One candidate is a
P0-only pre-COM arm request followed by a bounded soft disconnect/re-enumeration
that exposes the frozen byte in an advertised descriptor. That is only a design
candidate: its timing, controller-reset behavior, identity changes and safety
gates require host-only review and tests before another hardware approval.
No further hardware operation is authorized by this paragraph.

## Session s preparation: armed one-shot EP0 report (not executed)

This section is a host-only review and build result. Session r remains the last
hardware evidence. No DFU transfer, COM open, USB request, disconnect or
re-enumeration was performed while preparing this section.

### Code review and viability conditions

The candidate is viable only as a bounded P0 diagnostic, not as a guaranteed
recovery facility. The exact GET path remains
`usb_dwc2_handle_interrupts_ep` (SETUP after `dma_rmb`) ->
`usb_dwc2_ep0_handle_setup` -> `usb_dwc2_ep0_handle_class` ->
`usb_dwc2_ep0_start_data_send_phase` -> `usb_dwc2_ep_hw_send`; its IN
completion runs through `usb_dwc2_ep0_handle_xfer_done`, which moves to
`DATA_RECV_STATUS`, and `usb_dwc2_ep_hw_recv` arms the OUT status. The OUT
completion starts the next setup phase.

A. Arm is confirmed only by a successfully returned, checksum-valid `P0E2`
index-4 descriptor with `VALID|ARMED`, a nonzero boot ID and generation 1. PnP
enumeration alone is not arm evidence. If that read fails, COM must not open.

B. The 45-second report deadline starts at arm and is independent of target
GET recognition. Thus a valid frozen trace of zero distinguishes “armed but
target SETUP not observed” from failure to arm.

C. `usb_dwc2_handle_events` previously called an interrupt handler containing
a `while (1)` loop, while reset-time `usb_dwc2_ep_abort` contained three
unbounded waits. The P0 build now polls the deadline before and after the event
call and at the top of every interrupt-loop iteration. The three abort waits
are P0-only bounded to 10 ms and set `ABORT_TIMEOUT`. This still cannot report
after CPU stop, failure to call the event loop, a hang inside another interrupt
sub-handler/MMIO access, or power loss. Those outcomes remain UNKNOWN.

D. At the deadline the seven-bit checkpoint byte is frozen. `P0_EP0_MARK`
rejects later writes, and USB reset does not initialize diagnostic fields.
Disconnect/reconnect/abort flags are monotonic report metadata; they do not
alter the frozen GET checkpoint byte. A later SETUP or index-4 request therefore
cannot be mistaken for progress of the original GET.

E. The fixed 22-character record is `P0E2 + boot-id(8) + generation(4) +
trace(2) + flags(2) + checksum(2)`. The host requires the report boot ID and
generation to equal the saved arm record and validates its checksum. That
prevents accepting an initial value, another boot or ordinary descriptor
cache as this trial. The separately verified payload hash binds that boot to
the reviewed build; embedding the payload hash in itself is intentionally not
attempted.

F. The one-shot transition uses only the existing DWC2 `DCTL.SftDisCon` bit,
already used by `usb_dwc2_init` and `usb_dwc2_shutdown`: set once at freeze,
clear once after 100 ms. It does not guess registers or perform a full
controller reset. Normal host reset handling is reused with the P0 abort
bounds above. There is no retry or recovery loop.

G. Index 4 remains unadvertised before arm, preventing an automatic initial
enumeration read from masquerading as the explicit arm. At freeze the code
changes only `iConfiguration` from 0 to 4 before disconnect. Re-enumeration is
expected to retain VID:PID 1209:316D, serial/InstanceId,
parent hub, ordered location paths, `usbser` service and product prefix. The
only intentional descriptor change from the previous diagnostic is P0
configuration string index 4 being advertised. The host gate is not relaxed;
any other identity/location change rejects the report.

The report still depends on EP0 functioning after the reconnect attempt. A
failed reconnect or report read is not converted to a checkpoint value. No
UART, proxy or second host is assumed. This is materially different from the
failed session-r post-failure read because arm and the autonomous deadline are
established while EP0 is healthy, before COM.

### Minimal difference and host-only verification

`m1n1-p0.patch` adds P0-only fixed fields, guarded checkpoint ORs, the fixed
descriptor, three deadline poll sites, one disconnect and one reconnect, and
finite P0 abort waits. It adds no printf or dynamic allocation and makes no
ANS/NAND change. `Read-Ep0Trace.c` parses and checks the P0E2 record.
`Invoke-Ep0TraceRead.ps1` has explicit `Arm` and `Report` modes; Report requires
the saved successful Arm session and exact boot/generation match. Both modes
retain one request and a five-second process deadline, refuse output reuse and
write the session JSON in `finally`, including on host failure.

The full P0 payload build passed, with the pre-existing linker placement
warning only. The executable CDC test still runs the current handler bodies.
The new model/source-policy test covers normal `0x7f`, no SETUP `0x00`, handler
only `0x03`, IN armed/no completion `0x07`, and status armed/no completion
`0x1f`; it distinguishes unarmed from armed/unobserved, verifies freeze,
single disconnect/reconnect, post-freeze non-destruction and reset-source
non-initialization. Reader policy tests reject malformed/checksum-invalid,
stale/mismatched/non-frozen reports and unexpected identity/location. They
also verify zero COM/proxy/P_NOP/ANS/NAND operations in the reader. All three
focused host tests pass. These tests do not prove device DMA timing, interrupt
arrival, the 100-ms physical disconnect interval, Windows re-enumeration or
post-disconnect EP0 recovery.

Reviewed artifact hashes are:

| Artifact | SHA-256 |
| --- | --- |
| `m1n1-p0.patch` | `BD9734C382F1339FDE61EF70A52FB1A179F2063491B823895ABC70F299A66BAC` |
| `build/m1n1.bin` | `5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D` |
| `Read-Ep0Trace.c` | `BEC6568062F8D2DDEA40CCACD9E9B62303D9BB189A20921D42233F132D6DB0FB` |
| `Read-Ep0Trace.exe` | `26CEBECDAC9D93272A6A81C37E716D2CB0B364CB31B29D67A53FBF57C3D5F823` |
| `Invoke-Ep0TraceRead.ps1` | `912915FBE933130363C7D317705CC7617AC693191F0A71911C335D53B533357B` |
| `build-manifest.json` | `669AD4AE1A60D811547E6C2B81132A65EAF2DEC2CEA7CE4B94E1BE0A4BE4464D` |
| `ep0-trace-reader-manifest.json` | `9BCA8D2468DABAE73A8132951FFF4F569C7FF6AE0A6E1679709224275D8F78B9` |

### One future hardware trial (new approval required)

Use a new, initially absent directory
`artifacts/p0-usb/session-s-ep0-autoreport`. Reconfirm A1625/T7000 identity,
ECID and physical location; Checkm8 and Pongo are one attempt each; transfer
only the payload hash above once; then repeat exact identity/location and
artifact gates. Start one continuous ETW trace before arm and retain host
monotonic timestamps through final collection.

Perform one Arm-mode index-4 read (5-second limit). Save its session JSON and
raw stdout immediately. It must be P0E2, checksum-valid, VALID|ARMED, not
FROZEN, nonzero boot ID, generation 1. Otherwise stop without COM. Start
exactly one COM open within 5 seconds of arm completion. Do not issue a second
COM open or the failed session-r post-failure reader. Record Windows/OS-issued
URBs separately from tool-issued attempts: tool counters remain arm=1,
COM-open=1, report=1 at most; repeated OS URBs are ETW observations, not
authorized retries.

The device freezes at arm+45 seconds, sets soft disconnect once and clears it
after 100 ms once. The 45-second separation is deliberately later than session
r's approximately 30-second GET completion. Record the GET submission and
completion, disconnect, disappearance, reappearance and report-read timestamps
so an URB cancelled by disconnect is not labeled as the original GET result.
Wait no longer than 60 seconds from arm for the expected same-location device
to reappear. Unexpected identity/location or no reappearance ends UNKNOWN.
After reappearance perform exactly one Report-mode read (5-second limit),
bound to the saved Arm JSON. No report, invalid checksum, non-frozen state or
boot/generation mismatch ends UNKNOWN with logs retained; there is no reset,
re-enumeration or read retry.

Interpret the frozen checkpoint as follows; each bit proves only passage of
its instrumented statement:

| Frozen trace | Supported split | Still not established |
| --- | --- | --- |
| `0x00` | armed, but exact target SETUP was not observed | whether controller/DMA received it |
| `0x01` | target SETUP observed after DMA barrier | entry into validated handler |
| `0x03` | handler entered | EP0 IN programming |
| `0x07` | seven-byte IN was programmed/enabled | host receipt or DMA/IRQ completion |
| `0x0f` | IN completion handler ran | OUT status was armed |
| `0x1f` | OUT status was armed | status completion |
| `0x3f` | OUT status completion handler ran | subsequent SETUP; host success still needs ETW |
| `0x7f` | subsequent SETUP was also observed before freeze | Windows COM configuration success |
| other | instrumentation/state anomaly | normal prefix interpretation |

`ABORT_TIMEOUT` describes reconnect/reset handling after freeze and does not
change the GET trace. A valid current-trial record that advances this split is
the diagnostic completion condition. It is not COM configuration or P_NOP
success. Do not issue P_NOP in this autonomous-disconnect trial. In every
outcome stop before ANS initialization and all NAND access. The trial is not
authorized until its exact commands, current target state and hashes are shown
and the user gives a new approval.

### Session s execution wrapper and pre-start state

`Invoke-Ep0DiagnosticTrial.ps1` preserves one ETW session across arm, the one
COM open, the autonomous disconnect/re-enumeration window and report. It polls
PnP state without issuing extra USB requests, timestamps every phase, stops the
COM child at 40 seconds if still blocked, performs the report at 50 seconds
from arm, and writes hashes/session state in `finally`. Its SHA-256 is
`D590601CA39B884591600CE1C18CB3EF5C9D9C0EB8477338E99C0B30EA8A8DA8`.
The wrapper neither performs boot stages nor sends P_NOP/ANS/NAND requests.

The pre-start PnP check on 2026-09-10 found 1209:316D `usbser` at the expected
USB(4)/HS04 location: the device was still running the prior m1n1 boot. It was
not DFU, and no boot-stage command was run. After a new manual clean DFU entry,
the exact proposed commands, each gated on the preceding result, are:

```powershell
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Checkm8 -OutputDirectory artifacts/p0-usb/session-s-ep0-autoreport
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Pongo -OutputDirectory artifacts/p0-usb/session-s-ep0-autoreport
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Payload -OutputDirectory artifacts/p0-usb/session-s-ep0-autoreport -ApprovedPayloadSha256 5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D
& .\windows-native\internal-storage\p0\Collect-TransportInventory.ps1 -OutputPath artifacts/p0-usb/session-s-ep0-autoreport/before-com.json
& .\windows-native\internal-storage\p0\Invoke-Ep0DiagnosticTrial.ps1 -IdentityPath artifacts/p0-usb/session-s-ep0-autoreport/before-com.json -OutputDirectory artifacts/p0-usb/session-s-ep0-autoreport/diagnostic -ApprovedPayloadSha256 5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D
```

These commands are not valid against the currently observed 1209:316D state;
the Checkm8 gate requires one clean 05AC:1227 DFU device with CPID 7000, BDID
34, configured ECID `000C14642E028026`, `libusbK`, and the reviewed location.

## Session s: pre-Checkm8 driver-gate stop

The user manually entered DFU and explicitly approved the five commands listed
above. The first command was invoked once. Its pre-execution identity gate found
exactly one clean 05AC:1227 device with CPID 7000, BDID 34, ECID
`000C14642E028026`, status OK, and the expected USB(4)/HS04 location, but its
service was `WINUSB` rather than the required `libusbK`. The wrapper stopped at
line 19 with `Identity/driver gate failed: expected libusbK, got WINUSB` before
starting the Checkm8 process.

No Checkm8 attempt reached the device, and no Pongo, payload, inventory, arm,
COM open, autonomous disconnect, report, P_NOP, ANS or NAND operation ran. The
new session directory exists but contains no stage record because the gate
failed before record creation; it must not be reused. No retry or driver change
was performed. A later attempt requires an exact-instance driver correction,
a different new session directory, fresh DFU confirmation and new approval.

## Session t: Checkm8 passed, Pongo pre-gate stop

After the exact clean-DFU instance was changed to `libusbK`, the user approved
a new run in `artifacts/p0-usb/session-t-ep0-autoreport`. Checkm8 ran once and
passed its output, identity, location and host-artifact gates. The saved
`Checkm8.json` records the expected USB(4)/HS04 location and exact host hashes.

Before the Pongo process was launched, the stage wrapper found the resulting
YOLO DFU identity (`CPID:7000`, `BDID:34`, ECID
`000C14642E028026`, `YOLO:CHECKRA1N`) at the same location, but Windows had
bound that re-enumerated instance to `WINUSB`. The required `libusbK` gate
stopped the stage. Pongo was not transferred, and payload, inventory, arm, COM,
disconnect/report, P_NOP, ANS and NAND operations did not run. No automatic
retry or driver change was performed.

Session t and its passed Checkm8 record may be continued only while the same
YOLO identity and location remain present. The exact YOLO instance must first
be changed to `libusbK`; then the Pongo command requires a new approval. If the
device leaves YOLO DFU, Session t must not be resumed.

### Session t diagnostic host-gate stop

After Pongo and the hash-bound diagnostic payload passed, inventory saved one
expected 1209:316D `usbser` candidate at USB(4)/HS04. The approved diagnostic
wrapper started ETW, then its Arm child failed before creating the arm output
directory because it launched a legacy `powershell.exe` environment in which
`Get-FileHash` was unavailable. The native reader was never started, so the
device received no index-4 arm request. The persisted counters are actual arm
requests 0, COM opens 0, reports 0, P_NOP/ANS/NAND 0. ETL and XML were retained
with SHA-256 `3CE41D9CB87BDA04C0992793906D904A597C56943E749172724686851B63A690`
and `1B183FD9CBB91BF31854B75D80A505C1B146B54EF1CFCCAED51AE5ABA1CA6D94`.

No automatic retry occurred. The host-only correction makes the child use the
same executable as the current PowerShell process instead of resolving
`powershell.exe`. The corrected wrapper SHA-256 is
`C79D5F751E46EF91918E5B1CC329DEB9B3A3FDDF325D004861A1735572EDE417`.
The existing diagnostic output directory is not reusable;
another diagnostic attempt requires a new output directory and new approval.

### Session t diagnostic-u: pre-COM arm recovery failed

The user approved one corrected `diagnostic-u` run against the still-present,
previously unarmed payload. All saved identity, parent, ordered location and
reader-artifact gates passed. ETW started, and the Arm reader issued its one
allowed index-4 descriptor operation through the parent hub. It did not return
within the five-second deadline, so the exact child was stopped and no retry
occurred. Stdout is empty; stderr is only `descriptor` and is not a diagnostic
value. No P0E2 record was recovered. In particular this is UNKNOWN, not trace
`0x00`, and the ETW submission cannot establish device-side SETUP recognition.

Because an internal arm might nevertheless have occurred, this payload boot
must not be used for another arm or COM attempt. The orchestrator stopped before
`arm-confirmed`; actual counts are descriptor arm request 1, COM open 0, report
0, P_NOP/ANS/NAND 0. Its ETL/XML SHA-256 values are
`602614AED8FAC23EF44352B84A539899072F1B22753C7E5ABE931D934333C3EA`
and `7B151CF120532B7BD00FEE84A532C507637EFD4216B7791B319698076FCA25A7`;
the Arm session JSON SHA-256 is
`720BEE2D9E4EF433CEDDDE41C84E84C434561835478B93C2D83B58D7494B38D9`.

PnP checked after the device-side 45-second window still showed the expected
1209:316D instance, `usbser`, and USB(4)/HS04 location. That observation does
not prove whether a brief autonomous disconnect/re-enumeration occurred. The
ETW session had already stopped on arm failure and contains no evidence from
that later window.

This result invalidates the assumed pre-COM arm confirmation path on this host:
the same hub index-4 operation that failed after COM in session r also fails
before COM. Consequently the advertised post-re-enumeration report design
cannot be used until a different, independently verified pre-COM arm mechanism
exists. Repeating index 4, opening COM on this boot, or treating PnP presence as
arm success is prohibited. No further hardware step is authorized by this
result.

## Standard product-descriptor control preparation (not executed)

This offline preparation is based on session t diagnostic-u. It does not reuse
that possibly armed boot and performed no USB request, COM open, boot,
disconnect/re-enumeration or driver change.

### Saved-helper review

The diagnostic-u session hashes match commit `e373d1a` versions of
`Read-Ep0Trace.c`, `Invoke-Ep0TraceRead.ps1`, the executable and manifest. The
wrapper derives port 4 from the sole ordered location ending in `USB(4)`, uses
the saved parent hub, and gates exact InstanceId, 1209:316D, `usbser`, product,
parent and ordered location. The helper opens the single
`GUID_DEVINTERFACE_USB_HUB` path synchronously, validates
`IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX`, then calls
`IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION` once with one zeroed
header-plus-data buffer for both input and output.

No clear functional defect was found in the old structure size, initialization,
connection index or IOCTL buffer sizing. WDK 10.0.28000.0 `usbioctl.h` defines
the trailing `USB_DESCRIPTOR_REQUEST.Data[0]` layout. Microsoft documents this
as a user-mode hub request and its caller-provided `wValue`, `wIndex` and
`wLength`. The official USBView sample uses the same one-buffer arrangement
and checks `bLength == bytesReturned - sizeof(request)`.

The old reporting did have an observability defect: progress existed only on
buffered stdout/stderr, with no durable marker immediately before the blocking
call. Thus the forcibly terminated process's `descriptor` fragment does not
show that the API returned an error. Child termination also does not prove
kernel-I/O cancellation or device-side termination.

Primary references: local WDK `shared/usbioctl.h`, Microsoft Learn
[`IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/usbioctl/ni-usbioctl-ioctl_usb_get_descriptor_from_node_connection),
[`USB_DESCRIPTOR_REQUEST`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/usbioctl/ns-usbioctl-_usb_descriptor_request),
and Microsoft's
[`USBView GetStringDescriptor`](https://github.com/microsoft/Windows-driver-samples/blob/main/usb/usbview/enum.c).

### Selected control and exact request

The only control is the advertised product string. Payload source sets
`iProduct=2`, supplies index 2 as `"m1n1 uartproxy " BUILD_TAG`, and advertises
LANGID `0x0409`; saved inventory supplies the exact expected text. The request
is `bmRequestType=0x80`, `bRequest=0x06`, `wValue=0x0302`, `wIndex=0x0409`,
`wLength=128`. The source value fits the fixed buffer. This one maximum-sized
request avoids header-plus-full probing and matches USBView's approach. There
is no index scan, fallback or second request.

Only descriptor index 4 calls `p0_ep0_trace_string`; index 2 cannot arm the
existing 45-second timer. No device-side change is made.

### Minimal host change and offline results

The helper now creates an unbuffered JSONL phase log before hub open. It records
hub discovery/open, connection-info entry/return, descriptor entry/return,
monotonic times, exact request, returned length and the immediately captured
error (`0` on success). Raw bytes are saved separately before interpretation.
If the synchronous API never returns, no stale error is invented. The wrapper
persists `HOST_DEADLINE_EXCEEDED`, phases and observed request count in
`finally`, and separates Product UTF-16 validation from P0E2 parsing.

`Invoke-StandardDescriptorTrial.ps1` inherits the current PowerShell, starts
ETW first and issues only Product mode. It keeps ETW two seconds after success;
after the five-second helper deadline it observes passively for 35 seconds,
covering session r's roughly 30-second completion without another request.
It contains no index-4, COM, proxy, reset, driver, P_NOP, ANS or NAND action.

The helper builds with GCC C11 `-Wall -Wextra -Werror`; all 18 P0 host tests
pass. New offline cases cover valid response/raw preservation, returned API
error, non-return/timeout phase, short/malformed response, pre-request failure,
exception persistence, one-request policy and prohibited-operation absence.
Mocks do not prove device response, kernel cancellation, ETW correlation or
cache behavior.

| Artifact | SHA-256 |
| --- | --- |
| unchanged payload | `5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D` |
| unchanged device patch | `BD9734C382F1339FDE61EF70A52FB1A179F2063491B823895ABC70F299A66BAC` |
| helper source | `43AF90FD7B6F3253837F7AA6C8F34348D7704F3024526CE5C5835FC63569B738` |
| helper executable | `9871F936F81A0E288171C01BF2E7AA01D90FFC2F1EA7E1124C81DD86535D1E3E` |
| reader wrapper | `D430D3BAAFA256149B14986ABCE990D7000CD303E16DE0976EEAA62B78E7B3A1` |
| standard-trial wrapper | `52ACD2382E86C414ABC89368F2783F2CA9AE8F47825587BA53FC628BD4FC37F7` |
| reader manifest | `FADD1D216BCAF3F51B3D4AA3AB9ED1F5283E3B65C3D626145412E91D756EFD8B` |
| payload manifest | `669AD4AE1A60D811547E6C2B81132A65EAF2DEC2CEA7CE4B94E1BE0A4BE4464D` |

### One future trial

Do not reuse session t. Manually power-cycle, enter clean DFU, and bind only
the exact DFU/YOLO instances to `libusbK` when required by existing gates. Use
new directory `artifacts/p0-usb/session-u-standard-product`; stop after each
command unless its saved result passes:

```powershell
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Checkm8 -OutputDirectory artifacts/p0-usb/session-u-standard-product
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Pongo -OutputDirectory artifacts/p0-usb/session-u-standard-product
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Payload -OutputDirectory artifacts/p0-usb/session-u-standard-product -ApprovedPayloadSha256 5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D
& .\windows-native\internal-storage\p0\Collect-TransportInventory.ps1 -OutputPath artifacts/p0-usb/session-u-standard-product/before-control.json
& .\windows-native\internal-storage\p0\Invoke-StandardDescriptorTrial.ps1 -IdentityPath artifacts/p0-usb/session-u-standard-product/before-control.json -OutputDirectory artifacts/p0-usb/session-u-standard-product/product-control -ApprovedPayloadSha256 5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D
```

The last command issues one tool-originated request; Windows automatic traffic
is separately identified in ETW. Interpret results as follows:

| Class | Permitted conclusion |
| --- | --- |
| A: exact raw/product and corresponding successful ETW completion | this standard path worked then; not index 4 or CDC GET success |
| B: exact value but cache cannot be excluded | host API returned a value; live EP0 response unproved |
| C: API returned error | preserve API/error/length; do not generalize to all EP0 |
| D: five-second deadline | host timeout; device internal state UNKNOWN; retain ETW to 35 seconds |
| E: pre-request gate/process failure | tool USB request count 0; not a USB result |

Any failure stops further requests. Success also stops: no COM, index 4, P_NOP,
proxy, ANS or NAND follows. Save session JSON, phases, raw bytes, ETL/XML and
hashes. This trial needs fresh clean-DFU confirmation and explicit approval;
this preparation authorizes no hardware action.

## Session u: standard product-descriptor control result

The user manually confirmed a fresh DFU state and explicitly approved the five
Session u commands. The commands were then run one device-affecting stage at a
time. The saved Checkm8, PongoOS and diagnostic m1n1 RAM-payload stages all
passed their existing identity, location, artifact and safety gates. The
payload SHA-256 was
`5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D`.
The immediately collected inventory contained exactly one expected
`1209:316D`/`usbser` instance on the saved USB(4)/HS04 location. These facts do
not authorize reuse of this boot for another control request.

The standard product-descriptor trial issued its one allowed tool request and
then stopped with class D, `HOST_DEADLINE_EXCEEDED`. The durable phase log shows
successful hub open and connection information return (47 ms), followed by
`descriptor_entered` for exactly `80/06`, `wValue=0302`, `wIndex=0409`,
`wLength=0080`. There is no `descriptor_returned`, no raw descriptor, and no
API-returned error. Stdout and stderr are empty. The wrapper made no retry and
kept the ETW session passively for the specified 35 seconds.

ETW independently contains one dispatch matching that exact 128-byte request.
Its completion is about 4.965 seconds later with IRP status `0xC0000120`, USBD
status `0xC0010000`, and transfer length zero. That timing coincides with the
wrapper's five-second child deadline and is therefore treated as cancellation
of the outstanding tool request, not as an independently observed device
response. ETW also contains an immediately preceding completion for a
different product request whose `wLength` is `00FF`. Although the kernel reused
the same URB pointer, the differing SETUP lengths mean those events must not be
paired. The `0080` dispatch and completion form the applicable pair.

This result shows that the current parent-hub descriptor API path also fails to
return a live value for the advertised standard product string; the failure is
therefore not specific to private index 4 or P0E2 parsing. It does not establish
that the device recognized SETUP, entered a descriptor handler, or failed a
particular EP0/DMA phase. Nor does the PnP product text prove a live response,
because it can be enumeration metadata retained by Windows. The remaining
possibilities include a common device-side EP0 problem and a host/hub IOCTL
path problem; Session u alone does not distinguish them.

No COM open, index-4 request, proxy request, P_NOP, ANS operation or NAND
operation occurred. Counts persisted by the trial are product descriptor
requests 1 and all those prohibited/follow-on operations 0. No autonomous
disconnect was armed by index 2 in the payload source, and unrelated ETW bus
traffic is not evidence of an A1625 disconnect or re-enumeration. No additional
hardware operation was performed after this result.

| Session u evidence | SHA-256 |
| --- | --- |
| ETL | `A776CD99791634E926BF4187ED44C14E4BDB2627814A5B94FE85D97DC99504C6` |
| XML | `0FD24DA6DD9114FC3E36E32DB1CAEC82E268BAB3F80DE9A1505433D8FDFB0222` |
| trial session JSON | `78771D9EF3DF3F7BB64DCA69279F88AF544C85C894C41332054A0D4EE15BAFBD` |
| reader session JSON | `A676CB8A5B17E4E18CC8A4FCB51B72309DE714D5075B064433F990DA26AF21A6` |
| phase JSONL | `6DFDBAAD9AAC6EA1E5391DE71372E5B9115A4613D5F0012A60AF1BEA4B6DA101` |

Session u is complete and stopped safely. A further test needs a separately
reviewed plan, a new session directory and new explicit approval; it must not
repeat the already failed product or post-failure index-4 read without a new
source of evidence.

## Post-Session u ETW boundary analysis and passive-enumeration preparation

### New finding from the saved trace

The `wLength=00FF` event is not a successful product response. Session u ETW
starts at `17:19:56.2330391` (the XML renders a nonstandard `+08:59` offset),
after the Payload stage had already returned and Windows had created the
1209:316D instance. For the target UCX device `0x6A7687447FD8`, the trace has
only three control-transfer events. The first is the `00FF` completion; no
matching dispatch exists anywhere in the trace. Its IRP differs from the later
tool request, and its zero transfer length and cancellation statuses contain no
descriptor bytes. Its issuer and start time are therefore UNKNOWN. In
particular, the reused URB pointer cannot connect it to the later request.

| Time | Target / origin | Complete SETUP | Requested / actual | Status | Pairing basis and limit |
| --- | --- | --- | --- | --- | --- |
| `17:19:57.6814245` | target device `0x6A7687447FD8`, control pipe `0xFFFF958972FD4630`; issuer UNKNOWN | `80/06/0302/0409/00FF` | 255 / 0 | IRP `C0000120`, USBD `C0010000` | completion only; IRP `0xFFFF9589842D0010`, URB `0xFFFF958938F68458`; dispatch is outside the recording or missing, so start time and attribution are UNKNOWN |
| `17:19:57.6844513` | same device/control pipe; Session u helper, correlated by phase time and exact requested SETUP | `80/06/0302/0409/0080` | 128 / pending | dispatch USBD `40000000` | IRP `0xFFFF95896BDD4A80`, URB `0xFFFF958938F68458`, buffer `0xFFFF95896DD07DCC`; dispatch alone does not prove device SETUP consumption |
| `17:20:02.6489973` | same helper request | `80/06/0302/0409/0080` | 128 / 0 | IRP `C0000120`, USBD `C0010000` | exact IRP, URB, pipe, device, SETUP and buffer match the preceding dispatch; 4.965-second interval matches host child termination, so this is cancellation, not a device-returned timeout |

The UCX rundown maps the common pipe handle to endpoint object
`0x6A768D02BA88`; the control-transfer task and SETUP identify logical EP0, but
the XML has no separate endpoint-address field. It retains buffer addresses,
not payload data. There is no successful target completion in the recorded
interval. Consequently the last successful target transfer is UNKNOWN, and
the first recorded abnormal target event is the unmatched `00FF` completion,
which precedes the first tool dispatch by about 3.027 ms. The first manual
helper operation is not the first recorded target USB event.

Session u cannot reconstruct connection, descriptor enumeration,
SET_CONFIGURATION, interface binding, or the transition to ordinary proxy
waiting: all occurred before ETW began. PnP state and the Payload wrapper's
postcondition show that Windows created the expected instance, but are not
substitutes for per-transfer success completions or verified raw descriptor
contents.

### Code review at the missing boundary

The saved manifest still identifies source revision
`d5a10ac52a6468484854419a6c5130f1d62073eb`, patch SHA-256
`BD9734C382F1339FDE61EF70A52FB1A179F2063491B823895ABC70F299A66BAC`,
and the `ANS1_P0` build flags. The current nested source diff is byte-for-byte
represented by that saved patch, and the payload still hashes to
`5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D`.
There is no later source/build divergence to explain Session u.

In the DWC2 implementation, standard index 2 selects `str_product`, sets the
response length to `min(wLength, descriptor_len)`, enters `DATA_SEND`, copies
the response to the control-IN DMA buffer, and programs EP0 IN. IN completion
moves to the host-OUT status state; status completion rearms SETUP. CDC
GET_LINE_CODING joins the same path at `DATA_SEND`, but selects a 7-byte
buffer. Thus the two requests share later control-IN machinery, while the trace
does not prove that either reached it.

The built product text has 40 characters, so the actual USB string descriptor
is 82 bytes, not 128 or 255. It requires two 64-byte-maximum EP0 packets and
fits the per-endpoint 4096-byte DMA allocation. Both observed request lengths
would be capped to 82 by the code. No length overflow or single-packet boundary
fault is established here. The existing SET_CONFIGURATION path activates the
CDC endpoints and returns a control status; `uartproxy` continues to call
`iodev_handle_events` before `iodev_can_read`. No new blocking wait, lock or
flush attributable to the P0 patch was found on that transition.

The P0 patch does change common EP0 interrupt/state handling, so it remains a
candidate, but the post-enumeration-only trace cannot identify a failing state
transition. There is insufficient evidence for a targeted USB source fix and
no USB device code was changed. This review deliberately does not infer that
the product and CDC failures share a cause.

### Minimal preparation and offline verification

`Invoke-PassiveEnumerationTrace.ps1` is the only new host behavior. It checks
the existing Checkm8/Pongo records and payload/patch hashes, starts the same
full-keyword/full-level `Microsoft-Windows-USB-UCX` provider before spawning
the existing Payload stage once, then records 35 seconds after that stage
returns. A failed Payload stage stops without extending observation. The
overall payload-child deadline is 150 seconds. It adds no descriptor, index 4,
COM, proxy, reset, P_NOP, ANS or NAND request and makes no driver change.

The wrapper SHA-256 is
`2F060712F0DF54DE28D545E37461C55F49FE5DBCC90F0AA69ABEC15CE6B974FE`;
the unchanged called boot wrapper is
`C4D1E315BB3FD001878842149D1C86166BB82C665CAC029DCB64CE4B592B3B77`.
Its static test SHA-256 is
`E9D1123550F38DA1F28705EBEDADF6E48F99B0DC33F1C9BF362A11EA1DE0FA77`.
PowerShell parsing passed. All 19 P0 offline tests passed; the startup-object
test initially could not execute sandboxed `llvm-objdump`, then passed when
rerun with the same inputs outside that sandbox. These tests prove ordering
and prohibited-operation absence, not live provider coverage or device timing.

### One future passive enumeration session (not executed)

Use a new directory `artifacts/p0-usb/session-v-passive-enumeration`. After a
manual fresh DFU confirmation, run the existing Checkm8 and Pongo stages one at
a time. Only if both saved records pass, run the prepared wrapper:

```powershell
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Checkm8 -OutputDirectory artifacts/p0-usb/session-v-passive-enumeration
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Pongo -OutputDirectory artifacts/p0-usb/session-v-passive-enumeration
& .\windows-native\internal-storage\p0\Invoke-PassiveEnumerationTrace.ps1 -OutputDirectory artifacts/p0-usb/session-v-passive-enumeration -ApprovedPayloadSha256 5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D -ObservationSeconds 35
```

The third command starts ETW before the existing Payload stage performs its
upload/`bootm` transition. Provider rundown plus device/endpoint/pipe handles,
SETUP tuples, IRP/URB identifiers, ordered location and the saved phase ticks
will correlate pre/post-enumeration traffic. Header `EventsLost` and
`BuffersLost` detect reported ETW loss; an `etw-started-before-payload` phase
proves host ordering, but neither mechanism proves that UCX emitted every
hardware transaction. The Payload stage's PnP polling/property reads are
captured inside the window and must be classified from traffic, not assumed
traffic-free. There are no tool-originated control requests in this trial.

Interpret the single session as follows:

| Result | What it can distinguish | What remains unknown |
| --- | --- | --- |
| successful standard descriptor and configuration completions, followed by no abnormal automatic control | enumeration EP0 worked at those recorded moments; Session u failure is later or specific to its hub-IOCTL context | descriptor contents without captured data, device internal state, and why the explicit hub request hung |
| first abnormal completion occurs on a specific enumeration SETUP with a matched dispatch | narrows the boundary to that recorded request and orders it before driver readiness | device-side checkpoint and exact controller phase |
| descriptors succeed but SET_CONFIGURATION or a later class request is first abnormal | separates early descriptor handling from configuration/class transition | whether host, hub, driver or device caused the failure |
| unmatched completion or trace loss remains at the boundary | preserves UNKNOWN and shows the continuous trace still lacks decisive pairing | no causal conclusion; do not repeat automatically |
| no target UCX traffic despite a successful Payload record | provider/correlation plan is insufficient on this host | USB behavior itself; stop rather than add an active probe |

Success or failure ends the session. Do not issue product/index-4 controls,
open COM, run P_NOP, or proceed to ANS/NAND. If the trace has loss, lacks both
ends of the decisive transfer, or cannot correlate the expected device and
ordered location, record UNKNOWN and stop. This plan requires a new explicit
hardware approval after review; no Session v operation has been performed.

## Session v: continuous passive enumeration result

### Execution and safety result

The user confirmed a fresh DFU state and approved Session v. Checkm8 passed.
The first Pongo invocation stopped at its pre-transfer driver gate because the
exact YOLO instance had `WINUSB`, not `libusbK`; it made no Pongo transfer and
was not retried automatically. After the user changed that exact instance and
gave a new approval, the single Pongo retry passed. The passive wrapper then
started ETW before launching the one Payload stage. The payload and 35-second
passive observation both passed.

The payload was the approved RAM-only artifact
`5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D`.
Saved identity and ordered USB(4)/HS04 location gates passed. ETW reports zero
lost events and zero lost buffers. Counts are tool descriptor/index-4/COM/proxy/
P_NOP/ANS/NAND requests all zero. No driver change was automated, and no
operation followed passive observation.

### Newly established transfer boundary

The new trace changes the P0-USB boundary materially. The target m1n1 UCX
device is `0x6A7680BFC3A8` on control pipe `0xFFFF958978BB80E0`. Windows-side
successful completions exist for device/configuration/string descriptors,
SET_CONFIGURATION, the first CDC GET_LINE_CODING, SET_CONTROL_LINE_STATE and
SET_LINE_CODING. The next GET_LINE_CODING is the first abnormal target
transfer. It completes after about 8.919 ms with NT status `0xC0000001`, USBD
status `0xC0000004` (`USBD_STATUS_STALL_PID` in the saved WDK header), and zero
bytes. Only after that stall do standard string requests begin waiting five
seconds and ending as host cancellations.

| Time | SETUP | Host completion | Interpretation |
| --- | --- | --- | --- |
| `17:43:58.6609693` | `80/06/0100/0000/0040` device descriptor | success, 18 bytes | earliest recorded target request; host success record, raw bytes not retained |
| `17:43:58.6744077` | `80/06/0200/0000/00FF` configuration | success, 97 bytes | full advertised configuration returned according to host completion |
| `17:43:58.6745551` | `80/06/0302/0409/00FF` product | success, 82 bytes | exact built product length; proves this standard product transfer completed during this enumeration, not its decoded contents independently |
| `17:43:58.6917021` | `00/09/0001/0000/0000` SET_CONFIGURATION | success, 0 bytes | configuration transition completed on the host |
| `17:43:58.6932388` | `A1/21/0000/0002/0007` GET_LINE_CODING | success, 7 bytes | first CDC GET completed before any manual COM open |
| `17:43:58.6933018` | `21/22/0000/0002/0000` SET_CONTROL_LINE_STATE | success, 0 bytes | DTR value is zero; not a user COM-open success |
| `17:43:58.6936263` | `21/20/0000/0002/0007` SET_LINE_CODING | success, 7 bytes | host reports the complete control-OUT operation succeeded; received line-coding contents are not in ETW |
| `17:43:58.6937333` | `A1/21/0000/0002/0007` GET_LINE_CODING | `C0000001/C0000004`, 0 bytes | first abnormal target transfer; STALL follows SET_LINE_CODING by only about 5.2 microseconds |
| `17:43:58.7102546` | `80/06/0300/0000/00FF` languages | after 5.001 s: `C0000120/C0010000`, 0 bytes | first later non-returning standard request, canceled by its host deadline |
| through `17:44:33.7553055` | repeated languages/manufacturer/product string requests | each completed pair waits about 5 s and is canceled; final product dispatch is unmatched at trace stop | host-originated follow-up sequence; exact issuing component is not identified by UCX events |

The last successful target transfer is SET_LINE_CODING. The first failed target
transfer is the immediately following GET_LINE_CODING, not the later product
descriptor. This does not show that SET_LINE_CODING data was semantically
correct, but it does overturn the earlier session-specific assumption that the
device never reaches a host-successful SET_LINE_CODING operation. It also shows
that EP0 and the 82-byte product response work earlier in the same boot.

Session u's unmatched `00FF` product completion is consistent with the later
five-second follow-up sequence seen here, but Session u still lacks its own
submission and issuer; Session v does not retroactively supply those missing
fields. The follow-up requests occur while the existing Payload wrapper is
performing its PnP postcondition checks. UCX does not identify whether the
specific issuer is PnP, usbser, the hub stack, or a property-query side effect,
so attribution remains UNKNOWN.

### Code interpretation and remaining uncertainty

The exact SET_LINE_CODING and second GET share interface index 2 (pipe 1). The
source accepts both tuples. SET_LINE_CODING receives seven bytes on EP0 OUT,
copies them into pipe 1 line coding, sends IN status, and only after status
completion rearms the next SETUP. The second GET dispatch follows the prior
host completion by roughly 5.2 microseconds. A device-side rearm/timing race at
that transition is therefore the leading code hypothesis, and the subsequent
standard-request hangs are consistent with EP0 remaining in a bad state.

That is an inference, not a device checkpoint. ETW cannot show whether the
status-completion interrupt ran, whether SETUP DMA was rearmed before the next
packet, or which code/hardware path generated the STALL. Therefore no
speculative device fix was made in this session. In particular, success of the
first GET and SET does not prove the current interleaving logic correct for the
5-microsecond transition.

External primary-source review was kept separate: the Linux kernel's official
[`drivers/usb/dwc2/gadget.c`](https://github.com/torvalds/linux/blob/master/drivers/usb/dwc2/gadget.c)
uses controller-specific EP0 setup/control handling and, in descriptor-DMA
mode, distinct setup and control descriptor chains. It supports treating setup
reception as a controller-level timing concern, but it does not prove the
required programming sequence for this Apple/T7000 m1n1 implementation.

### Saved evidence and offline correction

| Evidence | SHA-256 |
| --- | --- |
| ETL | `12E9B287D9735ADD0122E711BA16D9B9494213E539DA4549EAE216D8E7766268` |
| XML | `D27F6DECC1DF41DDDDD019A3815D1EA6E1E4DC69251FFBAA821A654960EE557A` |
| phases JSONL | `2220D38B8EAFC503447AA0A2923266E3FDD8F2BA3925922370BBDF2DF69281C3` |
| Payload JSON | `C4FBCC5F79F76FDDEB17405B32C1BF2E022B2E54587B24526C4A4FFF7DEC30DC` |
| exact CDC analysis JSON | `0731EAD24540EB938B9A3F12DD6049ACAD71F0FEB398E3AD27633E8AC25CD23A` |

`Analyze-ComTrace.ps1` previously paired completions by reused URB pointer
alone. It now requires time order plus exact device, pipe, IRP, URB and complete
SETUP equality, and selects only the first exact completion. Its SHA-256 is
`2D804E043705A3EA7EE4D19B6C219A4F4204F99C1E8D12B7E76E699BEFF09352`.
A regression with one reused URB and two distinct CDC requests passes, as does
PowerShell parsing. The regression SHA-256 is
`642E0197E68D3E2655D4E240252C707ECB86C0F39E1545316121A0D77D134916`.
All 20 P0 offline tests pass; the startup-object test required the same
previously approved out-of-sandbox `llvm-objdump` execution. The resulting Session v analysis contains four CDC
requests, each with exactly one correctly paired completion. This is a
host-analysis correction only and made no USB/device change.

Session v achieved its primary goal and is closed. Do not reuse this boot or
repeat the passive test. The next work should isolate and review the rapid
control-OUT-status to next-SETUP transition in the DWC2 source, with a failing
software interleaving regression before any code change. Any later hardware
validation needs a new artifact hash, exact plan, fresh boot and new approval.

## Post-Session v: EP0 stale IN-status completion preparation

### Fixed baseline and actual-code path

Session v used source revision `d5a10ac52a6468484854419a6c5130f1d62073eb`
and payload SHA-256
`5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D`.
That exact old payload has also been preserved as
`artifacts/p0-usb/session-v-passive-enumeration/payload-used-5DAEF313.bin`;
the Session v logs were not changed. The following review and tests use the
same pinned source plus the new patch and do not describe Session v as having
run the fix.

The implemented SET-to-GET path in `src/usb_dwc2.c` is:

1. `usb_dwc2_handle_interrupts_ep` snapshots DAINT/DOEPINT and passes an EP0
   OUT transfer completion to `usb_dwc2_ep0_handle_xfer_done`.
2. In `DATA_RECV_DONE`, `usb_dwc2_ep0_handle_xfer_done` checks the DOEPTSIZ0
   residual, copies exactly seven bytes from the control OUT DMA buffer into
   `pipe[1].cdc_line_coding`, clears the pending receive destination and moves
   to `DATA_SEND_STATUS`.
3. `usb_dwc2_ep0_handle_xfer_not_ready` calls `usb_dwc2_start_status_phase`;
   this programs a zero-length EP0 IN transfer and changes the state to
   `DATA_SEND_STATUS_DONE`.
4. The corresponding EP0 IN completion enters
   `usb_dwc2_ep0_handle_xfer_done`, which calls `usb_dwc2_start_setup_phase`.
   That points `setup_pkt` at the control OUT DMA buffer, arms SETUP reception,
   and leaves the state at `SETUP_HANDLE`.
5. A new SETUP interrupt is handled by `usb_dwc2_ep0_handle_setup_phase_done`.
   The class handler validates A1/21/0000/0002/0007, selects the saved pipe-1
   seven bytes, and changes the state to `DATA_SEND`.
6. The not-ready handler then programs the GET data on EP0 IN and changes the
   state to `DATA_SEND_DONE`.

`setup_pkt` does refer to the reused control OUT DMA buffer, but the current
handler consumes its request fields synchronously. No later read of that
pointer was found in the reviewed SET/GET path, so this review did not establish
a dangling request-field use. The exact legal second GET can still reach STALL
through class-request validation failure or an invalid EP0-state/default path;
bad/short OUT completion has its own STALL path. Session v's host STALL does not
identify which `usb_dwc2_ep_set_stall` call, if any, ran on the device.

### Reproduced software race and minimal fix

The actual extracted implementation had a reproducible interleaving: DAINT can
be sampled before the preceding IN-status completion is serviced, the next
SETUP can supersede the old control transfer and arm the new GET, and a delayed
old IN completion can then be interpreted using the new `DATA_SEND_DONE` state.
It advances the new GET to status receive even though its data completion has
not occurred. Before the fix, the new regression failed on the invariant
`d.ep0_state == USB_DWC2_EP0_STATE_DATA_SEND_DONE` (generated `cdc.c`, line
463; process exit `3221226505`). The input and event order are identical before
and after the fix; no timing sleep is used.

The minimal device change adds one boolean,
`ep0_ignore_next_in_completion`. When a new SETUP supersedes
`DATA_SEND_STATUS_DONE` and the old IN completion was not already present in
the current interrupt snapshot, exactly one later IN completion is treated as
belonging to the old transfer instead of advancing the new state. If the IN
completion is already in the same snapshot, its W1C acknowledgement is accounted
for and no later discard is armed. USB reset clears the flag. Request validation,
descriptors, CDC interfaces, pipes, driver binding, stalls, and timeouts are
unchanged; no print, delay, arm/descriptor/watchdog, or re-enumeration mechanism
was added.

This proves a software state-machine defect for the modeled, controller-possible
ordering. It does not prove that Session v used exactly that ordering. In
particular, Apple/T7000 interrupt-bit coalescing and the distinction between an
old and a new completion at the hardware boundary remain unobserved. The mock
models discrete pending events; it does not establish real DMA or interrupt
timing.

The official Linux DWC2 gadget implementation was consulted only as external
primary-source context, at master commit `3dab139` as indexed on 2026-07-25,
principally `drivers/usb/dwc2/gadget.c` EP0 setup/control handling. Its
descriptor-DMA path uses controller-specific, separate setup/control descriptor
handling. That supports treating SETUP reception as a controller-owned ordering
problem, but the descriptor-DMA sequence was not copied and is not evidence for
the active Apple/T7000 mode.

### Regression, build, and saved artifacts

`test_usb_cdc.py` executes the extracted real request, completion, and EP0
interrupt bodies. Its new synthetic sequence is GET, DTR=0, SET with known bytes
`00 C2 01 00 00 00 08`, then GET; those bytes are test input, not Session v
observations. It covers normal prior-status completion, simultaneous SETUP and
old IN completion, SETUP after the interrupt snapshot, a delayed old completion
after new GET setup, and the current synchronous lifetime of request fields.
Existing invalid type/value/length/interface, short OUT, standalone GET,
82-byte product, DTR, buffer reuse and reset cases remain enabled.

The same regression that failed before the device change passes after it. All
20 P0 offline tests pass, including the startup-object inspection using the
previously approved external `llvm-objdump`. A forced P0 native rebuild with
`USE_CLANG=1 ARCH=aarch64-none-elf CHAINLOADING=1
EXTRA_CFLAGS=-DANS1_P0` succeeded. The changed common `usb_dwc2.c` also compiles
in a non-P0 configuration; a complete non-P0 build of this full P0 patch remains
inapplicable because the pre-existing P0-only `ans1.c` intentionally stops it.

| Artifact | SHA-256 |
| --- | --- |
| complete `m1n1-p0.patch` | `2490D397F05E080AFD9156E1F70409050EE51A73810744074AC8C8C8521A82EB` |
| `build-manifest.json` | `231039B77CDA26FAC7FB095019E5ABC1FADE653629F1D77E714B862D19E062C9` |
| regression-only patch | `4C793EE7BDACD31C2349E4319C06EF43CD213FFDE7AF15E0D41C66DEAA0C6280` |
| device-fix-only patch | `C309970DDC8946F8758DE7D790162AE4AD9DD45E24F3F3E40746E863DC6B4C73` |
| `test_usb_cdc.py` | `07CCE1890B89191A58F6A4125625E0D3450AE324333C1FA551C2638166A51529` |
| new versioned `m1n1.bin` | `39543DDB1A2D88C7950AF67506821846D0D1C08BCDF5E606D9B040C6D703740B` |
| Session v preserved payload | `5DAEF3135B69FF754C21F353996597CA9CD872A043A2D4BC9599D87B972C1F4D` |
| unchanged passive wrapper | `2F060712F0DF54DE28D545E37461C55F49FE5DBCC90F0AA69ABEC15CE6B974FE` |

The new payload is stored at
`artifacts/p0-usb/payloads/ep0-stale-in-39543ddb/m1n1.bin`. The manifest names
that versioned path and binds it to the complete patch and source revision.

### Proposed single hardware validation (not executed)

Use a fresh DFU boot, a new directory
`artifacts/p0-usb/session-w-ep0-stale-in`, and execute one stage at a time only
after checking each actual result:

```powershell
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Checkm8 -OutputDirectory artifacts/p0-usb/session-w-ep0-stale-in
& .\windows-native\internal-storage\p0\Invoke-UsbBootStage.ps1 -Stage Pongo -OutputDirectory artifacts/p0-usb/session-w-ep0-stale-in
& .\windows-native\internal-storage\p0\Invoke-PassiveEnumerationTrace.ps1 -OutputDirectory artifacts/p0-usb/session-w-ep0-stale-in -ApprovedPayloadSha256 39543DDB1A2D88C7950AF67506821846D0D1C08BCDF5E606D9B040C6D703740B -ObservationSeconds 35
```

The existing identity, ordered USB(4)/HS04 location, artifact, driver and
safety gates remain mandatory. ETW starts before the wrapper switches to m1n1.
The wrapper adds no COM open, product/index-4 read, proxy request, reset,
re-enumeration or retry. It passively records the automatic descriptor,
configuration and CDC sequence for 35 seconds. A driver-gate failure, identity
or location mismatch, unexpected hash/state, or stage failure stops the session;
it is not automatically retried. Session v's boot is not reused.

| Result | Supported conclusion | Still unknown / next action |
| --- | --- | --- |
| A: same sequence; second GET succeeds with 7 bytes | the fix build passed this one observed transition and removed the Session-v boundary in this run | semantic equality of the seven bytes, reproducibility, COM/P_NOP and exact hardware race remain unproved; stop |
| B: same second GET still STALLs | this software fix is insufficient for the observed boundary | device STALL source and controller ordering remain unknown; stop |
| C: earliest failure moves | compare the new earliest failure with the previously successful prefix | do not call it overall success; stop and review the trace |
| D: sequence absent or correlation/evidence incomplete | no conclusion about the fix | record UNKNOWN; do not repeat automatically |

Even result A is only one passive enumeration result. COM configuration and
P_NOP belong to a later, separately reviewed test. Every result stops before
ANS initialization or NAND read/write. This hardware validation has not been
run, fresh DFU readiness is not assumed, and new execution approval is required.

The offline pre-execution record has now been materialized at
`artifacts/p0-usb/session-w-ep0-stale-in/PREEXECUTION.md` with SHA-256
`889F740F7414317E8B390CFAA93AA4D0B8D8604B48100469A66D4F80CC92F4BD`.
It fixes the executable/script/manifest/patch/payload paths, sizes and hashes,
records the three exact commands, and explicitly leaves DFU, live identity,
location and execution approval unsatisfied. No stage JSON or location binding
was fabricated during this preparation.

## Session w: stopped before Pongo transfer

The user reported a fresh DFU entry and explicitly approved the three Session w
commands. Checkm8 was executed once. Its saved record has status `passed`, the
A1625 identity gate passed, the exact instance used `libusbK`, and the ordered
location contained two entries. The existing handoff-stop behavior records
`exit_code=-1`; the script's Checkm8 success predicate nevertheless passed.
`Checkm8.json` SHA-256 is
`8922E24951F426EA4FFD1F1701EFC8B585B150886E4AD7586D5D79A86A3D9A20`,
and the saved `location.json` SHA-256 is
`A868892B6366ACD75B644C2736EDEEB8D124A3FC5A74CB62C700575A572EB6AB`.

The approved Pongo command was then invoked once and stopped in
`Invoke-UsbBootStage.ps1` at the pre-launch `Expected one target` gate. Because
that check precedes creation of the stage record and uploader launch, there is
no `Pongo.json` and no Pongo transfer from this invocation. A read-only inventory
immediately afterward found no 05AC:1227, 05AC:4141, or 1209:316D target.
`Payload.json` and `passive-enumeration` are also absent. The third command was
not run, and there was no retry, alternate route, COM/P_NOP, ANS initialization,
or NAND access.

The post-failure record is
`artifacts/p0-usb/session-w-ep0-stale-in/PONGO-PREFLIGHT-FAILURE.md`, SHA-256
`A503D4ADD02134572B001C435AACA60B1BAD5DCDDC92B230FE211572264C7357`.
Session w is closed at this pre-Pongo boundary. A new attempt must use a new
session directory, fresh DFU entry, live identity/location gates, and new
approval; the successful Session w Checkm8 record must not be reused as proof
for another connection.

## Session x: Checkm8 identity-descriptor failure

The user again reported fresh DFU and approved the three commands for a new
Session x directory. The Checkm8 command was run once. Its initial live gate
found one clean-DFU A1625 with the expected identity, `libusbK`, status OK, and
the same two-entry ordered physical location. The exploit process reported
Stage 1 and Stage 2 success, but subsequent DFU identity descriptor reads timed
out. Its bounded settling attempts ended at
`DFU_IDENTITY_REOPEN_LIMIT: three opened handles rejected before the next
exploit stage`; the process then reported that checkm8/YOLO failed or the device
left DFU and exited 1. `Checkm8.json` therefore records `failed`.

This is not a successful Checkm8 or YOLO transition. The approved Pongo and
passive-trace commands were not run. There is no `Pongo.json`, `Payload.json`,
or `passive-enumeration` directory, and the post-failure read-only inventory
found no 05AC:1227, 05AC:4141, or 1209:316D device. No retry, COM/P_NOP, ANS
initialization, or NAND access followed.

The Session x evidence hashes are `Checkm8.json`
`ED166E8B82982364DF19FE17D0E699E0D34F842E0B81F5C9F026234DDC170602`,
`location.json`
`A868892B6366ACD75B644C2736EDEEB8D124A3FC5A74CB62C700575A572EB6AB`,
stdout `C87B74825976AE2F777A5B3549EBAC82657BA8A3B0A0BD30B38F33FA360F587B`,
and empty stderr
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
The summarized failure record is
`artifacts/p0-usb/session-x-ep0-stale-in/CHECKM8-FAILURE.md`, SHA-256
`C972EB0E14C3243D87D7DD148B77F43F4545D5DE653DF0A3E74EF6343719409C`.
Session x is closed; another attempt requires fresh DFU, a new directory, and
new approval.
