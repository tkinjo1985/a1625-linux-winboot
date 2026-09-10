"""Regenerate pinned drafts and run host tests. Never communicates with hardware."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
out = ROOT / 'artifacts/ans-offline-tests'
out.mkdir(parents=True, exist_ok=True)
report = out / 'results.json'
# Invalidate an earlier success before starting any child process.
report.write_text(json.dumps({'status': 'running', 'hardware_validation': False}), encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
results = []


def run(name, command):
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    results.append({'name': name, 'returncode': completed.returncode,
                    'stdout': completed.stdout, 'stderr': completed.stderr})
    print(f'{name}: {"PASS" if completed.returncode == 0 else "FAIL"}', flush=True)
    if completed.returncode:
        raise RuntimeError(name + ' failed: ' + completed.stderr + completed.stdout)


status = 'failed'
try:
    for name in ('prepare-mailbox-build.py', 'prepare-rtkit-build.py'):
        run(name, [sys.executable, str(HERE / name)])
    for name in ('wire', 'read', 'reply', 'transaction', 'fw', 'fwsg', 'clock', 'queue', 'geometry'):
        exe = out / f'test_ans1_{name}.exe'
        run(f'compile-{name}', [str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror',
            '-O2', str(HERE / f'test_ans1_{name}.c'), '-o', str(exe)])
        run(name, [str(exe)])
    for name in ('retry', 'buffer', 'hello', 'syslog', 'owner_guard'):
        run(f'rtkit-{name}', [sys.executable, str(HERE / f'test_rtkit_{name}.py')])
    run('mailbox-send', [sys.executable, str(HERE / 'test_mailbox_send.py')])
    run('mailbox-receive', [sys.executable, str(HERE / 'test_mailbox_receive.py')])
    run('mailbox-start', [sys.executable, str(HERE / 'test_mailbox_start.py')])
    run('block-request', [sys.executable, str(HERE / 'test_block_request.py')])
    run('selftest-stop', [sys.executable, str(HERE / 'test_selftest_stop.py')])
    run('read-client', [sys.executable, str(HERE / 'test_read_client.py')])
    run('dma-owner', [sys.executable, str(HERE / 'test_dma.py')])
    run('shared-memory-owner', [sys.executable, str(HERE / 'test_shmem.py')])
    run('rtkit-client-adapter', [sys.executable, str(HERE / 'test_rtkit_client.py')])
    run('reservation', [sys.executable, str(HERE / 'test_reservation.py')])
    run('power', [sys.executable, str(HERE / 'test_power.py')])
    status = 'passed'
finally:
    paths = sorted(p for p in HERE.iterdir() if p.suffix in ('.c', '.h', '.py', '.patch'))
    document = {
        'status': status,
        'completed_utc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Host mocks and codecs only; excludes kernel compilation and hardware',
        'hardware_validation': False,
        'compiler': str(gcc),
        'compiler_sha256': hashlib.sha256(gcc.read_bytes()).hexdigest(),
        'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
        'checks': results,
    }
    report.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')
print(report)
