"""Exercise actual DMA-owner implementation with counted allocation mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
out.mkdir(parents=True, exist_ok=True)
source = (HERE / 'ans1_dma.c').read_text()
source = '\n'.join(line for line in source.splitlines() if not line.startswith('#include'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "ans1_queue.h"
#include "ans1_read.h"
typedef uint64_t dma_addr_t;
struct device { int refs; };
struct ans1_dma;
int ans1_dma_free_unpublished(struct ans1_dma *dma);
#define GFP_KERNEL 0
#define ERR_PTR(e) ((void *)(intptr_t)(e))
static int attempt, fail_at, live, freed;
static dma_addr_t addresses[2];
static void *kzalloc(size_t n, int flags) {
    (void)flags; if (++attempt == fail_at) return NULL;
    live++; return calloc(1,n);
}
static void kfree(void *p) { assert(p); live--; free(p); }
static struct device *get_device(struct device *d) { d->refs++; return d; }
static void put_device(struct device *d) { assert(d->refs>0); d->refs--; }
static void *dma_alloc_coherent(struct device *d, size_t n, dma_addr_t *a, int flags) {
    (void)flags; assert(d->refs==1 && n==4096);
    if (++attempt == fail_at) return NULL;
    *a=addresses[attempt-2]; live++;
    void *p=malloc(n); assert(p); memset(p,0xa5,n); return p;
}
static void dma_free_coherent(struct device *d, size_t n, void *p, dma_addr_t a) {
    assert(d->refs==1 && n==4096 && p);
    (void)a; freed++; live--; free(p);
}
static void reset(void) {
    assert(!live); attempt=fail_at=freed=0;
    addresses[0]=0x1000; addresses[1]=0x2000;
}
'''
tests = r'''
int main(void) {
    struct device dev={0}; struct ans1_dma *d; dma_addr_t a;
    assert(ans1_dma_alloc(NULL)==ERR_PTR(-EINVAL));
    for (int i=1;i<=3;i++) {
        reset(); fail_at=i; assert(ans1_dma_alloc(&dev)==ERR_PTR(-ENOMEM));
        assert(!live && !dev.refs && freed==(i==3));
    }
    for (int i=0;i<4;i++) {
        reset();
        if(i==0) addresses[1]=addresses[0];
        if(i==1) addresses[0]=1ULL<<40;
        if(i==2) addresses[1]=1ULL<<44;
        if(i==3) addresses[1]++;
        assert(ans1_dma_alloc(&dev)==ERR_PTR(-ERANGE));
        assert(!live && !dev.refs && freed==2);
    }
    reset(); d=ans1_dma_alloc(&dev); assert(live==3 && dev.refs==1);
    unsigned char *p=ans1_dma_command(d,&a); assert(a==0x1000);
    for(int i=0;i<4096;i++) assert(!p[i]);
    p=ans1_dma_data(d,&a); assert(a==0x2000);
    for(int i=0;i<4096;i++) assert(!p[i]);
    assert(!ans1_dma_free_unpublished(d)); assert(!live && !dev.refs && freed==2);
    reset(); d=ans1_dma_alloc(&dev); ans1_dma_publish(d); ans1_dma_publish(d);
    assert(ans1_dma_free_unpublished(d)==-EBUSY);
    assert(ans1_dma_free_unpublished(d)==-EBUSY);
    assert(live==3 && dev.refs==1 && !freed);
    puts("DMA allocation unwind and published retention tests passed");
    return 0;
}
'''
test = out / 'test_dma.c'
test.write_text(prefix + source + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_dma.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                '-I', str(HERE), str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
