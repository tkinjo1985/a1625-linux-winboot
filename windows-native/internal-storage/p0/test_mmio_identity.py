"""Exercise actual read-only ADT gate before ANS power enable."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
src = ROOT / 'third_party/HoolockLinux-m1n1-p0/src'
s = (src / 'akf.c').read_text()
start = s.index('bool akf_p0_validate_ans(void)\n{')
body = s[start:s.index('\n}', start) + 2]
program = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
typedef uint64_t u64;
static void *adt;
static int bad=-1; static unsigned reads;
static int adt_path_offset_trace(void *a,const char *p,int *t) {
 (void)a;(void)t;assert(!strcmp(p,"/arm-io/ans"));return bad==12?-1:1;
}
static bool adt_is_compatible(void *a,int n,const char *c) {
 (void)a;assert(n==1 && !strcmp(c,"iop,s5l8960x"));return bad!=13;
}
static int adt_get_reg(void *a,int *t,const char *k,unsigned i,u64 *b,u64 *z) {
 (void)a;(void)t;assert(!strcmp(k,"reg") && i<4);reads++;
 const u64 bases[]={0x208040000,0x208060000,0x20e020000,0x200f00000};
 const u64 sizes[]={0x2000,0x1000,0x1000,0x100000};
 *b=bases[i];*z=sizes[i];
 if(bad==(int)i)*b+=0x1000;
 if(bad==4+(int)i)*z+=0x1000;
 return bad==8+(int)i?-1:0;
}
''' + body + r'''
int main(void) {
 assert(akf_p0_validate_ans() && reads==4);
 for(bad=0;bad<14;bad++) {
  reads=0;assert(!akf_p0_validate_ans());assert(reads<=4);
  if(bad>=12)assert(!reads);
 }
 puts("J42d ANS four-region, size, compatible and missing-node rejection tests passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'; out.mkdir(exist_ok=True)
c = out / 'mmio-identity.c'; c.write_text(program)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'mmio-identity.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
