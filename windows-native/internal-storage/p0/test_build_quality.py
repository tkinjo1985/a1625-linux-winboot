"""Build metadata failures must not publish a P0 artifact record."""
from pathlib import Path
import json, os, subprocess, sys, tempfile

HERE=Path(__file__).parent; ROOT=HERE.parents[2]; tool=HERE/'build-quality.py'; git=Path(r'C:\Program Files\Git\cmd\git.exe')
build=(HERE/'build.sh').read_text(); version=(ROOT/'third_party/HoolockLinux-m1n1-p0/version.sh').read_text(); manifest=(HERE/'write-manifest.py').read_text()
for required in ('command -v git','command -v make','command -v clang','build-quality.py" prepare','build-quality.py" verify'):
    assert required in build
assert 'set -eu' in version and 'test -n "$version"' in version
assert "validated build metadata is missing, stale, or inconsistent" in manifest
with tempfile.TemporaryDirectory() as td:
    src=Path(td)/'src'; src.mkdir(); (src/'version.sh').write_text(
        'import os\nprint(\'#define BUILD_TAG "\'+os.environ.get("M1N1_VERSION_TAG","")+\'"\')\n')
    subprocess.run([git,'-C',src,'init'],check=True,capture_output=True)
    subprocess.run([git,'-C',src,'config','user.email','p0@example.invalid'],check=True)
    subprocess.run([git,'-C',src,'config','user.name','P0 Test'],check=True)
    (src/'tracked').write_text('x'); subprocess.run([git,'-C',src,'add','.'],check=True)
    subprocess.run([git,'-C',src,'commit','-m','fixture'],check=True,capture_output=True)
    tag=subprocess.check_output([git,'-C',src,'describe','--tags','--always','--dirty'],text=True).strip()
    header=src/'build/build_tag.h'
    base=[sys.executable,tool,'prepare','--src',src,'--git',git,'--shell',sys.executable,'--header',header]
    subprocess.run(base,check=True,capture_output=True); assert tag in header.read_text()
    old=header.read_bytes()
    # Missing git and failing generator preserve the last valid header.
    for args in ([*base[:],],):
        bad=args.copy(); bad[bad.index('--git')+1]=str(src/'missing-git')
        assert subprocess.run(bad,capture_output=True).returncode and header.read_bytes()==old
    (src/'version.sh').write_text('raise SystemExit(7)\n')
    assert subprocess.run(base,capture_output=True).returncode and header.read_bytes()==old
    (src/'version.sh').write_text('print(\'#define BUILD_TAG ""\')\n')
    assert subprocess.run(base,capture_output=True).returncode and header.read_bytes()==old
    # Restore generator, then verify header and final binary are tied together.
    (src/'version.sh').write_text('import os\nprint(\'#define BUILD_TAG "\'+os.environ["M1N1_VERSION_TAG"]+\'"\')\n')
    subprocess.run(base,check=True,capture_output=True)
    tag=header.read_text().split('"')[1]
    product='m1n1 uartproxy '+tag; desc=bytes([2+2*len(product),3])+product.encode('utf-16le')
    elf=src/'x.elf'; payload=src/'x.bin'; elf.write_bytes(b'E'+desc); payload.write_bytes(b'P'+desc)
    output=src/'quality.json'
    verify=[sys.executable,tool,'verify','--src',src,'--git',git,'--header',header,
            '--elf',elf,'--payload',payload,'--output',output]
    subprocess.run(verify,check=True,capture_output=True); assert json.loads(output.read_text())['build_tag']==tag
    output.unlink(); header.write_text('#define BUILD_TAG "stale"\n')
    assert subprocess.run(verify,capture_output=True).returncode and not output.exists()
    subprocess.run(base,check=True,capture_output=True); payload.write_bytes(b'wrong descriptor')
    assert subprocess.run(verify,capture_output=True).returncode and not output.exists()
print('build tag generation is atomic; missing/failed/empty/stale/mismatched artifacts are rejected')
