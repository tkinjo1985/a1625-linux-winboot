"""Regression: reused URB pointers must not cross-pair CDC completions."""
from pathlib import Path
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent

def event(time, opcode, irp, bm, request, value, index, length, nt='', status='0x40000000', xfer='0x7'):
    nt_data = f'<Data Name="fid_IRP_NtStatus">{nt}</Data>' if nt else ''
    return f'''<Event><System><EventID>{19+opcode}</EventID><Opcode>{opcode}</Opcode><TimeCreated SystemTime="{time}"/></System><EventData>
<Data Name="fid_UsbDevice">dev</Data><Data Name="fid_PipeHandle">pipe</Data><Data Name="fid_IRP_Ptr">{irp}</Data><Data Name="fid_URB_Ptr">urb-reused</Data>{nt_data}
<ComplexData Name="URB_FUNCTION_CONTROL_TRANSFER_EX"><Data Name="fid_URB_Hdr_Status">{status}</Data><Data Name="fid_URB_TransferBufferLength">{xfer}</Data>
<Data Name="fid_URB_Setup_bmRequestType">{bm}</Data><Data Name="fid_URB_Setup_bRequest">{request}</Data><Data Name="fid_URB_Setup_wValue">{value}</Data><Data Name="fid_URB_Setup_wIndex">{index}</Data><Data Name="fid_URB_Setup_wLength">{length}</Data></ComplexData></EventData></Event>'''

xml = '<Events>' + ''.join((
    event('2026-01-01T00:00:00.000Z', 1, 'irp-a', '0xA1', '0x21', '0x0', '0x2', '0x7'),
    event('2026-01-01T00:00:00.001Z', 2, 'irp-a', '0xA1', '0x21', '0x0', '0x2', '0x7', '0x0', '0x0'),
    event('2026-01-01T00:00:00.002Z', 1, 'irp-b', '0x21', '0x20', '0x0', '0x2', '0x7'),
    event('2026-01-01T00:00:00.003Z', 2, 'irp-b', '0x21', '0x20', '0x0', '0x2', '0x7', '0x0', '0x0'),
)) + '</Events>'

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'trace.xml'
    output = Path(directory) / 'analysis.json'
    source.write_text(xml)
    subprocess.run(['pwsh', '-NoProfile', '-File', str(HERE / 'Analyze-ComTrace.ps1'),
                    '-XmlPath', str(source), '-OutputPath', str(output)], check=True)
    result = json.loads(output.read_text(encoding='utf-8-sig'))

assert result['cdc_request_count'] == 2
assert [item['completion_count'] for item in result['requests']] == [1, 1]
assert result['requests'][0]['completions'][0]['irp'] == 'irp-a'
assert result['requests'][1]['completions'][0]['irp'] == 'irp-b'
assert result['requests'][1]['setup']['request'] == '0x20'
print('CDC trace pairing uses device/pipe/IRP/URB/exact SETUP, not reused URB alone')
