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
quality_path = SRC / 'build/build-quality.json'
quality = json.loads(quality_path.read_text())
tag = subprocess.check_output(['git','-C',str(SRC),'describe','--tags','--always','--dirty'],text=True).strip()
if not tag or quality.get('build_tag') != tag or quality.get('payload_sha256') != sha(SRC/'build/m1n1.bin'):
    raise SystemExit('validated build metadata is missing, stale, or inconsistent')
manifest = {
    'source_url': 'https://github.com/HoolockLinux/m1n1.git',
    'source_revision': REV, 'ans1_feature_origin': ORIGIN,
    'patch_sha256': sha(HERE / 'm1n1-p0.patch'),
    'm1n1_bin_path': 'third_party/HoolockLinux-m1n1-p0/build/m1n1.bin',
    'm1n1_bin_sha256': sha(SRC / 'build/m1n1.bin'),
    'build_quality_sha256': sha(quality_path),
    'build_entry_sha256': sha(HERE / 'build.sh'),
    'build_quality_tool_sha256': sha(HERE / 'build-quality.py'),
    'build_metadata_patch_sha256': sha(HERE / 'build-metadata.patch'),
    'build_tag': quality['build_tag'],
    'product': quality['product'],
    'product_descriptor_length': quality['product_descriptor_length'],
    'build_tag_header_sha256': quality['build_tag_header_sha256'],
    'm1n1_elf_sha256': quality['elf_sha256'],
    'cargo_lock_sha256': sha(SRC / 'rust/Cargo.lock'),
    'linker_wrapper_sha256': sha(ROOT / 'windows-native/msys-aarch64-ld-wrapper.sh'),
    'build_flags': ['USE_CLANG=1', 'ARCH=aarch64-none-elf', 'CHAINLOADING=1', 'EXTRA_CFLAGS=-DANS1_P0'],
    'hardware_executed': False, 'execution_authorized': False,
    'execution_policy': 'HostReadOnlyExperimental',
    'preflight_verified': False,
    'acceptance': 'unverified',
    'selector_scope': 'Controlled Windows/m1n1/Linux operations only; unmodified firmware internal selectors are not an execution blocker',
    'firmware_persistent_side_effects': 'not_guaranteed_absent',
    'session_limit': 1,
    'backup_available': False, 'valuable_data_present': False, 'dfu_recovery_available': True,
    'historical_firmware_capture_sha256': sha(ROOT / 'artifacts/ans-offline-tests/ans-fw-live-region.bin'),
    'loaded_firmware_sha256': None,
}
(HERE / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(manifest['m1n1_bin_sha256'])
