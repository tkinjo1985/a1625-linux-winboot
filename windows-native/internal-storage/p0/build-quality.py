"""Atomically prepare and verify P0 build metadata; never touches hardware."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, tempfile

HEADER_RE = re.compile(r'^#define BUILD_TAG "([^"\r\n]+)"\r?\n?$')

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def expected_tag(src, git):
    p = subprocess.run([git, '-C', str(src), 'describe', '--tags', '--always', '--dirty'],
                       capture_output=True, text=True)
    if p.returncode or not p.stdout.strip():
        raise SystemExit('git describe failed or returned an empty build tag')
    return p.stdout.strip()

def prepare(a):
    src, header = Path(a.src), Path(a.header)
    tag = expected_tag(src, a.git)
    env = os.environ.copy(); env['M1N1_VERSION_TAG'] = tag
    p = subprocess.run([a.shell, str(src / 'version.sh')], cwd=src, env=env,
                       capture_output=True, text=True)
    expected = f'#define BUILD_TAG "{tag}"\n'
    if p.returncode or p.stdout != expected or not HEADER_RE.fullmatch(p.stdout):
        raise SystemExit('version generation failed, was empty, or was inconsistent')
    header.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=header.name + '.', dir=header.parent)
    try:
        with os.fdopen(fd, 'w', newline='\n') as f: f.write(expected)
        os.replace(tmp, header)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print(tag)

def verify(a):
    src, header, elf, payload, output = map(Path, (a.src,a.header,a.elf,a.payload,a.output))
    tag = expected_tag(src, a.git)
    text = header.read_text()
    m = HEADER_RE.fullmatch(text)
    if not m or m.group(1) != tag:
        raise SystemExit('build_tag.h is empty, stale, or inconsistent with git describe')
    product = 'm1n1 uartproxy ' + tag
    descriptor = bytes([2 + 2 * len(product), 3]) + product.encode('utf-16le')
    if len(descriptor) > 255: raise SystemExit('product descriptor is too long')
    for name, path in (('ELF', elf), ('payload', payload)):
        if descriptor not in path.read_bytes():
            raise SystemExit(f'{name} does not contain the generated product descriptor')
    result = {'build_tag': tag, 'product': product, 'product_descriptor_length': len(descriptor),
              'build_tag_header_sha256': sha(header), 'elf_sha256': sha(elf),
              'payload_sha256': sha(payload)}
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=output.name + '.', dir=output.parent)
    try:
        with os.fdopen(fd, 'w', newline='\n') as f: json.dump(result,f,indent=2); f.write('\n')
        os.replace(tmp, output)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print(json.dumps(result))

p=argparse.ArgumentParser(); sub=p.add_subparsers(dest='cmd',required=True)
q=sub.add_parser('prepare'); q.add_argument('--src',required=True);q.add_argument('--git',required=True);q.add_argument('--shell',required=True);q.add_argument('--header',required=True);q.set_defaults(fn=prepare)
q=sub.add_parser('verify'); q.add_argument('--src',required=True);q.add_argument('--git',required=True);q.add_argument('--header',required=True);q.add_argument('--elf',required=True);q.add_argument('--payload',required=True);q.add_argument('--output',required=True);q.set_defaults(fn=verify)
a=p.parse_args(); a.fn(a)
