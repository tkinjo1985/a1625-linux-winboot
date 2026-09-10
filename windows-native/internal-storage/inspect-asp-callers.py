"""List direct branches to the verified 16M568 ASP ExecuteCommand function."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

EXPECTED = '935841b4ef66f868ffc85a4c10604a3416e4de88ff0aa9c518e5a63eaef7fc68'
TARGET = 0xfffffff006d9c2e0


def inspect(path):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != EXPECTED:
        raise ValueError('requires the exact AppleTV5,3 16M568 research kernel')
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('unexpected Mach-O format')
    count, command_bytes = struct.unpack_from('<II', data, 16)
    offset = 32
    segments = []
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > 32 + command_bytes:
            raise ValueError('invalid load command')
        if cmd == 25:
            name = data[offset + 8:offset + 24].rstrip(b'\0').decode()
            va, _, start, length = struct.unpack_from('<QQQQ', data, offset + 24)
            if name in ('__TEXT_EXEC', '__PLK_TEXT_EXEC'):
                if start + length > len(data) or length % 4:
                    raise ValueError('invalid code segment')
                segments.append((name, va, start, length))
        offset += size
    if len(segments) != 2:
        raise ValueError('missing expected code segments')
    branches = []
    for name, va, start, length in segments:
        for off in range(start, start + length, 4):
            instruction = struct.unpack_from('<I', data, off)[0]
            if instruction & 0x7c000000 != 0x14000000:
                continue
            immediate = instruction & 0x3ffffff
            if immediate & (1 << 25):
                immediate -= 1 << 26
            address = va + off - start
            if address + 4 * immediate == TARGET:
                branches.append({'address': hex(address), 'file_offset': hex(off),
                                 'kind': 'BL' if instruction >> 31 else 'B',
                                 'segment': name})
    return {'kernel_sha256': EXPECTED, 'target': hex(TARGET),
            'scope': 'direct B/BL in two code segments only; does not prove absence of indirect calls or alternate send paths',
            'branches': branches,
            'absolute_pointer_byte_matches': data.count(struct.pack('<Q', TARGET))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kernel', type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.kernel), indent=2))
