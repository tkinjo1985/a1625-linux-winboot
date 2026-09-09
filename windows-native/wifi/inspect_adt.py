"""Read an Apple Device Tree RAM dump without printing private property values.

Wire format reference: HoolockLinux/m1n1 src/adt.h. No Apple data is bundled.
"""
import argparse
import json
import struct
from pathlib import Path


def parse(data):
    nodes = {}
    offset = 0

    def take(size):
        nonlocal offset
        if size < 0 or offset + size > len(data):
            raise ValueError("Truncated ADT")
        value = data[offset:offset + size]
        offset += size
        return value

    def node(parent, depth):
        if depth > 64 or len(nodes) > 10000:
            raise ValueError("ADT complexity limit exceeded")
        properties, children = struct.unpack('<II', take(8))
        if properties > 4096 or children > 4096:
            raise ValueError("Invalid ADT counts")
        props = {}
        for _ in range(properties):
            key = take(32).split(b'\0', 1)[0].decode('ascii')
            size = struct.unpack('<I', take(4))[0] & 0x7fffffff
            if key in props:
                raise ValueError("Duplicate ADT property")
            props[key] = take(size)
            take((-size) % 4)
        name = props.get('name', b'').rstrip(b'\0').decode('ascii')
        if not name or '/' in name and depth:
            raise ValueError("Invalid ADT node name")
        path = '/' if depth == 0 else parent.rstrip('/') + '/' + name
        if path in nodes:
            raise ValueError("Duplicate ADT path")
        nodes[path] = props
        for _ in range(children):
            node(path, depth + 1)

    node('', 0)
    return nodes


def summarize(nodes):
    root = nodes.get('/', {})
    if (root.get('model', b'').rstrip(b'\0') != b'AppleTV5,3'
            or root.get('target-type', b'').rstrip(b'\0') != b'J42d'):
        raise ValueError('Expected AppleTV5,3 / J42d ADT')
    # Deliberate allowlist: never serialize calibration, MAC, serial or NVRAM.
    allowed = {'name', 'compatible', 'device_type', 'reg', 'ranges',
               'interrupts', 'interrupt-parent', '#address-cells', '#size-cells',
               'clock-gates', 'power-gates', 'apcie-port', 'msi-address',
               'msi-vector-offset', 'msi-vector-base', '#msi-vectors',
               't-refclk-to-perst', 'maximum-link-speed', 'page-size',
               'function-reg_on', 'function-perst', 'function-clkreq',
               'function-device_wake'}
    result = {}
    for path, props in nodes.items():
        if any(word in path.lower() for word in ('wlan', 'wifi', 'pcie', 'sdio')):
            result[path] = {
                key: (value.rstrip(b'\0').decode('ascii', errors='replace')
                      if key in {'name', 'compatible', 'device_type'} else value.hex())
                for key, value in props.items() if key in allowed
            }
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    args = parser.parse_args()
    if args.dump.stat().st_size > 16 * 1024 * 1024:
        parser.error('ADT exceeds 16 MiB limit')
    print(json.dumps(summarize(parse(args.dump.read_bytes())), indent=2))
