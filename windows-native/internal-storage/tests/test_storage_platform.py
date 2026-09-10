import json
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inspect_storage_platform import platform_summary
from test_storage_adt import fixture as base_fixture, u32, u64


def record(device_id, name, group, offset):
    data = bytearray(48)
    data[3] = device_id
    data[10:12] = bytes((offset, group))
    data[32:32+len(name)] = name
    return bytes(data)


def fixture():
    nodes = base_fixture()
    nodes['/arm-io/pmgr'] = {
        'compatible': b'pmgr1,t7000\0', 'reg': u64(0xe000000, 0x40000),
        'ps-regs': u32(0, 0x20100, 0, 0, 0x20300, 0),
        'devices': record(22, b'ANS', 1, 3) + record(53, b'DEBUG', 0, 3),
        'secret': b'PRIVATE',
    }
    nodes['/arm-io/aic'] = {'compatible': b'aic,1\0', 'AAPL,phandle': u32(17),
                             'reg': u64(0xe100000, 0x100000)}
    return nodes


class PlatformTests(unittest.TestCase):
    def test_measured_mapping(self):
        report = platform_summary(fixture())
        self.assertEqual([g['physical_address'] for g in report['pmgr_gates']],
                         ['0x20e020318', '0x20e020118'])
        self.assertEqual(report['interrupt_parent']['physical_address'], '0x20e100000')
        self.assertNotIn('PRIVATE', json.dumps(report))

    def test_invalid_tables_rejected(self):
        nodes = fixture()
        pmgr = nodes['/arm-io/pmgr']
        for key, value in (
            ('compatible', b'pmgr1,t8015\0'), ('devices', pmgr['devices'][:-1]),
            ('devices', pmgr['devices'][:48] * 2),
            ('devices', record(22, b'ANS', 7, 3) + record(53, b'DEBUG', 0, 3)),
            ('devices', record(22, b'OTHER', 1, 3) + record(53, b'DEBUG', 0, 3)),
            ('ps-regs', u32(50, 0, 0, 0, 0x20300, 0)),
            ('reg', u64(0xe000000, 4)), ('ps-regs', u32(0)),
        ):
            with self.subTest(key=key):
                changed = fixture()
                changed['/arm-io/pmgr'][key] = value
                with self.assertRaises(ValueError):
                    platform_summary(changed)

    def test_virtual_gate_rejected(self):
        nodes = fixture()
        data = bytearray(nodes['/arm-io/pmgr']['devices'])
        data[0] |= 0x10
        nodes['/arm-io/pmgr']['devices'] = bytes(data)
        with self.assertRaises(ValueError):
            platform_summary(nodes)

    def test_unverified_irq_parent_and_gates_rejected(self):
        for path, key, value in (
            ('/arm-io/aic', 'AAPL,phandle', u32(18)),
            ('/arm-io/aic', 'compatible', b'aic,2\0'),
            ('/arm-io/ans', 'clock-gates', u32(22, 54)),
            ('/arm-io/ans', 'power-gates', u32(53)),
            ('/arm-io/aic', 'reg', u64(0x100000000, 4)),
        ):
            nodes = fixture()
            nodes[path][key] = value
            with self.subTest(path=path, key=key):
                with self.assertRaises(ValueError):
                    platform_summary(nodes)


if __name__ == '__main__':
    unittest.main()
