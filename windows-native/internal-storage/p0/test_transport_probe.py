"""Fault injection with no USB access: open failure and bounded fixed P_NOPs."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import types
from unittest.mock import patch

path = Path(__file__).with_name('transport_probe.py')
spec = importlib.util.spec_from_file_location('probe', path)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

identity = dict(port='COM999',instance_id='mock',interface=0,location=['mock'],product='mock',
                serial='mock',driver='usbser',pnp_status='OK',current_boot_verified=True,
                vid=0x1209,pid=0x316D)
class Port:
    fail_open = False
    writes = []
    def __init__(self, **kw):
        assert kw['port'] is None and kw['write_timeout'] == 3 and kw['timeout'] == .1
        self.is_open = False
        self.rx = bytearray()
    def open(self):
        assert self.dtr and not self.rts
        if self.fail_open:
            raise OSError(31, 'injected SetCommState failure')
        self.is_open = True
    def write(self, frame):
        assert frame == probe.nop_frame()
        self.writes.append(frame)
        reply = struct.pack('<IiQqQ', 0x01AA55FF, 0, 0, 0, 0)
        self.rx.extend(reply + struct.pack('<I', probe.checksum(reply)))
        return len(frame)
    def read(self, size):
        data = bytes(self.rx[:size]);del self.rx[:size];return data
    def close(self):
        self.is_open = False

def inventory(argv, **kw):
    Path(argv[-1]).write_text(json.dumps([identity]))

mods = {'serial': types.SimpleNamespace(Serial=Port),
        'serial.tools': types.ModuleType('serial.tools'),
        'serial.tools.list_ports': types.SimpleNamespace(comports=lambda:[types.SimpleNamespace(
            device='COM999',vid=0x1209,pid=0x316D,serial_number='mock')])}
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    identity_path = root/'identity.json';identity_path.write_text(json.dumps(identity))
    for fail in (True,False):
        Port.fail_open=fail;Port.writes=[]
        output=root/str(fail)
        argv=['probe','--identity',str(identity_path),'--output',str(output),'--artifact',str(path)]
        with patch.object(sys,'argv',argv),patch.dict(sys.modules,mods),patch.object(probe.subprocess,'run',inventory),contextlib.redirect_stdout(io.StringIO()):
            code=probe.main()
        result=json.loads((output/'result.json').read_text())
        assert code==int(fail) and result['ans_requests']==0
        assert result['nop_attempts']==(0 if fail else 3)
        assert len(Port.writes)==(0 if fail else 3)
        assert (output/'exception.txt').exists()==fail
print('COM-open failure persisted; successful mock sends exactly three P_NOPs and zero ANS requests')
