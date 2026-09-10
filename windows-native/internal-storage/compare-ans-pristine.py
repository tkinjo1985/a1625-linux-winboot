"""Compare a pinned iBoot embedded ANS candidate with retained DRAM; no device I/O."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import os

ROOT = Path(__file__).resolve().parents[2]
out = ROOT / 'artifacts/ans-pristine-candidate'
boot = (out / 'iboot-17L256-decrypted.bin').read_bytes()
live = (ROOT / 'artifacts/ans-offline-tests/ans-fw-live-region.bin').read_bytes()
if hashlib.sha256(boot).hexdigest() != '119cbaa86cb775d0c7f224971a700c7e5797ee7b987104ced1de0cb4c785ef95':
    raise ValueError('Unexpected iBoot image')
if hashlib.sha256(live).hexdigest() != '41ce142b90ce7b4fe51a4ea078dcbc6a936d19129b7f8709fcbe5a4e674a1482':
    raise ValueError('Unexpected retained image')
base = 0x55000
candidate = boot[base:]
bindir = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin'
os.environ['PATH'] = str(bindir) + os.pathsep + os.environ['PATH']
elf = out / 'iboot-17L256.elf'
subprocess.run([str(bindir / 'llvm-objcopy.exe'), '-I', 'binary', '-O',
    'elf64-littleaarch64', '-B', 'aarch64', str(out / 'iboot-17L256-decrypted.bin'), str(elf)], check=True)
for name, start, end in [('parameter-setters', 0x34e50, 0x34ff8),
                          ('platform-parameters', 0x364f8, 0x36580),
                          ('memory-parameters', 0x362d8, 0x36410),
                          ('parameter-argument-save', 0x369e4, 0x369f0),
                          ('parameter-callback-setup', 0x3604c, 0x3614c),
                          ('segment-name-lookup', 0x36238, 0x3627c),
                          ('parameter-callback-dispatch', 0x36634, 0x36660),
                          ('allocation-caller', 0x33c70, 0x33d0c),
                          ('allocation-tail-output', 0x35708, 0x35754),
                          ('allocation-tail-transform', 0x359b0, 0x35a54),
                          ('allocation-mode-predicate', 0x35020, 0x35054),
                          ('allocation-source-selection', 0x35344, 0x353dc),
                          ('allocation-alignment-source', 0x64d8, 0x6518),
                          ('ans-specific-parameter-callback', 0x798c, 0x79c0),
                          ('ans-allocation-and-load', 0x7430, 0x7490),
                          ('loader-object-initialization', 0x33a24, 0x33a9c),
                          ('region-lookup', 0x3b620, 0x3b728),
                          ('region-table-provider', 0x138fc, 0x13914),
                          ('ans-start-dispatch', 0x33d5c, 0x33e68),
                          ('iop-remap-and-start', 0x5ed8, 0x6200),
                          ('counter-read', 0x504, 0x510),
                          ('interrupt-mask-primitives', 0x5b4, 0x5d8),
                          ('counter-update-critical-section', 0x3a314, 0x3a3d4),
                          ('iop-power-gate-list', 0x5dbc, 0x5eb0),
                          ('pmgr-set-and-wait', 0x151a8, 0x151f8),
                          ('mailbox-object-init', 0x21b8c, 0x21be4),
                          ('mailbox-platform-init', 0x21d94, 0x21dec),
                          ('mailbox-interrupt-enable', 0x21ff4, 0x22034),
                          ('mailbox-send-receive', 0x21dec, 0x21ff4),
                          ('clock-parameter-lookup', 0x14e6c, 0x14f0c),
                          ('clock-cache-population', 0x14dcc, 0x14e3c),
                          ('pll-rate-calculation', 0x1512c, 0x151a8),
                          ('parameter-byte-fill', 0x36a30, 0x36a3c),
                          ('byte-generator-wrapper', 0x337b4, 0x337d4),
                          ('soc-parameter-sources', 0x14544, 0x14570),
                          ('resource-parameter-sources', 0x6534, 0x65dc),
                          ('page-parameter-source', 0x36960, 0x369bc),
                          ('property-lookup', 0x2eb6c, 0x2ec3c),
                          ('property-value', 0x2ed04, 0x2ee2c)]:
    result = subprocess.run([str(bindir / 'llvm-objdump.exe'), '-d',
        '--triple=aarch64-none-elf', '--section=.data',
        '--start-address='+str(start), '--stop-address='+str(end), str(elf)],
        capture_output=True, text=True, check=True)
    (out / ('iboot-'+name+'.txt')).write_text(result.stdout, encoding='utf-8')
# Observed trailer layout in this pinned image; not a generic format parser.
if candidate[0x60220:0x60224] != b'fwsg':
    raise ValueError('Missing fwsg trailer')
trailer_flag, table, count = struct.unpack_from('<III', candidate, 0x60224)
if ((trailer_flag, table, count) != (1, 0x601e0, 2)
        or len(candidate) - 32 != 0x60220
        or table + count * 32 != len(candidate) - 32):
    raise ValueError('Unexpected fwsg table or extent')
segments = []
file_end = memory_end = 0
for i in range(count):
    address, offset, filesz, memsz, flags, name = struct.unpack_from('<QIIII8s', candidate, table + i*32)
    if filesz > memsz or offset + filesz > table:
        raise ValueError('Segment exceeds file or memory extent')
    if offset < file_end or address < memory_end or address + memsz > 10485760:
        raise ValueError('Overlapping or out-of-reservation segment')
    file_end, memory_end = offset + filesz, address + memsz
    segments.append({'name': name.rstrip(b'\0').decode('ascii'),
        'address': hex(address), 'file_offset': hex(offset),
        'file_bytes': filesz, 'memory_bytes': memsz, 'flags': flags,
        'memory_end': hex(address + memsz)})
if candidate[:0x47b88] != live[:0x47b88]:
    raise ValueError('Captured text does not match candidate')
artifact = out / 'ans1-710.500.1-17L256-analysis-only.fwsg'
artifact.write_bytes(candidate)
if artifact.read_bytes() != boot[base:]:
    raise ValueError('Extracted artifact differs from source slice')
parameters = []
seen_tags = set()
cursor = 0x48000
while cursor < 0x480d1:
    tag, size = struct.unpack_from('<4sI', candidate, cursor)
    if size not in (1, 4, 8) or cursor + 8 + size > 0x480d1:
        raise ValueError('Unexpected pinned startup-parameter layout')
    if live[cursor:cursor+8] != candidate[cursor:cursor+8]:
        raise ValueError('Startup-parameter headers differ')
    if tag in seen_tags:
        raise ValueError('Duplicate startup parameter would make first-match lookup ambiguous')
    seen_tags.add(tag)
    parameters.append({'offset': hex(cursor), 'tag_bytes_ascii': tag.decode('ascii'),
        'bytes': size, 'pristine': candidate[cursor+8:cursor+8+size].hex(),
        'retained': live[cursor+8:cursor+8+size].hex()})
    cursor += 8 + size
if cursor != 0x480d1 or len(parameters) != 16:
    raise ValueError('Startup-parameter table extent or count differs')
report = {
    'scope': 'Offline embedded-image comparison; fwsg extent consistent; not a validated boot payload',
    'fwsg_format_reference': 'https://github.com/nlitsme/AppleC4000/blob/master/loadfwsg.py',
    'fwsg_trailer_flag_semantics': 'unknown; value 1 is not a proven version field',
    'iboot_build': '17L256 / iBoot-5540.100.194',
    'installed_tvos': 'unknown',
    'ans_region_id_2': {
        'table_offset': '0x54338',
        'table_count': 15,
        'id': struct.unpack_from('<I', boot, 0x54338)[0],
        'base': hex(struct.unpack_from('<Q', boot, 0x54340)[0]),
        'bytes': struct.unpack_from('<Q', boot, 0x54348)[0],
        'matches_retained_reservation': struct.unpack_from('<IIQQ', boot, 0x54338)
            == (2, 0, 0x87f600000, 0xa00000),
    },
    'retained_heap_extent_check': {
        'scope': 'Snapshot arithmetic only; caller allocation fields not yet traced',
        'reservation_base': hex(0x87f600000),
        'reservation_bytes': 0xa00000,
        'image_extent_parameter': hex(struct.unpack_from('<I', live, 0x48070)[0]),
        'heap_base': hex(struct.unpack_from('<Q', live, 0x480bd)[0]),
        'heap_bytes': struct.unpack_from('<I', live, 0x480cd)[0],
        'heap_fills_reservation_tail': (
            struct.unpack_from('<Q', live, 0x480bd)[0] ==
            0x87f600000 + struct.unpack_from('<I', live, 0x48070)[0]
            and struct.unpack_from('<Q', live, 0x480bd)[0] +
            struct.unpack_from('<I', live, 0x480cd)[0] == 0x880000000),
    },
    'candidate_offset': hex(base),
    'bytes_to_iboot_end': len(candidate),
    'analysis_artifact': artifact.name,
    'analysis_artifact_sha256': hashlib.sha256(candidate).hexdigest(),
    'observed_fwsg_segments': segments,
    'startup_parameter_comparison_not_patch_instructions': parameters,
    'resource_table_entry_zero': {
        'base': hex(struct.unpack_from('<Q', boot, 0x530d0)[0]),
        'secondary': hex(struct.unpack_from('<Q', boot, 0x530e0)[0]),
        'allocation_alignment': hex(struct.unpack_from('<Q', boot, 0x53198)[0])},
    'resource_zero_start_flags_c0_c7': boot[0x53190:0x53198].hex(),
    'clock_id_0x90_dispatch_target': hex(0x14ea0 + boot[0x4ea0d] * 4),
    'clock_cache_slot_56': {
        'descriptor_offset': '0x500f0',
        'control_register': hex(struct.unpack_from('<Q', boot, 0x500f0)[0]),
        'source_slot_divisor_pairs': [list(struct.unpack_from('<II', boot, 0x500f8 + i * 8))
                                      for i in range(12)],
    },
    'resource_zero_mailbox_layout': list(struct.unpack_from('<8I', boot, 0x4e8b0)),
    'resource_zero_power_gate_slots': list(struct.unpack_from('<8I', boot, 0x530f8)),
    'resource_zero_first_pmgr_address': hex(0x20e020000 +
        struct.unpack_from('<I', boot, 0x530f8)[0] * 8),
    'page_property_record_0x4b890_hex': boot[0x4b890:0x4b8b0].hex(),
    'heap_callback_segment_names': {
        hex(o): boot[o:o+16].split(b'\0', 1)[0].decode('ascii')
        for o in (0x48888, 0x4919e)},
    'ans_named_configuration_candidate': {
        'offset': '0x54100',
        'raw_128_bytes': boot[0x54100:0x54180].hex(),
        'name': boot[0x4819f:0x481a2].decode('ascii'),
        'path': boot[0x481a3:0x481b9].split(b'\0', 1)[0].decode('ascii'),
        'referencing_pointer_offset': '0x54190',
        'referencing_pointer': hex(struct.unpack_from('<Q', boot, 0x54190)[0]),
        'scope': 'Linked to loader at 0x7474; base/size populated at 0x7454/0x745c from region id 2'},
    'prefix_0_to_0x47000_equal': candidate[:0x47000] == live[:0x47000],
    'prefix_sha256': hashlib.sha256(candidate[:0x47000]).hexdigest(),
    'text_segment_complete_match': candidate[:0x47b88] == live[:0x47b88],
    'text_segment_sha256': hashlib.sha256(candidate[:0x47b88]).hexdigest(),
    'padding_between_text_and_data_differs': candidate[0x47b88:0x48000] != live[0x47b88:0x48000],
    'changed_pages_before_0x48000': [hex(p) for p in range(0, 0x48000, 4096)
        if candidate[p:p+4096] != live[p:p+4096]],
    'resource_object_0x4c6d8': {
        'pristine_20_bytes': candidate[0x4c6d8:0x4c6ec].hex(),
        'retained_20_bytes': live[0x4c6d8:0x4c6ec].hex()},
}
(out / 'embedded-comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
