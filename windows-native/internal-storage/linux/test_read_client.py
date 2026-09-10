"""Run real read-client code with deterministic RTKit/clock/DMA mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
header = '\n'.join(s for s in (HERE / 'ans1_read_client.h').read_text().splitlines()
                   if not s.startswith('#include <linux/'))
source = '\n'.join(s for s in (HERE / 'ans1_read_client.c').read_text().splitlines()
                   if not s.startswith('#include'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "ans1_read.h"
#include "ans1_queue.h"
struct completion { bool done; };
struct mutex { bool held; };
typedef struct mutex spinlock_t;
struct apple_rtkit { int dummy; };
typedef u64 dma_addr_t;
struct ans1_dma { void *command, *data; u64 command_dma, data_dma; bool published; };
static void *ans1_dma_command(struct ans1_dma *d, dma_addr_t *a) { *a=d->command_dma; return d->command; }
static void *ans1_dma_data(struct ans1_dma *d, dma_addr_t *a) { *a=d->data_dma; return d->data; }
static void ans1_dma_publish(struct ans1_dma *d) { d->published=true; }
static u64 clock_ns;
static int sends, mode, barriers;
static void mutex_init(struct mutex *m) { m->held=false; }
static void mutex_lock(struct mutex *m) { assert(!m->held); m->held=true; }
static void mutex_unlock(struct mutex *m) { assert(m->held); m->held=false; }
#define spin_lock_init(m) mutex_init(m)
#define spin_lock_irqsave(m,f) do { (f)=0; mutex_lock(m); } while (0)
#define spin_unlock_irqrestore(m,f) do { (void)(f); mutex_unlock(m); } while (0)
static void init_completion(struct completion *c) { c->done=false; }
#define reinit_completion(c) init_completion(c)
static void complete(struct completion *c) { c->done=true; }
static u64 ktime_get_ns(void) { return clock_ns; }
static unsigned long nsecs_to_jiffies(u64 ns) { return (ns+999999)/1000000; }
#define max_t(t,a,b) ((t)(a) > (t)(b) ? (t)(a) : (t)(b))
static unsigned long wait_for_completion_timeout(struct completion *c, unsigned long ticks) {
    if (c->done) return 1;
    clock_ns += (u64)ticks*1000000; return 0;
}
static void dma_wmb(void) { barriers++; }
static void dma_rmb(void) { barriers++; }
static int apple_rtkit_send_message(struct apple_rtkit *, u8, u64, struct completion *, bool);
static int apple_rtkit_start_ep(struct apple_rtkit *, u8);
static u8 advertised=5;
static u8 apple_rtkit_ans1_endpoint(struct apple_rtkit *r) { (void)r; return advertised; }
'''
tests = r'''
static struct ans1_read_client *active;
static struct ans1_dma *owner;
static int starts;
static int apple_rtkit_start_ep(struct apple_rtkit *r, u8 ep) {
    (void)r; assert(ep==5 && !active->state_lock.held); starts++;
    assert(active->tx.state==ANS1_TX_WAITING && active->tx.phase==ANS1_WAIT_READY);
    if(mode==1) return -EIO;
    if(mode==2) return 0;
    if(mode==3) { ans1_read_client_abort(active); return 0; }
    ans1_read_client_receive(active,5,mode==4 ? 0xafd2 : 0xafe2);
    return 0;
}
static int apple_rtkit_send_message(struct apple_rtkit *r, u8 ep, u64 msg,
                                   struct completion *completion, bool atomic) {
    (void)r; (void)completion; assert(!atomic && ep==5);
    assert(!active->state_lock.held); sends++;
    if (msg!=0xff003) {
        assert(owner && owner->published);
        if (msg==0x02000001) {
            assert(sends==2);
            if(mode==5) ans1_read_client_abort(active);
            return mode==4 ? -EIO : 0;
        }
        assert(msg==((owner->command_dma<<16)|0x20) && sends==1);
        if(mode==1) return -EIO;
        if(mode==2) return 0;
        ans1_read_client_receive(active,5,mode==3 ? 2 : 0xafd2);
        return 0;
    }
    if (mode==1) return -EIO;
    if (mode==2) return 0; /* No reply. */
    if (mode==4) { ans1_read_client_abort(active); return 0; }
    if (active->command[0]==0) {
        for(int i=0;i<128;i++) assert(!active->command[i]);
        ans1_put_le32(active->command+0x30,2);
        ans1_put_le32(active->command+0x34,mode==6 ? 16384 : 4096);
        ans1_put_le32(active->command+0x3c,mode==5 ? 0 : 1);
        ans1_put_le32(active->command+0x44,mode==7 ? 1 : 0);
    }
    memset(active->data,0x5a,4096);
    ans1_read_client_receive(active,5,mode==3 ? 0x12 : 2);
    return 0;
}
int main(void) {
    struct ans1_read_client c; struct apple_rtkit r;
    unsigned char cmd[4096], data[4096], dst[4096]; active=&c;
    for (mode=0; mode<5; mode++) {
        sends=barriers=0; clock_ns=0; memset(dst,0xa5,sizeof(dst));
        assert(!ans1_read_client_init(&c,&r,5,2,cmd,0x800000000ULL,data,0x800001000ULL));
        assert(ans1_read_client_read(&c,1,dst)==-EIO && !sends);
        c.registered=true; /* Isolate read handling from registration below. */
        int result=ans1_read_client_read(&c,1,dst);
        assert(!c.request_lock.held && !c.state_lock.held && sends==1);
        if (mode==0) {
            assert(!result && c.tx.state==ANS1_TX_IDLE && barriers==2);
            for (int i=0;i<4096;i++) assert(dst[i]==0x5a);
        } else {
            assert(result==-EIO && c.tx.state==ANS1_TX_QUARANTINED);
            for (int i=0;i<4096;i++) assert(dst[i]==0xa5);
            assert(ans1_read_client_read(&c,1,dst)==-EIO && sends==1);
            if (mode==2) assert(clock_ns==3000000000ULL);
        }
    }
    assert(ans1_read_client_init(&c,&r,5,2,cmd,0x800000000ULL,data,0x800000000ULL)==-EINVAL);
    assert(!ans1_read_client_init(&c,&r,5,2,cmd,0x800000000ULL,data,0x800001000ULL));
    sends=0; ans1_read_client_stop(&c);
    assert(ans1_read_client_read(&c,1,dst)==-EIO && !sends);
    ans1_read_client_stop(&c);
    assert(c.tx.state==ANS1_TX_QUARANTINED && !c.request_lock.held && !c.state_lock.held);
    struct ans1_dma dma={cmd,data,0x800000000ULL,0x800001000ULL,false}; owner=&dma;
    for(mode=0;mode<6;mode++) {
        sends=0; clock_ns=0; dma.published=false;
        assert(!ans1_read_client_init(&c,&r,5,2,cmd,dma.command_dma,data,dma.data_dma));
        assert(ans1_read_client_register(&c,&dma)==-EIO && !sends && !dma.published);
        c.ready=true; /* Isolate registration from start below. */
        int result=ans1_read_client_register(&c,&dma);
        assert(dma.published && !c.request_lock.held && !c.state_lock.held);
        assert(sends==(mode==0 || mode>=4 ? 2 : 1));
        if(!mode) {
            assert(!result && c.registered && c.tx.state==ANS1_TX_IDLE);
            assert(ans1_read_client_register(&c,&dma)==-EIO && sends==2);
        } else {
            assert(result==-EIO && !c.registered && c.tx.state==ANS1_TX_QUARANTINED);
            int previous=sends;
            assert(ans1_read_client_register(&c,&dma)==-EIO && sends==previous);
            if(mode==2) assert(clock_ns==3000000000ULL);
        }
    }
    sends=0; dma.published=false;
    assert(!ans1_read_client_init(&c,&r,5,2,cmd,dma.command_dma,data,dma.data_dma));
    dma.data_dma+=4096;
    assert(ans1_read_client_register(&c,&dma)==-EINVAL && !sends && !dma.published);
    for(mode=0;mode<8;mode++) {
        struct ans1_geometry geometry, before;
        memset(&geometry,0xa5,sizeof(geometry)); memcpy(&before,&geometry,sizeof(before));
        sends=0; clock_ns=0;
        assert(!ans1_read_client_init(&c,&r,5,0,cmd,0x800000000ULL,data,0x800001000ULL));
        c.registered=true;
        assert(ans1_read_client_read(&c,0,dst)==-EINVAL && !sends);
        int result=ans1_read_client_identify(&c,&geometry);
        assert(sends==1);
        if(!mode) {
            assert(!result && c.capacity==2 && geometry.bytes==8192);
            assert(ans1_read_client_identify(&c,&geometry)==-EIO && sends==1);
            assert(!ans1_read_client_read(&c,1,dst) && sends==2);
        } else {
            assert(result==-EIO && !c.capacity && c.tx.state==ANS1_TX_QUARANTINED);
            assert(!memcmp(&geometry,&before,sizeof(before)));
            assert(ans1_read_client_identify(&c,&geometry)==-EIO && sends==1);
        }
    }
    for(mode=0;mode<5;mode++) {
        starts=sends=0; clock_ns=0;
        assert(!ans1_read_client_init(&c,&r,5,0,cmd,0x800000000ULL,data,0x800001000ULL));
        int result=ans1_read_client_start(&c);
        assert(starts==1 && !sends && !c.state_lock.held && !c.request_lock.held);
        if(!mode) assert(!result && c.ready && c.tx.state==ANS1_TX_IDLE);
        else assert(result==-EIO && !c.ready && c.tx.state==ANS1_TX_QUARANTINED);
        assert(ans1_read_client_start(&c)==-EIO && starts==1);
        if(mode==2) assert(clock_ns==3000000000ULL);
    }
    mode=starts=sends=0; clock_ns=0;
    dma.data_dma=0x800001000ULL; dma.published=false;
    struct ans1_geometry found;
    assert(!ans1_read_client_init(&c,&r,5,0,cmd,dma.command_dma,data,dma.data_dma));
    advertised=6;
    assert(ans1_read_client_start(&c)==-EINVAL && !starts && !sends);
    advertised=0;
    assert(ans1_read_client_start(&c)==-EINVAL && !starts && !sends);
    advertised=5;
    assert(!ans1_read_client_start(&c));
    assert(!ans1_read_client_register(&c,&dma));
    assert(!ans1_read_client_identify(&c,&found));
    assert(!ans1_read_client_read(&c,1,dst));
    assert(starts==1 && sends==4 && dma.published && found.pages==2);
    ans1_read_client_stop(&c);
    assert(ans1_read_client_read(&c,1,dst)==-EIO && sends==4);
    puts("Read-client RTKit fault-injection and full lifecycle tests passed");
}
'''
test = out / 'test_read_client.c'
test.write_text(prefix + header + '\n' + source + '\n' + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_read_client.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
    '-I', str(HERE), str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
