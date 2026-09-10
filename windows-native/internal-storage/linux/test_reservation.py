"""Exercise actual reservation code with counted resource/allocator mocks."""
from pathlib import Path
import os
import subprocess
HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
source = (HERE / 'ans1_reservation.c').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('#include <linux/'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define IORESOURCE_SYSTEM_RAM 1
#define IORES_DESC_NONE 0
#define REGION_DISJOINT 0
#define GFP_KERNEL 0
struct resource { int dummy; };
static struct resource region;
static bool j42d=true,t7000=true,busy,oom;
static int overlap, allocations, requests;
static bool of_machine_is_compatible(const char *s) { return !strcmp(s,"apple,j42d")?j42d:t7000; }
static int region_intersects(unsigned long long base,size_t size,int flags,int desc) {
    assert(base==0x87f600000ULL && size==0xa00000 && flags==1 && !desc); return overlap;
}
static void *kzalloc(size_t n,int f) { assert(!f); if(oom)return NULL; allocations++; return calloc(1,n); }
static void kfree(void *p) { assert(p && allocations>0); allocations--; free(p); }
static struct resource *request_mem_region_exclusive(unsigned long long b,size_t n,const char *name) {
    assert(b==0x87f600000ULL && n==0xa00000 && name); requests++;
    if(busy)return NULL;
    busy=true; return &region;
}
static void release_mem_region(unsigned long long b,size_t n) {
    assert(b==0x87f600000ULL && n==0xa00000 && busy); busy=false;
}
'''
tests = r'''
int main(void) {
    struct ans1_reservation *a=NULL,*b=NULL;
    assert(ans1_reservation_claim(NULL)==-EINVAL);
    j42d=false; assert(ans1_reservation_claim(&a)==-ENODEV && !a);
    j42d=true;t7000=false;assert(ans1_reservation_claim(&a)==-ENODEV && !a);
    t7000=true;
    for(overlap=1;overlap<=2;overlap++) assert(ans1_reservation_claim(&a)==-EBUSY && !a);
    overlap=0;oom=true;assert(ans1_reservation_claim(&a)==-ENOMEM && !a);
    assert(!allocations && !requests);
    oom=false;assert(!ans1_reservation_claim(&a) && a && allocations==1 && busy);
    assert(ans1_reservation_claim(&a)==-EINVAL && allocations==1);
    assert(ans1_reservation_claim(&b)==-EBUSY && !b && allocations==1);
    ans1_reservation_release(a);a=NULL;
    assert(!busy && !allocations);
    assert(!ans1_reservation_claim(&b) && b);
    ans1_reservation_release(b);ans1_reservation_release(NULL);
    assert(!busy && !allocations);
    puts("Reservation ownership and failure-path tests passed");
}
'''
test=out/'test_reservation.c'
test.write_text(prefix+source+tests,encoding='utf-8')
gcc=Path.home()/'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH']=str(gcc.parent)+os.pathsep+os.environ['PATH']
exe=out/'test_reservation.exe'
subprocess.run([str(gcc),'-std=c11','-Wall','-Wextra','-Werror','-O2','-I',str(HERE),
                str(test),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
