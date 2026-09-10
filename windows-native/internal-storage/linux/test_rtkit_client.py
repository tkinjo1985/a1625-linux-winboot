"""Exercise actual callback adapter: crashes before/after reader attachment."""
from pathlib import Path
import os
import subprocess
HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
out.mkdir(parents=True, exist_ok=True)
def body(name):
    return '\n'.join(x for x in (HERE / name).read_text().splitlines()
                     if not x.startswith('#include'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef uint8_t u8;
typedef uint64_t u64;
#define IS_ERR_OR_NULL(p) (!(p) || (uintptr_t)(p) >= (uintptr_t)-4095)
struct mutex { bool held; };
static void mutex_init(struct mutex *m) { m->held=false; }
static void mutex_lock(struct mutex *m) { assert(!m->held); m->held=true; }
static void mutex_unlock(struct mutex *m) { assert(m->held); m->held=false; }
struct ans1_shmem { int setup, detach; };
struct apple_rtkit_shmem { int unused; };
struct ans1_read_client { int aborted, received; };
struct apple_rtkit_ops {
 void (*crashed)(void *,const void *,size_t);
 void (*recv_message)(void *,u8,u64);
 bool (*recv_message_early)(void *,u8,u64);
 int (*shmem_setup)(void *,struct apple_rtkit_shmem *);
 void (*shmem_destroy)(void *,struct apple_rtkit_shmem *);
 bool ans1_endpoint5;
};
static void ans1_read_client_abort(struct ans1_read_client *r) { r->aborted++; }
static void ans1_read_client_receive(struct ans1_read_client *r,u8 e,u64 m) {
 assert(e==5 && m==42); r->received++;
}
static int ans1_shmem_setup(struct ans1_shmem *s,struct apple_rtkit_shmem *b) {
 assert(b); s->setup++; return -ENOSPC;
}
static void ans1_shmem_detach(struct ans1_shmem *s,struct apple_rtkit_shmem *b) {
 assert(b); s->detach++;
}
'''
tests = r'''
int main(void) {
 struct ans1_rtkit_client c;
 struct ans1_shmem s={0}; struct apple_rtkit_shmem b={0};
 struct ans1_read_client r={0};
 const struct apple_rtkit_ops *o=&ans1_rtkit_client_ops;
 assert(o->ans1_endpoint5 && !o->recv_message_early);
 assert(ans1_rtkit_client_init(&c,NULL)==-EINVAL);
 assert(!ans1_rtkit_client_init(&c,&s));
 o->recv_message(&c,5,42); assert(!r.received);
 assert(o->shmem_setup(&c,&b)==-ENOSPC && s.setup==1);
 o->crashed(&c,NULL,0);
 assert(ans1_rtkit_client_attach(&c,&r)==-EIO);
 assert(o->shmem_setup(&c,&b)==-EIO && s.setup==1);
 o->shmem_destroy(&c,&b); assert(s.detach==1);
 /* A separate controller lifetime for the attached-reader scenario. */
 struct ans1_rtkit_client d;
 assert(!ans1_rtkit_client_init(&d,&s));
 assert(!ans1_rtkit_client_attach(&d,&r));
 assert(ans1_rtkit_client_attach(&d,&r)==-EBUSY);
 o->recv_message(&d,5,42); assert(r.received==1);
 o->crashed(&d,NULL,0); assert(r.aborted==1);
 o->recv_message(&d,5,42); assert(r.received==1);
 ans1_rtkit_client_detach(&d);
 o->crashed(&d,NULL,0); assert(r.aborted==1);
 assert(ans1_rtkit_client_attach(&d,&r)==-EIO);
 puts("RTKit adapter crash latch, routing and retained-owner delegation passed");
}
'''
test = out / 'test_rtkit_client.c'
test.write_text(prefix + body('ans1_rtkit_client.h') + '\n' +
                body('ans1_rtkit_client.c') + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_client.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
