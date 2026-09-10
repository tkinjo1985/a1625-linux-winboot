"""Check direct startup references in the actual P0-compiled main object."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[3]
objdump = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/llvm-objdump.exe'
obj = ROOT / 'third_party/HoolockLinux-m1n1-p0/build/main.o'
relocations = subprocess.check_output([str(objdump), '-r', str(obj)], text=True)
for name in ('payload_run', 'sep_init', 'nvme_shutdown', 'mmu_shutdown'):
    if any(line.split()[-1:] == [name] for line in relocations.splitlines()):
        raise SystemExit(f'P0 startup still references {name}')
assert any(line.split()[-1:] == ['uartproxy_run'] for line in relocations.splitlines())
print('Compiled P0 main references proxy and omits direct payload/SEP/next-stage shutdown calls')
