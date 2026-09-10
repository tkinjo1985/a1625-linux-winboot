"""Prepare an offline inspection overlay. Does not edit an image or boot a device."""
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'artifacts/diagnostic-ramdisk-research'
SOURCE = RESEARCH / 'atvssh-6c05c8a.tar.gz'
EXPECTED = '9c9a9988272adfd0b7cce0cbee716c147cb2ccd9eaadd627a75c2f9f2dc8af55'
# Exact regular files; no host keys, mount helpers, restore tools or autostart.
FILES = (
    'bin/sh', 'bin/dd', 'usr/sbin/ioreg',
    'usr/local/bin/restored_external', 'usr/local/bin/dropbear',
    'usr/local/bin/dropbearkey', 'usr/lib/libncurses.5.4.dylib',
)


def main():
    source = SOURCE.read_bytes()
    if hashlib.sha256(source).hexdigest() != EXPECTED:
        raise ValueError('source archive hash mismatch')
    output = RESEARCH / 'minimal-overlay.tar'
    records = []
    # Assemble entirely in memory so a rejected input cannot leave a partial tar.
    buffer = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        members = archive.getmembers()
        with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as target:
            for name in FILES:
                matches = [m for m in members if m.name == name]
                if len(matches) != 1 or not matches[0].isfile():
                    raise ValueError(f'expected one regular file: {name}')
                member = matches[0]
                payload = archive.extractfile(member).read()
                if len(payload) != member.size or member.size > 2 * 1024 * 1024:
                    raise ValueError(f'unexpected file size: {name}')
                header = tarfile.TarInfo(name)
                header.size = len(payload)
                header.mode = 0o755
                header.uid = header.gid = header.mtime = 0
                target.addfile(header, io.BytesIO(payload))
                records.append({'path': name, 'size': len(payload),
                                'sha256': hashlib.sha256(payload).hexdigest()})
    data = buffer.getvalue()
    output.write_bytes(data)
    manifest = {
        'purpose': 'offline inspection only; not a boot-ready image',
        'source_sha256': EXPECTED,
        'overlay_sha256': hashlib.sha256(data).hexdigest(),
        'files': records,
        'missing': ['private runtime SSH host keys', 'audited startup entry point',
                    'complete dynamic symbol compatibility verification',
                    'kernel and firmware storage-write assessment'],
    }
    (RESEARCH / 'minimal-overlay.json').write_text(
        json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
