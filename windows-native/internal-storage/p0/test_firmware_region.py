"""Validate actual firmware range parser against synthetic ADT properties."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/akf_fw.c').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('#include'))
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint64_t u64; typedef uint32_t u32;
struct adt_segment_ranges { u64 phys,iova,remap; u32 size,unk; } __attribute__((packed));
static struct adt_segment_ranges segments[129];
static bool present=true; static u32 bytes; static int old_reads;
static void *adt;
static const void *adt_getprop(void *a,int n,const char *key,u32 *len) {
 (void)a;(void)n;assert(!strcmp(key,"segment-ranges"));
 if(!present)return NULL;
 if(len)*len=bytes;
 return segments;
}
static int mock_prop(const char *key,void *out) {
 if(!strcmp(key,"pre-loaded")) {*(int *)out=1;return 0;}
 old_reads++; *(u64 *)out=!strcmp(key,"region-base")?0x1000:0x2000;return 0;
}
#define ADT_GETPROP(a,n,k,p) mock_prop(k,p)
'''
tests = r'''
int main(void) {
 u64 phys=0,iova=0,size=0;
 segments[0]=(struct adt_segment_ranges){.phys=0x2000,.iova=0x1000,.size=0x1000};
 segments[1]=(struct adt_segment_ranges){.phys=0x1000,.iova=0,.size=0x1000};
 bytes=2*sizeof(segments[0]);
 assert(akf_fw_get_region(0,&phys,&iova,&size));
 assert(phys==0x1000 && iova==0 && size==0x2000 && !old_reads);
 segments[0].iova=0x2000;
 assert(!akf_fw_get_region(0,&phys,&iova,&size) && !old_reads);
 segments[0].iova=0x1000; segments[1].size=0x800;
 assert(!akf_fw_get_region(0,&phys,&iova,&size) && !old_reads);
 segments[1].size=0x1000;segments[0].phys=UINT64_MAX-0x100;
 assert(!akf_fw_get_region(0,&phys,&iova,&size));
 segments[0].phys=0x2000;segments[0].iova=UINT64_MAX-0x100;
 assert(!akf_fw_get_region(0,&phys,&iova,&size));
 segments[0].iova=0x1000;segments[0].size=0;
 assert(!akf_fw_get_region(0,&phys,&iova,&size));
 segments[0].size=0x1000;
 bytes--;assert(!akf_fw_get_region(0,&phys,&iova,&size));
 bytes=0;assert(!akf_fw_get_region(0,&phys,&iova,&size));
 bytes=sizeof(segments);assert(!akf_fw_get_region(0,&phys,&iova,&size));
 assert(!old_reads);
 present=false;assert(akf_fw_get_region(0,&phys,&iova,&size));
 assert(old_reads==2 && phys==0x1000 && size==0x2000);
 puts("Firmware range overflow, holes, translation, length and no-fallback tests passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'
out.mkdir(exist_ok=True)
c = out / 'firmware-region.c'
c.write_text(prefix + source + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'firmware-region.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
