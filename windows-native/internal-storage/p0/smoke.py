"""Run ONLY on an independently verified P0 m1n1 proxy, never on Linux.

Requires an explicit serial port. Does not reboot, load firmware or free DMA.
The caller must capture the device console and verify the loaded build hash.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', required=True)
    parser.add_argument('--loaded-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(Path(__file__).with_name('build-manifest.json').read_text())
    if not manifest.get('execution_authorized', False):
        parser.error('hardware execution is on hold: firmware-internal selector prohibition is unproven')
    if args.loaded_sha256 != manifest['m1n1_bin_sha256']:
        parser.error('loaded build hash differs from P0 manifest')
    args.output.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(ROOT / 'third_party/HoolockLinux-m1n1-p0/proxyclient'))
    # Avoid m1n1.setup, which has unrelated hardware initialization side effects.
    from m1n1.proxy import UartInterface, M1N1Proxy
    iface = UartInterface(args.port)
    console = (args.output / 'console.log').open('w', encoding='utf-8')
    iface.tty_log = console
    p = M1N1Proxy(iface)
    result = {'status': 'running', 'build_sha256': args.loaded_sha256,
              'reads': [], 'shutdown_confirmed': False, 'tvos_cold_boot': 'unverified'}
    try:
        # Buffers remain allocated through this boot, including on transport loss.
        buf = p.memalign(4096, 4096)
        if not buf or buf & 4095 or buf >> 44:
            raise RuntimeError('invalid aligned read buffer')
        if not p.ans1_init():
            raise RuntimeError('ANS1 init/IDENTIFY failed; no retries')
        if not p.request(p.P_ANS1_RESERVED, buf):
            raise RuntimeError('IDENTIFY copy failed')
        (args.output / 'identify.bin').write_bytes(iface.readmem(buf, 128))
        expected = {}
        for repetition in range(2):
            for lba in (0, 1):
                if not p.ans1_read(lba, buf):
                    raise RuntimeError('READ failed; no retries')
                data = iface.readmem(buf, 4096)
                if len(data) != 4096:
                    raise RuntimeError('short host transfer')
                digest = hashlib.sha256(data).hexdigest()
                (args.output / f'lba{lba}-read{repetition}.bin').write_bytes(data)
                result['reads'].append({'lba': lba, 'repetition': repetition,
                                        'bytes': len(data), 'sha256': digest})
                if lba in expected and expected[lba] != digest:
                    raise RuntimeError('repeated READ hash mismatch')
                expected[lba] = digest
                if lba == 1 and data[:8] != b'EFI PART':
                    raise RuntimeError('LBA 1 lacks EFI PART signature')
        result['status'] = 'read_checks_passed'
    except Exception as exc:
        result['status'] = 'failed'
        result['error'] = str(exc)
    finally:
        try:
            result['shutdown_confirmed'] = bool(p.ans1_shutdown())
        except Exception as exc:
            result['shutdown_error'] = str(exc)
        if not result['shutdown_confirmed']:
            result['status'] = 'failed'
        (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        iface.dev.close()
        console.close()
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'read_checks_passed' else 1

if __name__ == '__main__':
    raise SystemExit(main())
