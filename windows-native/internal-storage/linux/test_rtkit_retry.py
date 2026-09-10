"""Execute the generated RTKit send function with deterministic host mocks."""
from pathlib import Path
import subprocess
import os

ROOT = Path(__file__).resolve().parents[3]
out = ROOT / 'artifacts/ans-rtkit-build'
source = (out / 'rtkit.c').read_text()
start = source.index('int apple_rtkit_send_message(')
end = source.index('EXPORT_SYMBOL_GPL(apple_rtkit_send_message);', start)
function = source[start:end]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
typedef uint8_t u8;
typedef uint64_t u64;
typedef int64_t ktime_t;
struct completion { int unused; };
struct apple_mbox_msg { u64 msg0; unsigned int msg1; };
struct apple_rtkit { bool crashed; int app_ep_start; void *mbox; };
static ktime_t clock_us;
static int calls, sleeps, fail_count, failure, barriers;
static bool running, crash_on_sleep;
static struct apple_rtkit *active;
#define dev_warn(...) ((void)0)
static ktime_t ktime_get(void) { return clock_us; }
static ktime_t ktime_add_ms(ktime_t t, int ms) { return t + ms * 1000; }
static int ktime_compare(ktime_t a, ktime_t b) { return (a > b) - (a < b); }
static bool apple_rtkit_is_running(struct apple_rtkit *r) { (void)r; return running; }
static void dma_wmb(void) { barriers++; }
static void usleep_range(int low, int high) {
    assert(low == 1000 && high == 2000);
    clock_us += high; sleeps++;
    if (crash_on_sleep) active->crashed = true;
}
static int apple_mbox_send(void *m, struct apple_mbox_msg msg, bool atomic) {
    (void)m; (void)atomic;
    assert(msg.msg0 == 0xff003 && msg.msg1 == 6);
    assert(barriers == 1);
    calls++;
    return calls <= fail_count ? failure : 0;
}
static void reset(struct apple_rtkit *r) {
    *r = (struct apple_rtkit){.app_ep_start = 6};
    active = r; clock_us = 0; calls = sleeps = barriers = 0;
    fail_count = 0; failure = -EAGAIN; running = true; crash_on_sleep = false;
}
'''
tests = r'''
int main(void) {
    struct apple_rtkit r;
    reset(&r); fail_count = 1000000;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, false) == -ETIMEDOUT);
    assert(clock_us == 500000 && calls == 250 && sleeps == 250);
    reset(&r); fail_count = 2;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, false) == 0);
    assert(calls == 3 && sleeps == 2);
    reset(&r); fail_count = 100;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, true) == -EAGAIN);
    assert(calls == 1 && sleeps == 0);
    reset(&r); fail_count = 100; failure = -EIO;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, false) == -EIO);
    assert(calls == 1 && sleeps == 0);
    reset(&r); fail_count = 100; crash_on_sleep = true;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, false) == -EIO);
    assert(calls == 1 && sleeps == 1);
    reset(&r); running = false;
    assert(apple_rtkit_send_message(&r, 6, 0xff003, NULL, false) == -EINVAL);
    assert(calls == 0 && barriers == 0);
    puts("RTKit generated send function fault-injection tests passed");
}
'''
test = out / 'test_rtkit_retry.c'
test.write_text(prefix + function + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_retry.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror',
                '-Wno-unused-parameter', '-O2', str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
