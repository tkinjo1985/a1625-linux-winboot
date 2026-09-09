"""Build pinned Alpine aarch64 RAM bundles using native Windows Python.

No installation scripts run and no archive is extracted onto the host.
The existing RAM root must provide musl and the system CA certificate bundle.
"""
import argparse
import hashlib
import io
import json
import posixpath
from pathlib import Path, PurePosixPath
import re
import tarfile
import urllib.request
import zlib


def require(condition, message):
    if not condition:
        raise ValueError(message)


def apk_data(raw):
    members = []
    while raw:
        decoder = zlib.decompressobj(31)
        expanded = decoder.decompress(raw)
        require(decoder.eof, 'Incomplete APK gzip member')
        members.append(expanded)
        raw = decoder.unused_data
    require(len(members) == 3, 'Expected APK v2 signature/control/data members')
    return members[2]


def safe_member(member):
    path = PurePosixPath(member.name)
    require(not path.is_absolute() and '..' not in path.parts
            and '\\' not in member.name, 'Unsafe archive path')
    if member.issym():
        target = member.linkname
        resolved = posixpath.normpath(posixpath.join(str(path.parent), target))
        require(not target.startswith('/') and '\\' not in target
                and resolved != '..' and not resolved.startswith('../'),
                'Symlink escapes bundle root')


def build(lock, kind, cache, output, offline):
    expected = lock['bundles'][kind]
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    destination = output / f'{kind}-runtime.tar'
    temporary = destination.with_suffix('.tar.tmp')
    seen = set()
    try:
        with tarfile.open(temporary, 'w') as bundle:
            for package in expected['packages']:
                name = package['file']
                require(re.fullmatch(r'[A-Za-z0-9_.+-]+\.apk', name),
                        'Invalid package filename')
                cached = cache / name
                if not cached.exists():
                    require(not offline, f'Missing cached package: {name}')
                    with urllib.request.urlopen(lock['source'] + name, timeout=60) as response:
                        raw = response.read()
                    require(hashlib.sha256(raw).hexdigest() == package['sha256'],
                            f'Package hash mismatch: {name}')
                    cached.write_bytes(raw)
                raw = cached.read_bytes()
                require(hashlib.sha256(raw).hexdigest() == package['sha256'],
                        f'Package hash mismatch: {name}')
                with tarfile.open(fileobj=io.BytesIO(apk_data(raw))) as data:
                    for member in data:
                        if not (member.name.startswith(('lib/', 'usr/lib/'))
                                or member.name in ('sbin/wpa_supplicant', 'sbin/wpa_cli', 'usr/bin/curl', 'usr/sbin/iw')):
                            continue
                        if not (member.isfile() or member.issym()):
                            continue
                        safe_member(member)
                        require(member.name not in seen, f'Duplicate member: {member.name}')
                        seen.add(member.name)
                        member.uid = member.gid = member.mtime = 0
                        member.uname = member.gname = ''
                        bundle.addfile(member, data.extractfile(member) if member.isfile() else None)
        digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
        require(digest == expected['bundle_sha256'], f'{kind} bundle hash mismatch: {digest}')
        temporary.replace(destination)
        print(f'{kind}: {digest}')
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path('artifacts/wifi-userland'))
    parser.add_argument('--output', type=Path, default=Path('artifacts/wifi-userland/reproduced'))
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    lock = json.loads(Path(__file__).with_name('userland.lock.json').read_text(encoding='utf-8-sig'))
    require(lock['source'] == 'https://dl-cdn.alpinelinux.org/alpine/v3.23/main/aarch64/',
            'Unexpected package source')
    for kind in ('wpa', 'curl', 'iw'):
        build(lock, kind, args.cache, args.output, args.offline)


if __name__ == '__main__':
    main()
