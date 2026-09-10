"""Prepare an isolated synthetic module; does not build or load it."""
from pathlib import Path
import hashlib
import json
import shutil
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--v2', action='store_true', help='Separate instance for stop-path validation')
args = parser.parse_args()

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / ('artifacts/ans-block-selftest-v2' if args.v2 else 'artifacts/ans-block-selftest')
out.mkdir(parents=True, exist_ok=True)
source = (HERE / 'ans1_block.c').read_text()
# Only disk/major registration names differ from the real frontend source.
assert source.count('"a1625ans"') == 3
assert source.count('"a1625ans0"') == 1
renamed = source.replace('"a1625ans"', '"ans1ramtest"').replace('"a1625ans0"', '"ans1ramtest0"')
if args.v2:
    renamed = renamed.replace('"ans1ramtest"', '"ans1ramtestv2"').replace('"ans1ramtest0"', '"ans1ramtest1"')
(out / 'ans1_block.c').write_text(renamed, encoding='utf-8', newline='\n')
for name in ('ans1_block.h', 'block_selftest.c'):
    shutil.copyfile(HERE / name, out / name)
module = 'ans1_ram_selftest_v2' if args.v2 else 'ans1_ram_selftest'
if args.v2:
    wrapper = (out / 'block_selftest.c').read_text().replace('"ans1-block-selftest"', '"ans1-block-selftest-v2"')
    (out / 'block_selftest.c').write_text(wrapper, encoding='utf-8', newline='\n')
(out / 'Makefile').write_text(f'obj-m := {module}.o\n{module}-y := ans1_block.o block_selftest.o\n', encoding='utf-8')
(out / 'sources.json').write_text(json.dumps({
    'purpose': 'Synthetic RAM block testing; no NAND/controller access',
    'frontend_sha256': hashlib.sha256((HERE / 'ans1_block.c').read_bytes()).hexdigest(),
    'generated_frontend_sha256': hashlib.sha256((out / 'ans1_block.c').read_bytes()).hexdigest(),
    'loaded': False,
}, indent=2) + '\n', encoding='utf-8')
print(out)
