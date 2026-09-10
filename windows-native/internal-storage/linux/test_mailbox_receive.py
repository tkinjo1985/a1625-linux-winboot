"""Exercise generated AKF receive functions with a counted FIFO model."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
out = ROOT / 'artifacts/ans-akf-mailbox'
source = (out / 'mailbox.c').read_text()
start = source.index('static int apple_mbox_poll_locked(')
end = source.index('static irqreturn_t apple_mbox_recv_irq(', start)
body = source[start:end]
start = source.index('int apple_mbox_poll(')
end = source.index('EXPORT_SYMBOL(apple_mbox_poll);', start)
body += source[start:end]
prefix = r'''
#include <assert.h>
#include <stdio.h>
#include <errno.h>
#include "ans1_wire.h"
#define ESHUTDOWN 108
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x,v) ((x)=(v))
#define APPLE_MBOX_MSG1_MSG 0xffffffffULL
#define FIELD_GET(mask,val) ((val) & (mask))
struct apple_mbox_msg { u64 msg0; u32 msg1; };
struct hw { bool akf_single_word, has_irq_controls; u32 i2a_control, control_empty,
    i2a_recv0, i2a_recv1, irq_bit_recv_not_empty, irq_ack; };
struct apple_mbox { struct hw *hw; bool active, akf_faulted; char *regs; int rx_lock;
    void (*rx)(struct apple_mbox *, struct apple_mbox_msg, void *); void *cookie; };
static int held, controls, reads, callbacks, available;
static u32 fault;
static char registers[64];
#define spin_lock_irqsave(p,f) do { (void)(p); (f)=0; assert(!held); held=1; } while (0)
#define spin_unlock_irqrestore(p,f) do { (void)(p); (void)(f); assert(held); held=0; } while (0)
static u32 readl_relaxed(char *p) { assert(held && p==registers+32); controls++; return fault | (available ? 0 : 1U<<17); }
static u64 readq_relaxed(char *p) {
    assert(held && p==registers+56 && available>0);
    available--; reads++; return 0x0500000000000000ULL | (u64)reads;
}
#define writel_relaxed(...) assert(0)
static void receive(struct apple_mbox *m, struct apple_mbox_msg msg, void *cookie) {
    (void)m; assert(cookie==registers && held);
    callbacks++; assert(msg.msg1==5 && msg.msg0==(u64)callbacks);
}
'''
tests = r'''
int main(void) {
    struct hw hw = {.akf_single_word=true, .i2a_control=32, .control_empty=1U<<17, .i2a_recv0=56};
    struct apple_mbox m = {.hw=&hw, .regs=registers, .rx=receive, .cookie=registers};
    available=100;
    assert(apple_mbox_poll(&m)==-ESHUTDOWN && !controls && !reads && !held);
    m.active=true;
    assert(apple_mbox_poll(&m)==64 && reads==64 && callbacks==64 && available==36 && !held);
    assert(apple_mbox_poll(&m)==36 && reads==100 && callbacks==100 && !available && !held);
    assert(apple_mbox_poll(&m)==0 && reads==100 && !held);
    int before=controls;
    m.active=false; available=10;
    assert(apple_mbox_poll(&m)==-ESHUTDOWN && controls==before && reads==100 && !held);
    m.active=true;
    for (unsigned bit=18; bit<=19; bit++) {
        m.akf_faulted=false; fault=1U<<bit;
        assert(apple_mbox_poll(&m)==-EIO && m.akf_faulted);
        assert(reads==100 && callbacks==100 && !held);
        before=controls; fault=0;
        assert(apple_mbox_poll(&m)==-EIO && controls==before);
    }
    puts("Generated AKF receive FIFO-model tests passed");
}
'''
test = out / 'test_mailbox_receive.c'
test.write_text(prefix + body + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_mailbox_receive.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
