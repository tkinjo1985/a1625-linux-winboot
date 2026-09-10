"""Record exact built inputs; never authorize device execution."""
from pathlib import Path
import hashlib
import json
import subprocess
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SRC = ROOT / 'third_party/HoolockLinux-m1n1-p0'
REV = 'd5a10ac52a6468484854419a6c5130f1d62073eb'
ORIGIN = '8a8bc21922b21a909330d7dbec53e8a763e9fa34'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def git(*args):
    return subprocess.check_output(['git', '-C', str(SRC), *args])
assert git('rev-parse', 'HEAD').decode().strip() == REV
subprocess.run(['git', '-C', str(SRC), 'merge-base', '--is-ancestor', ORIGIN, REV], check=True)
patch = git('diff', '--binary', '--', 'src')
if patch != (HERE / 'm1n1-p0.patch').read_bytes():
    raise SystemExit('working source does not match checked-in P0 patch')
manifest = {
    'source_url': 'https://github.com/HoolockLinux/m1n1.git',
    'source_revision': REV, 'ans1_feature_origin': ORIGIN,
    'patch_sha256': sha(HERE / 'm1n1-p0.patch'),
    'm1n1_bin_path': 'third_party/HoolockLinux-m1n1-p0/build/m1n1.bin',
    'm1n1_bin_sha256': sha(SRC / 'build/m1n1.bin'),
    'cargo_lock_sha256': sha(SRC / 'rust/Cargo.lock'),
    'linker_wrapper_sha256': sha(ROOT / 'windows-native/msys-aarch64-ld-wrapper.sh'),
    'build_flags': ['USE_CLANG=1', 'ARCH=aarch64-none-elf', 'CHAINLOADING=1', 'EXTRA_CFLAGS=-DANS1_P0'],
    'hardware_executed': False, 'execution_authorized': False,
    'acceptance': 'unverified',
    'selector_scope': 'Includes firmware-internal settings; current firmware not proven compliant',
}
(HERE / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(manifest['m1n1_bin_sha256'])
