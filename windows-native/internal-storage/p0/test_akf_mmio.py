"""Run actual AKF map/start/stop/send bodies against a bounded MMIO model."""
from pathlib import Path
import os
import subprocess
ROOT=Path(__file__).resolve().parents[3]
s=(ROOT/'third_party/HoolockLinux-m1n1-p0/src/akf.c').read_text()
defs=s[s.index('#define AKF_REMAP'):s.index('bool akf_p0_reserve_firmware')]
def function(sig):
 start=s.index(sig+'\n{');return s[start:s.index('\n}',start)+2]
prefix=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef uint64_t u64;typedef uint32_t u32;
typedef struct akf_dev akf_dev_t;
#define ANS1_P0 1
#define BIT(n) (1ULL<<(n))
'''
mocks=r'''
static void *adt;
static unsigned map_writes,starts,stops,polls,sends,frees;
static u32 cpu;
static bool full, start_stuck;
static void mock_log(const char *s,...) {(void)s;}
#define printf mock_log
static int adt_first_child_offset(void *a,int n) {(void)a;(void)n;return 1;}
static bool akf_fw_get_region(int n,u64 *p,u64 *i,u64 *z) {
 assert(n==1);*p=p0_fw_phys;*i=p0_fw_iova;*z=p0_fw_size;return true;
}
static u32 read32(u64 a) {
 if(a==0x208041020ULL)return 1U<<17;
 assert(a==0x208040028ULL);return cpu;
}
static void write32(u64 a,u32 v) {
 const u64 offsets[]={0x10,0x14,8,12,0x18,0x1c,0x20};
 const u32 values[]={0,0,0x7f600000,8,0xa00000,0,1};
 assert(map_writes<7 && a==0x208040000ULL+offsets[map_writes]);
 assert(v==values[map_writes]);map_writes++;
}
static void set32(u64 a,u32 v) {assert(a==0x208040028ULL && v==16);starts++;if(!start_stuck)cpu|=v;}
static void clear32(u64 a,u32 v) {assert(a==0x208040028ULL && v==16);stops++;cpu&=~v;}
static int poll32(u64 a,u32 m,u32 v,u32 n) {
 assert(a==0x208041008ULL && m==65536 && !v && n==200000);polls++;return full?1:0;
}
static void dma_wmb(void) {}
static void write64(u64 a,u64 v) {(void)v;assert(a==0x208041010ULL);sends++;}
static void mock_free(void *p) {(void)p;frees++;}
#define free mock_free
static void reset(akf_dev_t *a) {
 memset(a,0,sizeof(*a));a->cpu_base=0x208040000ULL;a->base=0x208041000ULL;
 p0_fw_reserved=true;p0_fw_phys=0x87f600000ULL;p0_fw_iova=0;p0_fw_size=0xa00000;
 map_writes=starts=stops=polls=sends=frees=cpu=0;full=start_stuck=false;
}
'''
tests=r'''
int main(void) {
 akf_dev_t a;reset(&a);
 assert(!akf_send(&a,0) && !polls);
 akf_cpu_start(&a);assert(!starts);
 assert(akf_map_preloaded_fw(&a) && map_writes==7);
 assert(!akf_map_preloaded_fw(&a) && map_writes==7);
 akf_cpu_start(&a);akf_cpu_start(&a);assert(starts==1 && cpu==16);
 for(int i=0;i<128;i++)assert(akf_send(&a,0));
 assert(!akf_send(&a,0) && sends==128 && polls==128);
 for(int i=0;i<4;i++)akf_cpu_stop(&a);
 assert(stops==2 && !cpu && a.p0_stops==2);
 akf_cpu_start(&a);assert(starts==1);
 assert(!akf_send(&a,0) && polls==128);
 akf_free(&a);assert(!frees);
 reset(&a);cpu=16;
 assert(!akf_map_preloaded_fw(&a) && !map_writes);
 reset(&a);assert(akf_map_preloaded_fw(&a));start_stuck=true;
 akf_cpu_start(&a);assert(a.p0_failed && !akf_send(&a,0) && !polls);
 reset(&a);assert(akf_map_preloaded_fw(&a));akf_cpu_start(&a);full=true;
 assert(!akf_send(&a,0) && polls==1 && !sends);
 full=false;assert(!akf_send(&a,0) && polls==1 && !sends);
 reset(&a);a.p0_recv_checks=0xffffff;
 assert(!akf_can_recv(&a) && !a.p0_failed && a.p0_recv_checks==0x1000000);
 assert(!akf_can_recv(&a) && a.p0_failed && a.p0_recv_checks==0x1000000);
 puts("P0 AKF exact remap writes, one start, bounded clear/send and failure latches passed");
}
'''
out=ROOT/'artifacts/ans-p0-tests';out.mkdir(exist_ok=True)
c=out/'akf-mmio.c'
c.write_text(prefix+defs+mocks+'\n'.join(function(sig) for sig in (
 'bool akf_map_preloaded_fw(akf_dev_t *akf)', 'void akf_cpu_start(akf_dev_t *akf)',
 'void akf_cpu_stop(akf_dev_t *akf)', 'void akf_free(akf_dev_t *akf)',
 'bool akf_send(akf_dev_t *akf, u64 msg)', 'bool akf_can_recv(akf_dev_t *akf)'))+tests)
gcc=Path.home()/'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH']=str(gcc.parent)+os.pathsep+os.environ['PATH']
exe=out/'akf-mmio.exe'
subprocess.run([str(gcc),'-std=c11','-Wall','-Wextra','-Werror',str(c),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
