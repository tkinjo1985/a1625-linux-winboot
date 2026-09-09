import json
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from inspect_adt import parse, summarize


def node(props, children=()):
    data = struct.pack('<II', len(props), len(children))
    for key, value in props.items():
        data += key.encode().ljust(32, b'\0') + struct.pack('<I', len(value))
        data += value + b'\0' * (-len(value) % 4)
    return data + b''.join(children)


def fixture():
    return node({'name': b'device-tree\0', 'model': b'AppleTV5,3\0',
                 'target-type': b'J42d\0', 'serial-number': b'PRIVATE_SERIAL'}, [
        node({'name': b'wlan\0', 'compatible': b'wlan-pcie,bcm4350\0',
              'local-mac-address': b'PRIVATE_MAC', 'calibration': b'PRIVATE_CAL',
              'nvram': b'PRIVATE_NVRAM'})])


class AdtTests(unittest.TestCase):
    def test_private_values_are_not_reported(self):
        report = json.dumps(summarize(parse(fixture())))
        self.assertIn('bcm4350', report)
        self.assertNotIn('PRIVATE', report)
        self.assertNotIn('local-mac-address', report)

    def test_truncation(self):
        data = fixture()
        for size in range(len(data)):
            with self.assertRaises((ValueError, UnicodeError)):
                parse(data[:size])

    def test_invalid_counts(self):
        with self.assertRaises(ValueError):
            parse(struct.pack('<II', 0xffffffff, 0))

    def test_wrong_target(self):
        nodes = parse(fixture())
        nodes['/']['model'] = b'iPhone7,2\0'
        with self.assertRaises(ValueError):
            summarize(nodes)

    def test_duplicate_path(self):
        child = node({'name': b'wlan\0'})
        with self.assertRaises(ValueError):
            parse(node({'name': b'root\0'}, [child, child]))


if __name__ == '__main__':
    unittest.main()
