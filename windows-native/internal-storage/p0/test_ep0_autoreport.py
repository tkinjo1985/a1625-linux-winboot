"""Host model and source-policy tests for the one-shot P0 EP0 report."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = (HERE.parents[2] / 'third_party/HoolockLinux-m1n1-p0/src/usb_dwc2.c').read_text()

VALID, ARMED, FROZEN, DISCONNECTED, RECONNECTED = 1, 2, 4, 8, 16
SETUP, HANDLER, IN_ARMED, IN_DONE, STATUS_ARMED, STATUS_DONE, NEXT_SETUP = (1 << i for i in range(7))

class Record:
    def __init__(self):
        self.flags = self.trace = 0
        self.boot = 0
        self.generation = 0
        self.disconnects = self.reconnects = 0

    def arm(self, boot):
        if self.flags & VALID:
            return False
        self.boot, self.generation = boot, 1
        self.flags = VALID | ARMED
        return True

    def mark(self, bit):
        if self.flags & (ARMED | FROZEN) == ARMED:
            self.trace |= bit

    def timeout(self):
        if self.flags & (ARMED | FROZEN) == ARMED:
            self.flags |= FROZEN | DISCONNECTED
            self.disconnects += 1

    def reconnect(self):
        if self.flags & DISCONNECTED and not self.flags & RECONNECTED:
            self.flags |= RECONNECTED
            self.reconnects += 1


cases = {
    'setup_not_seen': 0,
    'handler_only': SETUP | HANDLER,
    'in_armed_no_completion': SETUP | HANDLER | IN_ARMED,
    'out_status_not_complete': SETUP | HANDLER | IN_ARMED | IN_DONE | STATUS_ARMED,
    'normal': SETUP | HANDLER | IN_ARMED | IN_DONE | STATUS_ARMED | STATUS_DONE | NEXT_SETUP,
}
for expected in cases.values():
    record = Record()
    assert record.arm(0x12345678)
    for bit in (SETUP, HANDLER, IN_ARMED, IN_DONE, STATUS_ARMED, STATUS_DONE, NEXT_SETUP):
        if expected & bit:
            record.mark(bit)
    record.timeout()
    frozen = record.trace
    record.mark(NEXT_SETUP)       # later SETUP cannot alter frozen evidence
    record.reconnect()
    record.reconnect()            # one shot
    assert record.trace == frozen == expected
    assert record.disconnects == record.reconnects == 1
    assert not record.arm(0x87654321)

unarmed = Record()
unarmed.timeout()
assert unarmed.flags == 0                         # arm-not-established
armed_unseen = Record()
assert armed_unseen.arm(1)
armed_unseen.timeout()
assert armed_unseen.trace == 0 and armed_unseen.flags & FROZEN

# The actual P0 implementation gates checkpoint mutation, polls both outside
# and inside the interrupt loop, uses the already-established DCTL bit, and
# has finite endpoint-abort waits. Reset does not clear the diagnostic record.
assert '#define P0_EP0_MARK' in SRC
assert SRC.count('p0_ep0_poll(dev);') >= 3
assert 'DWC2_DCTL_SftDisCon' in SRC
assert '#define P0_EP_ABORT_USEC 10000' in SRC
assert '.iConfiguration = 0,' in SRC
assert 'cdc_configuration_descriptor.configuration.iConfiguration =' in SRC
reset = SRC.split('static void usb_dwc2_handle_usbrst', 1)[1].split('static void usb_dwc2_ep_abort', 1)[0]
for field in ('p0_ep0_trace =', 'p0_ep0_flags =', 'p0_ep0_boot_id =', 'p0_ep0_generation ='):
    assert field not in reset

print('P0 EP0 arm/freeze/one-shot report model and source policy passed')
