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
