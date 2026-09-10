"""Prepare a compile/link-only ANS1 core; never install or load it."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'artifacts/ans-core-build'
OUT.mkdir(parents=True, exist_ok=True)
manifest = OUT / 'sources.json'
manifest.write_text(json.dumps({'status': 'preparing'}), encoding='utf-8')
subprocess.run([sys.executable, str(HERE / 'prepare-mailbox-build.py')], check=True)
subprocess.run([sys.executable, str(HERE / 'prepare-rtkit-build.py')], check=True)
names = ['ans1_block.c', 'ans1_block.h', 'ans1_dma.c', 'ans1_dma.h',
         'ans1_read_client.c', 'ans1_read_client.h', 'ans1_read.h',
         'ans1_queue.h', 'ans1_wire.h', 'ans1_reply.h', 'ans1_transaction.h',
         'ans1_geometry.h', 'ans1_firmware.c', 'ans1_firmware.h',
         'ans1_fw.h', 'ans1_fwsg.h', 'ans1_firmware_selftest.c',
         'ans1_reservation.c', 'ans1_reservation.h', 'ans1_power.c', 'ans1_power.h',
         'ans1_power_selftest.c', 'ans1_shmem.c', 'ans1_shmem.h',
         'ans1_rtkit_client.c', 'ans1_rtkit_client.h']
records = []
for name in names:
    raw = (HERE / name).read_bytes()
    generated = raw
    if name in ('ans1_read_client.c', 'ans1_shmem.c', 'ans1_rtkit_client.c'):
        needle = b'#include <linux/soc/apple/rtkit.h>'
        if raw.count(needle) != 1:
            raise ValueError('unexpected RTKit include')
        generated = raw.replace(needle, b'#include "apple-rtkit.h"')
    (OUT / name).write_bytes(generated)
    records.append({'name': name, 'source_sha256': hashlib.sha256(raw).hexdigest(),
                    'generated_sha256': hashlib.sha256(generated).hexdigest()})
header = (ROOT / 'artifacts/ans-rtkit-build/apple-rtkit.h').read_bytes()
(OUT / 'apple-rtkit.h').write_bytes(header)
(OUT / 'Makefile').write_text(
    '# Compile/link only: intentionally no module entry or device binding.\n'
    'obj-m += ans1_core.o\n'
    'ans1_core-y := ans1_block.o ans1_dma.o ans1_read_client.o ans1_firmware.o ans1_reservation.o ans1_power.o ans1_shmem.o ans1_rtkit_client.o\n'
    'obj-m += ans1_fw_check.o\n'
    'ans1_fw_check-y := ans1_firmware_selftest.o ans1_firmware.o ans1_reservation.o\n'
    'obj-m += ans1_power_check.o\n'
    'ans1_power_check-y := ans1_power_selftest.o ans1_power.o\n', encoding='utf-8')
manifest.write_text(json.dumps({'status': 'prepared', 'files': records,
    'rtkit_header_sha256': hashlib.sha256(header).hexdigest(),
    'build_target': 'ans1_core.o', 'hardware_binding': False}, indent=2), encoding='utf-8')
print(f'Prepared compile/link-only core: {OUT}')
