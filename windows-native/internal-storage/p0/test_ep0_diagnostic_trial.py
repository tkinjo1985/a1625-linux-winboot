"""Static one-shot and persistence policy for the future hardware orchestrator."""
from pathlib import Path

HERE = Path(__file__).resolve().parent
script = (HERE / 'Invoke-Ep0DiagnosticTrial.ps1').read_text()

for required in (
    "throw 'Output directory exists; no automatic repeat'",
    "Approved payload hash mismatch",
    "$record.arm_attempts=1",
    "$record.com_open_attempts=1",
    "$record.report_attempts=1",
    "Run-Reader 'Arm'",
    "Run-Reader 'Report'",
    "'com-child-deadline'",
    "Get-PnpDevice -PresentOnly",
    "finally{",
    "$record|ConvertTo-Json -Depth 9|Set-Content $recordPath",
    "nop_requests=0;ans_requests=0;nand_requests=0",
):
    assert required in script

assert script.count("Run-Reader 'Arm'") == 1
assert script.count("Run-Reader 'Report'") == 1
assert script.count('Start-Process $python') == 1
for forbidden in ('P_NOP', 'IOCTL_USB_RESET', 'IOCTL_USB_HUB_CYCLE_PORT',
                  'Invoke-UsbBootStage', 'ans_init', 'nand_read'):
    assert forbidden not in script

print('EP0 diagnostic trial one-shot, timeline, artifact and failure-log policy passed')
