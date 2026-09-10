"""Check generated start failure paths with counted PM and register mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-akf-mailbox'
source = (out / 'mailbox.c').read_text()
start = source.index('static int apple_mbox_start_locked(')
end = source.index('int apple_mbox_start(', start)
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
typedef uint32_t u32;
#define BIT(n) (1U<<(n))
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x,v) ((x)=(v))
struct hw { bool akf_single_word, has_irq_controls; u32 a2i_control,
    i2a_control, irq_bit_recv_not_empty, irq_bit_send_empty, irq_enable; };
struct apple_mbox { struct hw *hw; bool active, akf_faulted; char *regs;
    void *dev; int akf_poll_work, irq_recv_not_empty; };
static char regs[64];
static u32 tx, rx;
static int pm_gets, puts_count, reads, writes, scheduled, pm_error;
static int pm_runtime_resume_and_get(void *d) { (void)d; pm_gets++; return pm_error; }
static void pm_runtime_mark_last_busy(void *d) { (void)d; }
static void pm_runtime_put_autosuspend(void *d) { (void)d; puts_count++; }
static u32 readl_relaxed(char *p) { reads++; assert(p==regs+8 || p==regs+32); return p==regs+8 ? tx:rx; }
static void writel_relaxed(u32 v, char *p) {
    assert(reads==2); assert(p==regs+8 || p==regs+32);
    assert(v==((p==regs+8 ? tx:rx)|1)); writes++;
}
static void schedule_delayed_work(int *p, int delay) { (void)p; assert(!delay); scheduled++; }
#define enable_irq(...) assert(0)
'''
tests = r'''
int main(void) {
    struct hw hw={.akf_single_word=true,.a2i_control=8,.i2a_control=32};
    struct apple_mbox m={.hw=&hw,.regs=regs};
    for (unsigned side=0;side<2;side++) for (unsigned bit=18;bit<=19;bit++) {
        m.akf_faulted=false; pm_gets=puts_count=reads=writes=scheduled=0;
        tx=side ? 0:BIT(bit); rx=side ? BIT(bit):0;
        assert(apple_mbox_start_locked(&m)==-EIO);
        assert(m.akf_faulted && !m.active && pm_gets==1 && puts_count==1);
        assert(reads==2 && !writes && !scheduled);
        tx=rx=0;
        assert(apple_mbox_start_locked(&m)==-EIO);
        assert(pm_gets==1 && reads==2 && puts_count==1);
    }
    m.akf_faulted=false; pm_gets=puts_count=reads=0; pm_error=-EIO;
    assert(apple_mbox_start_locked(&m)==-EIO);
    assert(pm_gets==1 && !puts_count && !reads && !m.active);
    pm_error=0; pm_gets=0;
    assert(apple_mbox_start_locked(&m)==0);
    assert(m.active && pm_gets==1 && reads==2 && writes==2 && scheduled==1);
    assert(apple_mbox_start_locked(&m)==0 && pm_gets==1 && writes==2);
    puts("Generated AKF start PM/fault tests passed");
}
'''
test = out / 'test_mailbox_start.c'
test.write_text(prefix + source[start:end] + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_mailbox_start.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
