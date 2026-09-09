"""Compile the actual local driver's packed-TCR accessors against RAM MMIO."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def extract(source, name):
    start = source.index('static ', source.index(name) - 20)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cc', required=True)
    parser.add_argument('--driver', type=Path, required=True)
    args = parser.parse_args()
    source = args.driver.read_text()
    accessors = '\n'.join(extract(source, name) for name in (
        'apple_dart_s5l8960x_read_tcr', 'apple_dart_s5l8960x_write_tcr'))
    harness = r'''
typedef unsigned int u32;
#define WARN_ON(x) ((void)(x))
#define DART_S5L8960X_TCR_BITS_PER_STREAM 8
struct hw { unsigned int tcr; };
struct apple_dart { void *regs; struct hw *hw; };
static u32 readl(void *p) { return *(volatile u32 *)p; }
static void writel(u32 v, void *p) { *(volatile u32 *)p = v; }
''' + accessors + r'''
int main(void) {
    const u32 enabled[] = {0x12345680, 0x12348078, 0x12805678, 0x80345678};
    const u32 disabled[] = {0x12345600, 0x12340078, 0x12005678, 0x00345678};
    u32 reg = 0;
    struct hw hw = {0};
    struct apple_dart dart = {&reg, &hw};
    for (u32 sid = 0; sid < 4; sid++) {
        reg = 0x12345678;
        apple_dart_s5l8960x_write_tcr(&dart, sid, 0x80);
        if (reg != enabled[sid]) return 1;
        if (apple_dart_s5l8960x_read_tcr(&dart, sid) != 0x80) return 2;
        reg = 0x12345678;
        apple_dart_s5l8960x_write_tcr(&dart, sid, 0);
        if (reg != disabled[sid]) return 3;
        reg = 0x12345678;
        apple_dart_s5l8960x_write_tcr(&dart, sid, 0x180);
        if (reg != enabled[sid]) return 4;
    }
    reg = 0;
    for (u32 sid = 0; sid < 4; sid++)
        apple_dart_s5l8960x_write_tcr(&dart, sid, 0x80);
    if (reg != 0x80808080) return 5;
    for (u32 sid = 0; sid < 4; sid++)
        apple_dart_s5l8960x_write_tcr(&dart, sid, 0);
    return reg != 0 ? 6 : 0;
}
'''
    with tempfile.TemporaryDirectory(prefix='a1625-dart-test-') as folder:
        c = Path(folder) / 'tcr.c'
        exe = Path(folder) / 'tcr.exe'
        c.write_text(harness)
        subprocess.run([args.cc, '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                        str(c), '-o', str(exe)], check=True)
        subprocess.run([str(exe)], check=True)
    print('PASS: packed TCR read/write, per-stream enable/disable and isolation')


if __name__ == '__main__':
    main()
