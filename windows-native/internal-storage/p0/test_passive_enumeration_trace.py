"""Static safety and ordering checks for the future passive enumeration trace."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
script = (HERE / 'Invoke-PassiveEnumerationTrace.ps1').read_text()

for required in (
    "throw 'Payload stage already recorded; no automatic repeat'",
    "throw 'Prior boot stage did not pass'",
    "Approved payload hash mismatch",
    "P0 artifact gate failed",
    "Stamp 'etw-started-before-payload'",
    "Stamp 'payload-stage-started'",
    "'-Stage','Payload'",
    "Stamp 'passive-observation-started'",
    "Payload stage exceeded 150-second host deadline",
    "payload_exit_code",
    "timeline.etl",
    "timeline.xml",
    "tool_descriptor_requests=0;index4_requests=0;com_opens=0;proxy_requests=0;nop_requests=0;ans_requests=0;nand_requests=0",
):
    assert required in script

assert script.index("Stamp 'etw-started-before-payload'") < script.index("Stamp 'payload-stage-started'")
assert script.count("'-Stage','Payload'") == 1
assert script.count('Start-Process $powershell') == 1
for forbidden in ('Invoke-StandardDescriptorTrial', 'Invoke-Ep0TraceRead',
                  'Invoke-TracedComOpen', 'IOCTL_USB_RESET', 'P_NOP'):
    assert forbidden not in script

print('passive trace starts before one payload stage and adds no active USB request')
