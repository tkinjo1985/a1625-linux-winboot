"""Test actual shared-memory owner with counted host allocation mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
out.mkdir(parents=True, exist_ok=True)
source = '\n'.join(x for x in (HERE / 'ans1_shmem.c').read_text().splitlines()
                   if not x.startswith('#include'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef uint64_t dma_addr_t;
struct device { int refs; };
struct mutex { int held; };
struct apple_rtkit_shmem {
 void *buffer, *iomem; size_t size; dma_addr_t iova;
 bool is_mapped; void *private;
};
#define GFP_KERNEL 0
#define ERR_PTR(e) ((void *)(intptr_t)(e))
static int fail, allocations;
static void *kzalloc(size_t n, int f) { (void)f; return fail?NULL:calloc(1,n); }
static void kfree(void *p) { free(p); }
static struct device *get_device(struct device *d) { d->refs++; return d; }
static void put_device(struct device *d) { assert(d->refs==1); d->refs--; }
static void mutex_init(struct mutex *m) { m->held=0; }
static void mutex_lock(struct mutex *m) { assert(!m->held); m->held=1; }
static void mutex_unlock(struct mutex *m) { assert(m->held); m->held=0; }
static void *dma_alloc_coherent(struct device *d,size_t n,dma_addr_t *a,int f) {
 (void)f; assert(d->refs==1); if(fail) return NULL;
 *a=(++allocations)*0x100000ULL;
 void *p=malloc(n); assert(p); memset(p,0xa5,n); return p;
}
'''
tests = r'''
int main(void) {
 struct device d={0}; struct ans1_shmem *o;
 struct apple_rtkit_shmem b={0};
 assert(ans1_shmem_create(NULL)==ERR_PTR(-EINVAL));
 fail=1; assert(ans1_shmem_create(&d)==ERR_PTR(-ENOMEM)); assert(!d.refs);
 fail=0; o=ans1_shmem_create(&d); assert(d.refs==1);
 assert(ans1_shmem_setup(o,&b)==-EINVAL);
 b.size=ANS1_SHMEM_MAX_SIZE+1; assert(ans1_shmem_setup(o,&b)==-EINVAL);
 b.size=4096;
 b.iova=4096; assert(ans1_shmem_setup(o,&b)==-EOPNOTSUPP); b.iova=0;
 b.private=o; assert(ans1_shmem_setup(o,&b)==-EOPNOTSUPP); b.private=NULL;
 fail=1; assert(ans1_shmem_setup(o,&b)==-ENOMEM); assert(!allocations);
 assert(!ans1_shmem_free_unpublished(o)); assert(!d.refs);
 fail=0; o=ans1_shmem_create(&d);
 for(unsigned int i=0;i<ANS1_SHMEM_SLOTS;i++) {
  memset(&b,0,sizeof(b)); b.size=4096;
  assert(!ans1_shmem_setup(o,&b));
  for(size_t j=0;j<b.size;j++) assert(!((unsigned char *)b.buffer)[j]);
  void *p=b.buffer;
  ans1_shmem_detach(o,&b); assert(!b.private);
  memset(&b,0,sizeof(b)); /* RTKit reinit/free discards its descriptor. */
  assert(o->records[i].buffer==p && o->records[i].size==4096);
  assert(ans1_shmem_free_unpublished(o)==-EBUSY && d.refs==1);
 }
 b.size=4096; assert(ans1_shmem_setup(o,&b)==-ENOSPC);
 assert(allocations==4 && o->count==4);
 /* Mock-only cleanup; deliberately absent from production API. */
 for(unsigned int i=0;i<o->count;i++) free(o->records[i].buffer);
 free(o);
 puts("Shared memory limits, allocation failure and detached retention passed");
}
'''
test = out / 'test_shmem.c'
test.write_text(prefix + source + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_shmem.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
