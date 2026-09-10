"""Run the generated HELLO handler with host transport/completion mocks."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
out = ROOT / 'artifacts/ans-rtkit-build'
source = (out / 'rtkit.c').read_text()
start = source.index('static void apple_rtkit_management_rx_hello(')
end = source.index('static void apple_rtkit_management_rx_iop_pwr_ack(', start)
internal = (out / 'rtkit-internal.h').read_text()
defines = '\n'.join(line for line in (source + internal).splitlines() if
    line.startswith('#define APPLE_RTKIT_MGMT_HELLO_') or
    line.startswith('#define APPLE_RTKIT_MGMT_EPMAP_') or
    line.startswith('#define APPLE_RTKIT_MIN_SUPPORTED_VERSION') or
    line.startswith('#define APPLE_RTKIT_MAX_SUPPORTED_VERSION') or
    line.startswith('#define APPLE_RTKIT_APP_ENDPOINT_START_'))
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t u8;
#define BIT_ULL(n) (1ULL << (n))
#define GENMASK_ULL(h,l) ((~0ULL << (l)) & (~0ULL >> (63-(h))))
#define FIELD_GET(m,v) (((v) & (m)) >> __builtin_ctzll(m))
#define FIELD_PREP(m,v) (((u64)(v) << __builtin_ctzll(m)) & (m))
#define min(a,b) ((a) < (b) ? (a) : (b))
#define dev_dbg(...) ((void)0)
#define dev_err(...) ((void)0)
#define dev_info(...) ((void)0)
#define dev_warn(...) ((void)0)
#define APPLE_RTKIT_MGMT_HELLO_REPLY 2
#define APPLE_RTKIT_MGMT_EPMAP_REPLY 8
enum { APPLE_RTKIT_EP_MGMT, APPLE_RTKIT_EP_CRASHLOG, APPLE_RTKIT_EP_SYSLOG,
       APPLE_RTKIT_EP_DEBUG, APPLE_RTKIT_EP_IOREPORT, APPLE_RTKIT_EP_OSLOG = 8 };
#define for_each_set_bit(i,p,n) for ((i)=0; (i)<(n); (i)++) if ((p)[(i)/32] & (1UL << ((i)%32)))
static void set_bit(int bit, unsigned long *p) { assert(bit < 256); p[bit/32] |= 1UL << (bit%32); }
struct ops { bool ans1_endpoint5; };
struct apple_rtkit { struct ops *ops; int boot_result, version, app_ep_start, epmap_completion; unsigned long endpoints[8]; };
static bool running=true;
static bool apple_rtkit_is_running(struct apple_rtkit *r) { (void)r; return running; }
static bool test_bit(int bit, unsigned long *p) { return !!(p[bit/32] & (1UL << (bit%32))); }
static int calls, send_error, starts, start_error;
static u64 last_reply;
static int apple_rtkit_management_send(struct apple_rtkit *r, int type, u64 msg) {
    (void)r; assert(type == 2 || type == 8); calls++; last_reply = msg; return send_error;
}
static int apple_rtkit_start_ep(struct apple_rtkit *r, int ep) {
    (void)r; assert(ep == 2); starts++; return start_error;
}
static void complete_all(int *c) { (*c)++; }
'''
tests = r'''
int main(void) {
    struct ops ops;
    struct apple_rtkit r;
    int version, opt;
    for (version = 10; version <= 12; version++) {
        for (opt = 0; opt <= 1; opt++) {
            ops.ans1_endpoint5 = opt;
            r = (struct apple_rtkit){.ops = &ops}; calls = 0;
            apple_rtkit_management_rx_hello(&r, ((u64)version << 16) | version);
            assert(r.version == version && !r.epmap_completion && calls == 1);
            assert(r.app_ep_start == (version == 10 ? (opt ? 5 : 6) : 32));
            assert(last_reply == (((u64)version << 16) | version));
        }
    }
    r = (struct apple_rtkit){.ops = &ops}; calls = 0; send_error = -ETIMEDOUT;
    apple_rtkit_management_rx_hello(&r, 0x000a000a);
    assert(r.boot_result == -ETIMEDOUT && r.epmap_completion == 1);
    send_error = 0;
    apple_rtkit_management_rx_hello(&r, 0x000c000c);
    assert(r.boot_result == -ETIMEDOUT && r.version == 10 && calls == 1);
    assert(r.epmap_completion == 1);
    const u64 invalid[] = {0x000a000b, 0x00090009, 0x000d000d};
    for (unsigned int i = 0; i < sizeof(invalid)/sizeof(invalid[0]); i++) {
        r = (struct apple_rtkit){.ops = &ops}; calls = 0;
        apple_rtkit_management_rx_hello(&r, invalid[i]);
        assert(r.boot_result == -EINVAL && r.epmap_completion == 1 && !calls);
    }
    r = (struct apple_rtkit){.ops = &ops}; calls = 0;
    apple_rtkit_management_rx_epmap(&r, 4);
    assert(r.boot_result == -EPROTO && r.epmap_completion == 1 && !calls);
    assert(!r.endpoints[0]);
    apple_rtkit_management_rx_hello(&r, 0x000a000a);
    assert(r.boot_result == -EPROTO && !calls);
    r = (struct apple_rtkit){.ops = &ops, .version = 10, .app_ep_start = 5};
    send_error = -EIO; calls = 0; starts = 0;
    apple_rtkit_management_rx_epmap(&r, 4);
    assert(r.boot_result == -EIO && r.epmap_completion == 1 && calls == 1 && !starts);
    send_error = 0;
    apple_rtkit_management_rx_epmap(&r, 4);
    assert(r.boot_result == -EIO && calls == 1 && !starts);
    r = (struct apple_rtkit){.ops = &ops, .version = 10, .app_ep_start = 5};
    start_error = -ETIMEDOUT;
    apple_rtkit_management_rx_epmap(&r, 4);
    assert(r.boot_result == -ETIMEDOUT && r.epmap_completion == 1 && starts == 1);
    r = (struct apple_rtkit){.ops = &ops, .version = 10, .app_ep_start = 5};
    start_error = 0;
    apple_rtkit_management_rx_epmap(&r, 4);
    assert(r.boot_result == 0 && r.epmap_completion == 1 && starts == 2);
    r = (struct apple_rtkit){.ops = &ops, .version = 10};
    ops.ans1_endpoint5=true;
    assert(!apple_rtkit_ans1_endpoint(&r));
    set_bit(5,r.endpoints); assert(apple_rtkit_ans1_endpoint(&r)==5);
    set_bit(6,r.endpoints); assert(apple_rtkit_ans1_endpoint(&r)==6);
    ops.ans1_endpoint5=false; assert(!apple_rtkit_ans1_endpoint(&r));
    ops.ans1_endpoint5=true; running=false; assert(!apple_rtkit_ans1_endpoint(&r));
    running=true; r.boot_result=-EIO; assert(!apple_rtkit_ans1_endpoint(&r));
    r.boot_result=0; r.version=11; assert(!apple_rtkit_ans1_endpoint(&r));
    set_bit(32,r.endpoints); assert(apple_rtkit_ans1_endpoint(&r)==32);
    r.version=12; assert(apple_rtkit_ans1_endpoint(&r)==32);
    r.version=13; assert(!apple_rtkit_ans1_endpoint(&r));
    puts("RTKit generated HELLO, endpoint-map and ANS selection tests passed");
}
'''
test = out / 'test_rtkit_hello.c'
selection = source[source.index('u8 apple_rtkit_ans1_endpoint('):source.index('EXPORT_SYMBOL_GPL(apple_rtkit_ans1_endpoint);')]
test.write_text(prefix + defines + '\n' + source[start:end] + selection + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_hello.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
