import json
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inspect_storage_adt import summarize


def u32(*values):
    return struct.pack('<' + 'I' * len(values), *values)


def u64(*values):
    return struct.pack('<' + 'Q' * len(values), *values)


def fixture():
    return {
        '/': {'model': b'AppleTV5,3\0', 'target-type': b'J42d\0',
              '#address-cells': u32(2), '#size-cells': u32(2),
              'serial-number': b'PRIVATE'},
        '/arm-io': {'#address-cells': u32(2), '#size-cells': u32(2),
                    'ranges': u64(0, 0x200000000, 0x100000000)},
        '/arm-io/ans': {
            'compatible': b'iop,s5l8960x\0', 'reg': u64(0x8040000, 0x2000),
            'interrupt-parent': u32(17), 'interrupts': u32(37, 36, 39, 38),
            'clock-gates': u32(22, 53), 'power-gates': u32(22),
            'clock-ids': u32(311, 312), 'iop-version': u32(1),
            'ps-reg-offset': u32(0x318), 'sf-ps-reg-offset': u32(0x298),
            'credential': b'PRIVATE', 'unknown': b'PRIVATE'},
        '/arm-io/ans/iop-ans-nub': {'compatible': b'iop-nub,rtbuddy\0',
                                    'segment-ranges': b'PRIVATE'},
        '/chosen': {'ECID': b'PRIVATE'},
    }


class StorageAdtTests(unittest.TestCase):
    def test_translation_and_allowlist(self):
        report = summarize(fixture())
        self.assertEqual(report['ans']['registers'], [{
            'bus_address': '0x8040000', 'physical_address': '0x208040000', 'size': '0x2000'}])
        rendered = json.dumps(report)
        for secret in ('PRIVATE', 'ECID', 'credential', 'segment-ranges', 'serial-number'):
            self.assertNotIn(secret, rendered)

    def test_other_targets_and_protocols_rejected(self):
        for path, key, value in (
            ('/', 'model', b'iPhone7,1\0'), ('/', 'target-type', b'N56AP\0'),
            ('/arm-io/ans', 'compatible', b'apple,nvme-ans2\0'),
            ('/arm-io/ans/iop-ans-nub', 'compatible', b'iop-nub,rtkit\0'),
            ('/arm-io', '#address-cells', u32(1)),
        ):
            with self.subTest(path=path, key=key):
                nodes = fixture()
                nodes[path][key] = value
                with self.assertRaises(ValueError):
                    summarize(nodes)

    def test_malformed_properties_rejected(self):
        for path, props in fixture().items():
            for key in props:
                if key not in ('interrupts', 'ranges', 'reg', 'power-gates'):
                    continue
                for value in (b'', b'\x01', props[key][:-1]):
                    nodes = fixture()
                    nodes[path][key] = value
                    with self.subTest(path=path, key=key, size=len(value)):
                        with self.assertRaises(ValueError):
                            summarize(nodes)

    def test_unmapped_crossing_and_overflow_registers_rejected(self):
        for address, size in ((0x100000000, 4), (0xffffffff, 2), (0, 0), (2**64-1, 2)):
            nodes = fixture()
            nodes['/arm-io/ans']['reg'] = u64(address, size)
            with self.assertRaises(ValueError):
                summarize(nodes)

    def test_ambiguous_and_overflow_bus_ranges_rejected(self):
        for ranges in (u64(0, 0, 2**64-1, 0, 0, 2**64-1), u64(1, 0, 2**64-1),
                       u64(0, 2**64-1, 2), u64(0, 0, 0)):
            nodes = fixture()
            nodes['/arm-io']['ranges'] = ranges
            # A range ending exactly at 2**64 is representable, but the second
            # case excludes the register only after moving it to bus address 0.
            if ranges == u64(1, 0, 2**64-1):
                nodes['/arm-io/ans']['reg'] = u64(0, 1)
            with self.assertRaises(ValueError):
                summarize(nodes)


if __name__ == '__main__':
    unittest.main()
