"""Offline product-string control and evidence-classification checks."""
from pathlib import Path
import json

HERE=Path(__file__).resolve().parent
helper=(HERE/'Read-Ep0Trace.c').read_text()
wrapper=(HERE/'Invoke-Ep0TraceRead.ps1').read_text()
trial=(HERE/'Invoke-StandardDescriptorTrial.ps1').read_text()

def classify(raw, api=None, timed_out=False, preflight=False):
    if preflight:return 'PRE_REQUEST_FAILURE'
    if timed_out:return 'HOST_DEADLINE_EXCEEDED'
    if not api or not api['ok']:return 'API_ERROR'
    if len(raw)<2 or raw[1]!=3 or raw[0]<2 or raw[0]&1 or raw[0]!=len(raw):return 'MALFORMED'
    return 'VALID_PRODUCT_VALUE' if raw[2:raw[0]].decode('utf-16le').startswith('m1n1 uartproxy ') else 'MALFORMED'

value='m1n1 uartproxy test';raw=bytes([2+len(value)*2,3])+value.encode('utf-16le')
assert classify(raw,{'ok':True})=='VALID_PRODUCT_VALUE'
assert classify(b'\x08\x03x',{'ok':True})=='MALFORMED'
assert classify(raw,{'ok':False,'error':31})=='API_ERROR'
assert classify(b'',timed_out=True)=='HOST_DEADLINE_EXCEEDED'
assert classify(b'',preflight=True)=='PRE_REQUEST_FAILURE'

for required in ('descriptor_entered','descriptor_returned','connection_info_entered',
                 'connection_info_returned','hub_open_returned','descriptor_malformed',
                 'error=ok?0:GetLastError()','fwrite(r->Data,1,raw_len,raw)',
                 '(product?2:4)','product?MAX_DESCRIPTOR:46'):
    assert required in helper
assert "[ValidateSet('Arm','Report','Product')]" in wrapper
assert "'HOST_DEADLINE_EXCEEDED'" in wrapper
assert "$text -ne $identity.product" in wrapper
assert "-Mode','Product'" in trial
assert 'passive_observation_seconds=35' in trial
assert trial.count("$record.tool_descriptor_requests=1")==1
for forbidden in ('-Mode\',\'Arm', 'P_NOP', 'IOCTL_USB_RESET', 'Invoke-Ep0DiagnosticTrial'):
    assert forbidden not in trial

print('standard product descriptor raw/error/timeout/malformed and one-request policy passed')
