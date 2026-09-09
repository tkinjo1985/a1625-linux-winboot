"""Archive boundaries and tamper rejection for the RAM userland builder."""
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('builder', Path(__file__).parents[1] / 'build_userland.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class BundleTests(unittest.TestCase):
    def test_link_may_cross_one_directory_but_not_bundle_root(self):
        member = tarfile.TarInfo('usr/lib/libalias.so')
        member.type = tarfile.SYMTYPE
        member.linkname = '../../lib/libreal.so'
        builder.safe_member(member)
        for target in ('../../../outside', '/etc/passwd', '..\\outside'):
            member.linkname = target
            with self.subTest(target=target), self.assertRaises(ValueError):
                builder.safe_member(member)

    def test_traversal_member_rejected(self):
        for name in ('lib/../../outside', '/usr/lib/outside', 'lib/..\\outside'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                builder.safe_member(tarfile.TarInfo(name))

    def test_tampered_cache_does_not_replace_existing_bundle(self):
        with tempfile.TemporaryDirectory() as root:
            cache = Path(root) / 'cache'
            output = Path(root) / 'output'
            cache.mkdir()
            output.mkdir()
            (cache / 'test-1.apk').write_bytes(b'corrupted')
            destination = output / 'wpa-runtime.tar'
            destination.write_bytes(b'previous verified output')
            lock = {'bundles': {'wpa': {'packages': [
                {'file': 'test-1.apk', 'sha256': '0' * 64}
            ]}}}
            with self.assertRaisesRegex(ValueError, 'Package hash mismatch'):
                builder.build(lock, 'wpa', cache, output, True)
            self.assertEqual(destination.read_bytes(), b'previous verified output')
            self.assertFalse((output / 'wpa-runtime.tar.tmp').exists())


if __name__ == '__main__':
    unittest.main()
