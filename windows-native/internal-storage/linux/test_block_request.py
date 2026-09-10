"""Test actual block request handler with host block/controller mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
source = (HERE / 'ans1_block.c').read_text()
start = source.index('static blk_status_t ans1_block_request(')
end = source.index('static const struct blk_mq_ops', start)
prefix = r'''
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <errno.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef int blk_status_t;
enum { BLK_STS_OK, BLK_STS_NOTSUPP, BLK_STS_IOERR };
#define REQ_OP_READ 0
struct bio_vec { unsigned int bv_len; char *data; };
struct req_iterator { unsigned int i; };
struct request { int op; u64 sector; unsigned int bytes, count; struct bio_vec vec[2]; };
struct ans1_block { u64 pages; int lock; bool failed; int (*read_page)(void *, u32, void *); void *cookie; char *buffer; };
struct queue { struct ans1_block *queuedata; };
struct blk_mq_hw_ctx { struct queue *queue; };
struct blk_mq_queue_data { struct request *rq; };
#define blk_rq_pos(r) ((r)->sector)
#define blk_rq_bytes(r) ((r)->bytes)
#define req_op(r) ((r)->op)
#define rq_for_each_segment(v,r,it) for ((it).i=0; (it).i<(r)->count && (((v)=(r)->vec[(it).i]),1); (it).i++)
static int starts, ends, calls, status, error, held;
static void blk_mq_start_request(struct request *r) { (void)r; starts++; }
static void blk_mq_end_request(struct request *r, int s) { (void)r; ends++; status=s; }
static void mutex_lock(int *m) { (void)m; assert(!held); held=1; }
static void mutex_unlock(int *m) { (void)m; assert(held); held=0; }
static void memcpy_to_bvec(struct bio_vec *v, const char *src) { memcpy(v->data,src,v->bv_len); }
static int read_page(void *cookie, u32 lba, void *page) {
    (void)cookie; assert(held && lba==1); calls++; memset(page,0x5a,4096); return error;
}
'''
tests = r'''
int main(void) {
    char buffer[4096], dst[4096]; memset(dst,0xa5,sizeof(dst));
    struct ans1_block b = {.pages=2,.read_page=read_page,.buffer=buffer};
    struct queue q = {.queuedata=&b}; struct blk_mq_hw_ctx h = {.queue=&q};
    struct request r = {.sector=8,.bytes=4096,.count=2,.vec={{1024,dst},{3072,dst+1024}}};
    struct blk_mq_queue_data bd = {.rq=&r};
    for (int op=1; op<256; op++) { r.op=op; assert(ans1_block_request(&h,&bd)==BLK_STS_NOTSUPP); }
    assert(!calls && !starts && !ends); r.op=0;
    r.sector=9; assert(ans1_block_request(&h,&bd)==BLK_STS_IOERR);
    r.sector=16; assert(ans1_block_request(&h,&bd)==BLK_STS_IOERR);
    r.sector=8; r.vec[1].bv_len=3073; assert(ans1_block_request(&h,&bd)==BLK_STS_IOERR);
    r.vec[1].bv_len=3071; assert(ans1_block_request(&h,&bd)==BLK_STS_IOERR);
    r.vec[1].bv_len=3072; r.bytes=512; assert(ans1_block_request(&h,&bd)==BLK_STS_IOERR);
    assert(!calls && !starts && !ends); r.bytes=4096; error=-1;
    assert(ans1_block_request(&h,&bd)==BLK_STS_OK && status==BLK_STS_IOERR);
    for (int i=0;i<4096;i++) assert((unsigned char)dst[i]==0xa5);
    assert(calls==1 && starts==1 && ends==1 && !held); error=0;
    assert(ans1_block_request(&h,&bd)==BLK_STS_OK && status==BLK_STS_IOERR);
    assert(calls==1 && starts==2 && ends==2 && b.failed);
    for (int i=0;i<4096;i++) assert((unsigned char)dst[i]==0xa5);
    /* New simulated device; never clear a live controller failure. */
    b = (struct ans1_block){.pages=2,.read_page=read_page,.buffer=buffer};
    assert(ans1_block_request(&h,&bd)==BLK_STS_OK && status==BLK_STS_OK);
    for (int i=0;i<4096;i++) assert(dst[i]==0x5a);
    assert(calls==2 && starts==3 && ends==3 && !held);
    puts("Block request rejection and error-data tests passed");
}
'''
test = out / 'test_block_request.c'
test.write_text(prefix + source[start:end] + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_block_request.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
