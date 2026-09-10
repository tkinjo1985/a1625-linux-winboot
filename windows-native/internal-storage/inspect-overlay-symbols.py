"""Offline Mach-O named-import check; not a dyld execution/ABI test."""
import functools
import json
import os
import re
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'artifacts/diagnostic-ramdisk-research'
OVERLAY = RESEARCH / 'overlay-files'
BASE = RESEARCH / 'tvos-12.4/libraries/HopeG16M568.arm64UpdateRamDisk'
OBJDUMP = Path(os.environ['USERPROFILE']) / 'scoop/apps/msys2/current/ucrt64/bin/llvm-objdump.exe'


def resolve(name):
    if not name.startswith('/') or '..' in Path(name).parts:
        raise ValueError(f'unsupported dependency: {name}')
    for root in (OVERLAY, BASE):
        path = root / name.lstrip('/')
        if path.is_file():
            return path
    raise FileNotFoundError(name)


@functools.cache
def dependencies(path):
    data = path.read_bytes()
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError(f'not a little-endian 64-bit Mach-O: {path}')
    count, size = struct.unpack_from('<II', data, 16)
    end = 32 + size
    if end > len(data):
        raise ValueError('truncated load commands')
    result = []
    offset = 32
    for _ in range(count):
        cmd, length = struct.unpack_from('<II', data, offset)
        if length < 8 or offset + length > end:
            raise ValueError('invalid load command')
        if cmd in (12, 0x80000018, 0x8000001f):
            start = struct.unpack_from('<I', data, offset + 8)[0]
            if start < 24 or start >= length:
                raise ValueError('invalid dylib name offset')
            name = data[offset + start:offset + length].split(b'\0', 1)[0].decode()
            result.append((name, cmd))
        offset += length
    if offset != end:
        raise ValueError('load-command size mismatch')
    return result


def dump(path, flag):
    return subprocess.run([str(OBJDUMP), '--macho', flag, str(path)],
                          check=True, capture_output=True, text=True).stdout


@functools.cache
def exports(path):
    names = set()
    for line in dump(path, '--exports-trie').splitlines():
        fields = line.split()
        if fields and fields[0].startswith('0x') and len(fields) >= 2:
            names.add(fields[1])
        elif line.startswith('[re-export]'):
            match = re.fullmatch(r'\[re-export\] (\S+) \((?:(\S+) )?from (\S+)\)', line.strip())
            if not match:
                raise ValueError(f'unsupported symbol reexport: {line}')
            alias, original, library = match.groups()
            original = original or alias
            targets = [resolve(name) for name, _ in dependencies(path)
                       if short_name(name) == library]
            if len(targets) != 1 or original not in exports(targets[0]):
                raise ValueError(f'unresolved symbol reexport: {line}')
            names.add(alias)
    # Traverse only explicitly re-exported libraries, not all dependencies.
    for name, cmd in dependencies(path):
        if cmd == 0x8000001f:
            names.update(exports(resolve(name)))
    return names


def short_name(name):
    name = name.rsplit('/', 1)[-1]
    if '.dylib' in name:
        name = name.split('.', 1)[0]
    return name


def main():
    report = []
    for path in sorted(OVERLAY.rglob('*')):
        if not path.is_file():
            continue
        libs = {}
        for name, _ in dependencies(path):
            short = short_name(name)
            if short in libs:
                raise ValueError(f'ambiguous library name {short}')
            libs[short] = resolve(name)
        count = 0
        missing = []
        for flag in ('--bind', '--lazy-bind'):
            for line in dump(path, flag).splitlines():
                fields = line.split()
                if not fields or not fields[0].startswith('__'):
                    continue
                index = 5 if flag == '--bind' else 3
                lib, symbol = fields[index:index + 2]
                count += 1
                if lib not in libs or symbol not in exports(libs[lib]):
                    missing.append({'library': lib, 'symbol': symbol})
        report.append({'path': path.relative_to(OVERLAY).as_posix(),
                       'named_bind_entries': count, 'unresolved': missing})
    out = {'scope': 'overlay named bind/lazy-bind exports including library reexports; not full ABI or boot validation',
           'files': report}
    (RESEARCH / 'overlay-symbol-report.json').write_text(
        json.dumps(out, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
