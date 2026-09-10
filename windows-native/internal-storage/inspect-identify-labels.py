"""Read diagnostic labels from the exact A1625 16M568 research kernel."""
import hashlib
import json
from pathlib import Path
import struct
import sys

data = Path(sys.argv[1]).read_bytes()
expected = '935841b4ef66f868ffc85a4c10604a3416e4de88ff0aa9c518e5a63eaef7fc68'
if hashlib.sha256(data).hexdigest() != expected:
    raise ValueError('unexpected research kernel hash')
segments = []
symtab = None
offset = 32
for _ in range(struct.unpack_from('<I', data, 16)[0]):
    command, size = struct.unpack_from('<II', data, offset)
    if command == 25:
        va, _, fileoff, filesize = struct.unpack_from('<QQQQ', data, offset + 24)
        segments.append((va, fileoff, filesize))
    elif command == 2:
        symtab = struct.unpack_from('<IIII', data, offset + 8)
    offset += size

def read_string(va):
    for base, start, size in segments:
        if base <= va < base + size:
            pos = start + va - base
            end = data.index(b'\0', pos, min(pos + 256, start + size))
            return data[pos:end].decode('ascii')
    raise ValueError('unmapped string')

def read_pointer(va):
    for base, start, size in segments:
        if base <= va <= base + size - 8:
            return struct.unpack_from('<Q', data, start + va - base)[0]
    raise ValueError('unmapped pointer')

target = read_pointer(0xfffffff006fd98e8)
symbols = []
if symtab is None:
    raise ValueError('missing symbol table')
symoff, count, stroff, strsize = symtab
for index in range(count):
    name, _, _, _, value = struct.unpack_from('<IBBHQ', data, symoff + index * 16)
    if value == target and name < strsize:
        pos = stroff + name
        symbols.append(data[pos:data.index(b'\0', pos, stroff + strsize)].decode('ascii'))
print(json.dumps({'kernel_sha256': expected,
    'command_clear_stub_target': hex(target), 'command_clear_symbols': symbols,
    'labels': {
    hex(va): read_string(va) for va in
    (0xfffffff006340954, 0xfffffff006340964, 0xfffffff00634098a,
     0xfffffff0063409b6, 0xfffffff0063409e2, 0xfffffff006340a0e,
     0xfffffff006340a41)}}, indent=2))
