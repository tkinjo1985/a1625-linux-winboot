"""Exercise generated AKF send control flow with counted MMIO mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
out = ROOT / 'artifacts/ans-akf-mailbox'
source = (out / 'mailbox.c').read_text()
start = source.index('int apple_mbox_send(')
end = source.index('EXPORT_SYMBOL(apple_mbox_send);', start)
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include "ans1_wire.h"
#define ESHUTDOWN 108
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x,v) ((x)=(v))
#define APPLE_MBOX_TX_TIMEOUT 500
#define APPLE_MBOX_MSG1_MSG 0xffffffffULL
#define FIELD_PREP(mask,val) ((val) & (mask))
struct apple_mbox_msg { u64 msg0; u32 msg1; };
struct hw { bool akf_single_word, has_irq_controls; u32 a2i_control, control_full,
    irq_bit_send_empty, irq_ack, a2i_send0, a2i_send1; };
struct apple_mbox { struct hw *hw; bool active, akf_faulted; char *regs; int tx_lock, irq_send_empty, tx_empty; };
static int reads, writes, held;
static u32 control;
static u64 last_word;
static char registers[64];
#define spin_lock_irqsave(p,f) do { (void)(p); (f)=0; assert(!held); held=1; } while (0)
#define spin_unlock_irqrestore(p,f) do { (void)(p); (void)(f); assert(held); held=0; } while (0)
static u32 readl_relaxed(char *p) { assert(held && p == registers+8); reads++; return control; }
static void writeq_relaxed(u64 word, char *p) { assert(held && p == registers+16); writes++; last_word=word; }
#define readl_poll_timeout_atomic(...) (assert(0), -EIO)
#define writel_relaxed(...) assert(0)
#define enable_irq(...) assert(0)
#define reinit_completion(...) assert(0)
#define wait_for_completion_interruptible_timeout(...) (assert(0), 0)
'''
tests = r'''
int main(void) {
    struct hw hw = {.akf_single_word=true, .a2i_control=8, .control_full=1U<<16, .a2i_send0=16};
    struct apple_mbox m = {.hw=&hw, .regs=registers};
    struct apple_mbox_msg msg = {.msg0=0xff003, .msg1=5};
    assert(apple_mbox_send(&m,msg,false) == -ESHUTDOWN);
    assert(!reads && !writes && !held);
    m.active=true; msg.msg1=256;
    assert(apple_mbox_send(&m,msg,false) == -EINVAL);
    msg.msg1=5; msg.msg0=1ULL<<56;
    assert(apple_mbox_send(&m,msg,false) == -EINVAL);
    assert(!reads && !writes && !held);
    msg.msg0=0xff003; control=1U<<16;
    assert(apple_mbox_send(&m,msg,false) == -EAGAIN);
    assert(apple_mbox_send(&m,msg,true) == -EAGAIN);
    assert(reads==2 && !writes && !held);
    control=0;
    assert(apple_mbox_send(&m,msg,false) == 0);
    assert(reads==3 && writes==1 && last_word==0x05000000000ff003ULL && !held);
    for (unsigned bit=18; bit<=19; bit++) {
        m.akf_faulted=false; control=(1U<<bit)|(1U<<16);
        int before=reads;
        assert(apple_mbox_send(&m,msg,false)==-EIO);
        assert(m.akf_faulted && reads==before+1 && writes==1 && !held);
        control=0;
        assert(apple_mbox_send(&m,msg,true)==-EIO);
        assert(reads==before+1 && writes==1 && !held);
    }
    puts("Generated AKF send MMIO-mock tests passed");
}
'''
test = out / 'test_mailbox_send.c'
test.write_text(prefix + source[start:end] + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_mailbox_send.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
