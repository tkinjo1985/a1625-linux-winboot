"""Resolve A1625 ANS PMGR gates and IRQ parent offline from private RAM ADT.

The 48-byte PMGR record layout follows Hoolock m1n1 src/pmgr.c.
Only the measured T7000, 8-bit device-ID, ps-regs layout is accepted.
No MMIO or mailbox access is performed.
"""
import argparse
import json
from pathlib import Path
import struct

from inspect_storage_adt import parse, summarize, words


def translate(nodes, address, size):
    ranges = words(nodes['/arm-io'], 'ranges', 8)
    matches = [parent + address - child for child, parent, span in
               zip(ranges[::3], ranges[1::3], ranges[2::3])
               if size > 0 and child <= address and address + size <= child + span
               and parent + address - child + size <= 2**64]
    if len(matches) != 1:
        raise ValueError('Ambiguous or unmapped platform register')
    return matches[0]


def platform_summary(nodes):
    summarize(nodes)  # Identity, ANS protocol and bus layout validation.
    pmgr = nodes.get('/arm-io/pmgr', {})
    if pmgr.get('compatible') != b'pmgr1,t7000\0':
        raise ValueError('Unsupported PMGR compatible')
    data = pmgr.get('devices', b'')
    if len(data) < 96 or len(data) % 48 or len(data) > 48 * 256:
        raise ValueError('Malformed PMGR device table')
    records = [data[i:i+48] for i in range(0, len(data), 48)]
    if records[0][3] == records[1][3]:
        raise ValueError('Unsupported PMGR ID format')
    by_id = {}
    for record in records:
        device_id = record[3]
        if device_id in by_id:
            raise ValueError('Duplicate PMGR device ID')
        by_id[device_id] = record
    groups = words(pmgr, 'ps-regs')
    registers = words(pmgr, 'reg', 8)
    if len(groups) % 3 or len(registers) % 2:
        raise ValueError('Malformed PMGR register table')
    gates = []
    ans = nodes['/arm-io/ans']
    ids = sorted(set(words(ans, 'clock-gates') + words(ans, 'power-gates')))
    # Exact observed IDs/names avoid emitting arbitrary strings from input.
    if ids != [0x16, 0x35] or words(ans, 'power-gates') != [0x16]:
        raise ValueError('Unverified ANS gate topology')
    for device_id, name in ((0x16, 'ANS'), (0x35, 'DEBUG')):
        record = by_id.get(device_id)
        if record is None or record[32:].rstrip(b'\0') != name.encode():
            raise ValueError('Gate name/ID mismatch')
        if record[0] & 0x10:
            raise ValueError('Virtual gate cannot supply a physical register')
        group_index, offset = record[11], record[10] * 8
        if group_index >= len(groups) // 3:
            raise ValueError('PMGR group index out of range')
        reg_index, group_offset, _ = groups[group_index*3:group_index*3+3]
        if reg_index >= len(registers) // 2:
            raise ValueError('PMGR reg index out of range')
        base, span = registers[reg_index*2:reg_index*2+2]
        if group_offset + offset + 4 > span:
            raise ValueError('PMGR gate outside register window')
        address = translate(nodes, base + group_offset + offset, 4)
        gates.append({'id': hex(device_id), 'name': name,
                      'physical_address': hex(address),
                      'parent_ids': list(record[4:6]),
                      'pmgr_register_index': reg_index,
                      'offset_in_register': hex(group_offset + offset)})
    aic = nodes.get('/arm-io/aic', {})
    phandle = words(ans, 'interrupt-parent')
    if len(phandle) != 1 or aic.get('AAPL,phandle') != struct.pack('<I', phandle[0]):
        raise ValueError('ANS interrupt parent is not the captured AIC')
    if aic.get('compatible') != b'aic,1\0':
        raise ValueError('Unsupported AIC compatible')
    irq_reg = words(aic, 'reg', 8)
    if len(irq_reg) != 2:
        raise ValueError('Unsupported AIC register layout')
    return {'schema_version': 1, 'target': 'AppleTV5,3/J42d/T7000',
            'pmgr_gates': gates,
            'interrupt_parent': {'path': '/arm-io/aic',
                'physical_address': hex(translate(nodes, *irq_reg)),
                'size': hex(irq_reg[1]),
                'interrupt_numbers': words(ans, 'interrupts')},
            'limitations': ['IRQ trigger semantics and interrupt order roles are unverified',
                            'No live register read, power transition or mailbox transaction']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    args = parser.parse_args()
    with args.dump.open('rb') as stream:
        data = stream.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        parser.error('ADT exceeds 16 MiB limit')
    print(json.dumps(platform_summary(parse(data)), indent=2))
