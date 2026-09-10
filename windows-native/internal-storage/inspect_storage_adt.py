"""Offline, allowlisted ANS inventory from an owned A1625 RAM ADT capture.

This does not access MMIO, send mailbox messages, or read internal NAND.
Raw ADT input remains private; only selected topology properties are emitted.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'wifi'))
from inspect_adt import parse


def words(props, key, width=4):
    value = props.get(key, b'')
    if not value or len(value) % width:
        raise ValueError(f'Missing or malformed {key}')
    return list(struct.unpack('<' + ('I' if width == 4 else 'Q') * (len(value) // width), value))


def summarize(nodes):
    root = nodes.get('/', {})
    if (root.get('model') != b'AppleTV5,3\0'
            or root.get('target-type') != b'J42d\0'):
        raise ValueError('Expected AppleTV5,3 / J42d')
    arm = nodes.get('/arm-io', {})
    ans = nodes.get('/arm-io/ans', {})
    nub = nodes.get('/arm-io/ans/iop-ans-nub', {})
    if ans.get('compatible') != b'iop,s5l8960x\0':
        raise ValueError('Unexpected ANS compatible')
    if nub.get('compatible') != b'iop-nub,rtbuddy\0':
        raise ValueError('Unexpected ANS nub compatible')
    for props in (root, arm):
        if words(props, '#address-cells') != [2] or words(props, '#size-cells') != [2]:
            raise ValueError('Unsupported address/size cell layout')
    ranges = words(arm, 'ranges', 8)
    registers = words(ans, 'reg', 8)
    if len(ranges) % 3 or len(registers) % 2:
        raise ValueError('Malformed ranges/reg tuples')
    windows = []
    for i in range(0, len(ranges), 3):
        child, parent, size = ranges[i:i+3]
        if not size or child + size > 2**64 or parent + size > 2**64:
            raise ValueError('Invalid bus range')
        windows.append((child, parent, size))
    decoded = []
    for i in range(0, len(registers), 2):
        address, size = registers[i:i+2]
        if not size or address + size > 2**64:
            raise ValueError('Invalid register range')
        matches = [(parent + address - child) for child, parent, span in windows
                   if child <= address and address + size <= child + span]
        if len(matches) != 1:
            raise ValueError('Register must map through exactly one arm-io range')
        decoded.append({'bus_address': hex(address), 'physical_address': hex(matches[0]),
                        'size': hex(size)})
    # No generic dump of property names or values: unknown fields stay private.
    properties = {key: [hex(v) for v in words(ans, key)] for key in (
        'interrupt-parent', 'interrupts', 'clock-gates', 'power-gates',
        'clock-ids', 'iop-version', 'ps-reg-offset', 'sf-ps-reg-offset')}
    return {'schema_version': 1, 'target': {'product': 'AppleTV5,3', 'board': 'J42d'},
            'source_kind': 'RAM Apple Device Tree; not live IORegistry or NAND evidence',
            'ans': {'path': '/arm-io/ans', 'compatible': 'iop,s5l8960x',
                    'registers': decoded, 'properties': properties},
            'nub': {'path': '/arm-io/ans/iop-ans-nub', 'compatible': 'iop-nub,rtbuddy'},
            'unverified': ['Linux IRQ and power-domain mapping', 'RTBuddy live state and protocol',
                           'ASP endpoints and block commands', 'disk capacity and block size',
                           'GPT/APFS topology and reference sector hashes']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    args = parser.parse_args()
    with args.dump.open('rb') as stream:
        data = stream.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        parser.error('ADT exceeds 16 MiB limit')
    print(json.dumps(summarize(parse(data)), indent=2))


if __name__ == '__main__':
    main()
