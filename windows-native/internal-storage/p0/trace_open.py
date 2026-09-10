"""One approved COM open. No proxy sends: record configuration outcome and close."""
import hashlib
import json
from pathlib import Path
import sys
import traceback

def main():
    identity_path, output_path = map(Path, sys.argv[1:])
    output_path.mkdir(exist_ok=False)
    result = {'mode':'P0-USB COM-open identification','com_open_attempts':0,
              'com_configured':False,'nop_requests':0,'ans_requests':0,
              'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    port = None
    def save():
        (output_path/'result.json').write_text(json.dumps(result,indent=2))
    save()
    try:
        import serial
        from serial.tools.list_ports import comports
        ident = json.loads(identity_path.read_text(encoding='utf-8-sig'))
        if isinstance(ident, list):
            if len(ident) != 1:
                raise RuntimeError(f'Expected one inventory candidate, found {len(ident)}')
            ident = ident[0]
        result['identity_sha256']=hashlib.sha256(identity_path.read_bytes()).hexdigest()
        matches=[p for p in comports() if p.device==ident['port']]
        if len(matches)!=1 or (matches[0].vid,matches[0].pid,matches[0].serial_number)!=(0x1209,0x316d,ident['serial']):
            raise RuntimeError('Port descriptor mismatch')
        port=serial.Serial(port=None,baudrate=115200,bytesize=8,parity='N',stopbits=1,
                           timeout=.1,write_timeout=3,xonxoff=False,rtscts=False,dsrdtr=False)
        port.dtr=True;port.rts=False;port.port=ident['port']
        result['com_open_attempts']=1;save()
        port.open()
        result['com_configured']=True
    except Exception:
        result['exception']=traceback.format_exc()
        (output_path/'exception.txt').write_text(result['exception'])
    finally:
        try:
            if port is not None and port.is_open:port.close()
        except Exception:result['close_exception']=traceback.format_exc()
        save()
    print(json.dumps(result))

if __name__=='__main__':main()
