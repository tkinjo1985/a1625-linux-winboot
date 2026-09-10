"""P0-USB only. Sends at most three fixed P_NOP frames, no other proxy opcode.

Run after matching a fresh PnP inventory to the new boot's USB connection.
No m1n1 imports, initialization, ANS cleanup, reconnect, or retry on failure.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import time
import traceback


def checksum(data):
    value = 0xDEADBEEF
    for byte in data:
        value = (value * 31337 + (byte ^ 0x5A)) & 0xFFFFFFFF
    return value ^ 0xADDEDBAD


def nop_frame():
    body = struct.pack('<I7Q', 0x01AA55FF, 0, 0, 0, 0, 0, 0, 0)
    return body + struct.pack('<I', checksum(body))


def receive_nop(port, log):
    deadline = time.monotonic() + 3
    data = bytearray()
    magic = struct.pack('<I', 0x01AA55FF)
    while time.monotonic() < deadline and len(data) < 65536:
        part = port.read(1)
        if not part:
            continue
        log.write(part)
        data.extend(part)
        start = data.find(magic)
        if start >= 0 and len(data) >= start + 36:
            reply = data[start:start + 36]
            if checksum(reply[:-4]) != struct.unpack('<I', reply[-4:])[0]:
                raise RuntimeError('P_NOP reply checksum mismatch')
            outer, opcode, status, retval = struct.unpack('<iQqQ', reply[4:-4])
            if outer or opcode or status:
                raise RuntimeError('P_NOP reply status/opcode mismatch')
            return {'opcode': opcode, 'status': status, 'retval': retval}
    raise TimeoutError('P_NOP response deadline or 64 KiB receive budget exhausted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', type=Path, required=True,
                        help='Reviewed current-boot identity JSON, not a COM number alone')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--artifact', type=Path, action='append', required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    result = {'mode': 'P0-USB', 'status': 'starting', 'com_configured': False,
              'nop_attempts': 0, 'replies': [], 'ans_requests': 0,
              'nand_read_requests': 0, 'hashes': {}, 'usb_trace': 'not captured'}
    port = None
    with (args.output / 'rx.bin').open('wb') as rx:
        try:
            for path in [Path(__file__), args.identity, *args.artifact]:
                result['hashes'][str(path.resolve())] = hashlib.sha256(path.read_bytes()).hexdigest()
            identity = json.loads(args.identity.read_text(encoding='utf-8-sig'))
            result['identity'] = identity
            required = ('port', 'instance_id', 'interface', 'location', 'product', 'serial',
                        'driver', 'pnp_status', 'current_boot_verified')
            if any(not identity.get(key) and identity.get(key) != 0 for key in required):
                raise ValueError('Incomplete port identity; no packet sent')
            if (identity.get('vid'), identity.get('pid')) != (0x1209, 0x316D):
                raise ValueError('Unexpected descriptor VID/PID')
            if identity['interface'] not in (0, 2) or identity['driver'].lower() != 'usbser':
                raise ValueError('Unexpected CDC interface/driver')
            if identity['pnp_status'] != 'OK' or identity['current_boot_verified'] is not True:
                raise ValueError('Current boot binding not verified')
            inventory_script = Path(__file__).with_name('Collect-TransportInventory.ps1')
            result['hashes'][str(inventory_script.resolve())] = hashlib.sha256(inventory_script.read_bytes()).hexdigest()
            inventory_path = args.output / 'live-inventory.json'
            subprocess.run(['powershell.exe', '-NoProfile', '-File', str(inventory_script),
                            '-OutputPath', str(inventory_path)], check=True, timeout=20,
                           capture_output=True)
            candidates = json.loads(inventory_path.read_text(encoding='utf-8-sig'))
            live = [c for c in candidates if c['instance_id'] == identity['instance_id']]
            if len(live) != 1 or any(live[0][key] != identity[key] for key in
                                    ('port', 'interface', 'location', 'product', 'serial', 'driver', 'pnp_status')):
                raise ValueError('Fresh PnP identity mismatch or unproven interface; no packet sent')
            import serial
            from serial.tools.list_ports import comports
            matches = [p for p in comports() if p.device == identity['port']]
            if len(matches) != 1:
                raise ValueError('Selected port missing or ambiguous')
            found = matches[0]
            if (found.vid, found.pid, found.serial_number) != (identity['vid'], identity['pid'], identity['serial']):
                raise ValueError('Live port descriptor mismatch')
            # Results exist before Serial.open / SetCommState can fail.
            (args.output / 'result.json').write_text(json.dumps(result, indent=2))
            port = serial.Serial(port=None, baudrate=115200, bytesize=8, parity='N',
                                 stopbits=1, timeout=0.1, write_timeout=3,
                                 xonxoff=False, rtscts=False, dsrdtr=False)
            port.dtr = True
            port.rts = False
            port.port = identity['port']
            port.open()
            result['com_configured'] = True
            for _ in range(3):
                result['nop_attempts'] += 1
                frame = nop_frame()
                if port.write(frame) != len(frame):
                    raise IOError('Short P_NOP write')
                result['replies'].append(receive_nop(port, rx))
            result['status'] = 'passed'
        except Exception:
            result['status'] = 'failed'
            result['exception'] = traceback.format_exc()
            (args.output / 'exception.txt').write_text(result['exception'])
        finally:
            try:
                if port is not None and port.is_open:
                    port.close()
            except Exception:
                result['close_exception'] = traceback.format_exc()
                result['status'] = 'failed'
            (args.output / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({'status': result['status'], 'nop_attempts': result['nop_attempts'],
                      'ans_requests': 0, 'result': str(args.output / 'result.json')}))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
