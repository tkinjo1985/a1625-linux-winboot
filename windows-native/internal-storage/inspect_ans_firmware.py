"""Read only allowlisted ANS firmware layout metadata from a saved A1625 ADT."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
from inspect_storage_adt import parse, summarize


def inspect(data):
    nodes = parse(data)
    summarize(nodes)  # Existing exact A1625/J42d and ANS identity checks.
    nub = nodes['/arm-io/ans/iop-ans-nub']
    raw = nub.get('segment-ranges', b'')
    # Pinned m1n1 adt.h: packed u64 phys/iova/remap, u32 size/unk.
    if not raw or len(raw) % 32 or len(raw) > 32 * 32:
        raise ValueError('missing/malformed/oversized segment-ranges')
    records = list(struct.iter_unpack('<QQQII', raw))
    segments = sorted(records, key=lambda s: s[0])
    first_phys, first_iova = segments[0][:2]
    end = first_phys
    for phys, iova, remap, size, unk in segments:
        if not size or phys + size >= 2**64 or iova + size >= 2**64:
            raise ValueError('zero size or address overflow')
        if phys < end or iova < first_iova or phys - first_phys != iova - first_iova:
            raise ValueError('overlap or inconsistent physical/IOVA translation')
        end = phys + size
    return {
        'source_sha256': hashlib.sha256(data).hexdigest(),
        'target': 'AppleTV5,3/J42d',
        'metadata_translation_valid': True,
        'region': {'phys': hex(first_phys), 'iova': hex(first_iova), 'size': hex(end-first_phys)},
        'segment_count': len(segments),
        'gaps_bytes': end-first_phys-sum(s[3] for s in segments),
        'remap_nonzero_count': sum(s[2] != 0 for s in segments),
        'unknown_nonzero_count': sum(s[4] != 0 for s in segments),
        'firmware_integrity_verified': False,
        'reservation_ownership_verified': False,
        'safe_to_start': False,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('adt', type=Path)
    args = parser.parse_args()
    with args.adt.open('rb') as stream:
        data = stream.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        parser.error('ADT exceeds 16 MiB')
    print(json.dumps(inspect(data), indent=2))
