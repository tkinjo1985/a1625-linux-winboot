"""Static policy and artifact checks for the COM-independent EP0 trace reader."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
source_path = HERE / 'Read-Ep0Trace.c'
wrapper_path = HERE / 'Invoke-Ep0TraceRead.ps1'
boot_wrapper_path = HERE / 'Invoke-UsbBootStage.ps1'
manifest_path = HERE / 'ep0-trace-reader-manifest.json'
patch_path = HERE / 'm1n1-p0.patch'

source = source_path.read_text()
wrapper = wrapper_path.read_text()
boot_wrapper = boot_wrapper_path.read_text()
patch = patch_path.read_text()
manifest = json.loads(manifest_path.read_text())

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

# The helper performs one identity query and one descriptor control-IN. It has
# no function-driver/COM handle, write path, reset or proxy transport.
assert source.count('IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX') == 1
assert source.count('IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION') == 1
assert 'r->SetupPacket.bmRequest=0x80;' in source
assert 'r->SetupPacket.bRequest=0x06;' in source
assert '(USB_STRING_DESCRIPTOR_TYPE<<8)|(product?2:4)' in source
assert 'product?MAX_DESCRIPTOR:46' in source
assert '(product?2:4)' in source
assert 'descriptor_entered' in source and 'descriptor_returned' in source
for forbidden in ('SetCommState', 'WriteFile(', 'IOCTL_USB_RESET',
                  'IOCTL_USB_HUB_CYCLE_PORT', 'libusb_', 'P_NOP'):
    assert forbidden not in source

# The wrapper binds the one read to the saved live target and cannot silently
# reuse an output or attempt the descriptor request twice.
for required in ("InstanceId -eq $identity.instance_id", "-ne 'usbser'",
                 "-notmatch '^m1n1 uartproxy '", "-ne $identity.parent",
                 'Compare-Object $savedLocation $location -SyncWindow 0',
                 "throw 'Output directory already exists; no automatic repeat'",
                 '$record.attempts=1', '$process.WaitForExit(5000)',
                 "[ValidateSet('Arm','Report','Product')]", "throw 'Diagnostic arm was not confirmed'",
                 "throw 'Report is stale, mismatched, or not frozen'",
                 'com_opens=0;proxy_requests=0;ans_requests=0;nand_requests=0'):
    assert required in wrapper
assert wrapper.count('Start-Process -FilePath $reader') == 1

# A future approval is bound to the exact diagnostic payload, not merely to the
# mutable manifest path or a prior session's authorization.
assert '[string]$ApprovedPayloadSha256' in boot_wrapper
assert "Approved payload hash is missing or does not match manifest" in boot_wrapper
assert '$ApprovedPayloadSha256 -ne $m.m1n1_bin_sha256' in boot_wrapper

# Manifest hashes bind the reviewed source and locally built executable.
assert sha256(ROOT / manifest['source']) == manifest['source_sha256'].upper()
assert sha256(ROOT / manifest['executable']) == manifest['executable_sha256'].upper()
assert manifest['com_opens'] == manifest['proxy_requests'] == 0
assert manifest['ans_requests'] == manifest['nand_requests'] == 0

# The device patch is P0-only and contains every fixed one-byte checkpoint.
assert '#define STRING_DESCRIPTOR_P0_EP0_TRACE 4' in patch
for marker in ('P0_EP0_SETUP_CONSUMED', 'P0_EP0_GET_HANDLER', 'P0_EP0_IN_ARMED',
               'P0_EP0_IN_COMPLETE', 'P0_EP0_STATUS_ARMED',
               'P0_EP0_STATUS_COMPLETE', 'P0_EP0_NEXT_SETUP'):
    assert marker in patch
assert 'u8 p0_ep0_trace;' in patch
assert '#define P0_EP0_FREEZE_USEC 45000000' in patch
assert 'P0_EP0_FROZEN' in patch and 'P0_EP0_RECONNECT_ATTEMPTED' in patch
assert patch.count('p0_ep0_poll(dev);') >= 3

print('EP0 trace helper, target gates, one-read policy and artifact hashes passed')
