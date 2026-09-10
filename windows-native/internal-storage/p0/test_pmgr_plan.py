"""Fault-inject the real one-shot P0 power plan before mocked MMIO writes."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
s = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/pmgr.c').read_text()
start = s.index('int pmgr_p0_ans_power_enable(void)\n{')
body = s[start:s.index('\n}', start) + 2]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;
#define PMGR_FLAG_VIRTUAL 0x10
#define PMGR_PS_ACTIVE 15
struct pmgr_device {u8 flags; unsigned index;};
static struct pmgr_device devices[]={{0,0},{0,1}};
static void *adt;
static bool pmgr_initialized=true;
static int scenario,writes;
static void mock_log(const char *s,...) {(void)s;}
#define printf mock_log
static int adt_path_offset(void *a,const char *p) {
 (void)a;assert(!strcmp(p,"/arm-io/ans"));return scenario==1?-1:1;
}
static const u32 *adt_getprop(void *a,int n,const char *p,u32 *len) {
 static u32 gates[]={0x16,0x35}; (void)a;assert(n==1 && !strcmp(p,"clock-gates"));
 *len=scenario==2?4:8;if(scenario==3)gates[1]=0x36;
 return scenario==12?NULL:gates;
}
static int pmgr_find_device(u16 id,const struct pmgr_device **d) {
 assert(id==0x16 || id==0x35);*d=&devices[id==0x35];
 return scenario==7?-1:0;
}
static void pmgr_adt_get_parents(const struct pmgr_device *d,u16 *p) {
 p[0]=scenario==5?1:0;p[1]=(scenario==8 && d->index==1)?1:0;
}
static uintptr_t pmgr_device_get_addr(u8 die,const struct pmgr_device *d) {
 assert(!die);return scenario==6?0:(d->index?0x20e020118ULL:0x20e020318ULL);
}
static int pmgr_set_mode(uintptr_t a,u8 v) {
 assert(v==15 && writes<2);
 assert(a==(writes?0x20e020118ULL:0x20e020318ULL));writes++;
 return (scenario==9 && writes==1) || (scenario==10 && writes==2)?-1:0;
}
'''
tests = r'''
int main(int argc,char **argv) {
 assert(argc==2);scenario=atoi(argv[1]);
 if(scenario==4)devices[1].flags=PMGR_FLAG_VIRTUAL;
 if(scenario==11)pmgr_initialized=false;
 int result=pmgr_p0_ans_power_enable();
 assert(result==(scenario==0?0:-1));
 int expected=scenario==0 || scenario==10?2:scenario==9?1:0;
 assert(writes==expected);
 assert(pmgr_p0_ans_power_enable()==-1 && writes==expected);
}
'''
out = ROOT / 'artifacts/ans-p0-tests'; out.mkdir(exist_ok=True)
c = out / 'pmgr-plan.c'; c.write_text(prefix+body+tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'pmgr-plan.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
for scenario in range(13):
    subprocess.run([str(exe), str(scenario)], check=True)
print('P0 PMGR plan: 13 cases, all-before-write validation, first-failure stop and no retry passed')
