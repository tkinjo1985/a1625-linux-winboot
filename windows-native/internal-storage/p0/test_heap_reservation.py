"""Exercise production firmware reservation and heap bounds without real RAM access."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/heapblock.c').read_text()
def function(sig):
    start=source.index(sig+'\n{')
    return source[start:source.index('\n}',start)+2]
prefix=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <setjmp.h>
typedef uint64_t u64; typedef uint8_t u8;
static struct {u64 phys_base,mem_size,top_of_kernel_data;} cur_boot_args;
static u64 mem_size_actual;
static uintptr_t _base,_end,p0_firmware_limit;
static void *heap_base,*heap_limit;
static jmp_buf trap;
static void mock_log(const char *s,...) {(void)s;}
#define printf mock_log
static void panic(const char *s,...) {(void)s;longjmp(trap,1);}
static void reset(void) {
 cur_boot_args.phys_base=0x800000000ULL;
 cur_boot_args.top_of_kernel_data=0x801000000ULL;
 mem_size_actual=0x80000000;
 _base=0x800100000ULL;_end=0x800400000ULL;
 heap_base=(void *)0x802000000ULL;heap_limit=NULL;p0_firmware_limit=0;
}
'''
tests=r'''
int main(void) {
 const u64 fw=0x87f600000ULL,size=0xa00000;
 reset();assert(heapblock_p0_reserve_firmware(fw,size));
 assert((u64)heap_limit==fw);
 heapblock_set_limit(NULL);assert((u64)heap_limit==fw);
 heapblock_set_limit((void *)(fw+size));assert((u64)heap_limit==fw);
 assert(!heapblock_p0_reserve_firmware(fw,size));
 heap_base=(void *)(fw-4096);
 assert(heapblock_alloc_aligned(4096,4096)==(void *)(fw-4096));
 if(!setjmp(trap)) {heapblock_alloc_aligned(1,4096);assert(false);}
 assert((u64)heap_base==fw);
 for(int bad=0;bad<8;bad++) {
  reset();u64 base=fw,n=size;
  if(bad==0)n=0;
  if(bad==1)base++;
  if(bad==2)n++;
  if(bad==3)heap_base=(void *)(fw+4096);
  if(bad==4)_end=fw+4096;
  if(bad==5)_base=cur_boot_args.phys_base-1;
  if(bad==6)base=UINT64_MAX-4095;
  if(bad==7)mem_size_actual=0;
  assert(!heapblock_p0_reserve_firmware(base,n));
  assert(!p0_firmware_limit && !heap_limit);
 }
 reset();heap_limit=(void *)(fw-0x100000);
 assert(heapblock_p0_reserve_firmware(fw,size));
 heapblock_set_limit(NULL);assert((u64)heap_limit==fw-0x100000);
 reset();heap_base=(void *)(UINT64_MAX-1);
 if(!setjmp(trap)) {heapblock_alloc_aligned(1,4096);assert(false);}
 reset();
 if(!setjmp(trap)) {heapblock_alloc_aligned(SIZE_MAX,4096);assert(false);}
 puts("P0 firmware/heap separation, fixed ceiling and allocator overflow tests passed");
}
'''
out=ROOT/'artifacts/ans-p0-tests';out.mkdir(exist_ok=True)
c=out/'heap-reservation.c'
c.write_text(prefix+'\n'.join(function(s) for s in (
 'void heapblock_set_limit(void *limit)',
 'bool heapblock_p0_reserve_firmware(u64 phys, u64 size)',
 'void *heapblock_alloc_aligned(size_t size, size_t align)'))+tests)
gcc=Path.home()/'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH']=str(gcc.parent)+os.pathsep+os.environ['PATH']
exe=out/'heap-reservation.exe'
subprocess.run([str(gcc),'-std=c11','-Wall','-Wextra','-Werror',str(c),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
