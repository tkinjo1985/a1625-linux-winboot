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
