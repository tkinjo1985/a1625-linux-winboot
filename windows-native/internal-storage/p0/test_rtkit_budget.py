"""Exercise actual AKF transport wrappers, including the boot timed-RX path."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/rtkit.c').read_text()
def function(name):
    start = source.index('static bool ' + name + '(')
    return source[start:source.index('\n}', start) + 2]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
typedef uint64_t u64; typedef uint32_t u32; typedef int akf_dev_t;
struct rtkit_message { unsigned char ep; u64 msg; };
struct rtkit_dev { void *mbox; bool crashed; unsigned p0_tx_count,p0_rx_count; };
#define ANS1_P0 1
#define RTKIT_AKF_MSG_EP 0xff00000000000000ULL
#define RTKIT_AKF_MSG_MSG 0x00ffffffffffffffULL
#define FIELD_PREP(m,v) (((u64)(v)<<__builtin_ctzll(m))&(m))
#define FIELD_GET(m,v) (((v)&(m))>>__builtin_ctzll(m))
static unsigned sends, reads, ticks;
static bool send_ok=true, available=true;
static void mock_log(const char *s,...) {(void)s;}
#define printf mock_log
static bool akf_send(akf_dev_t *a,u64 v) {(void)a;(void)v;sends++;return send_ok;}
static bool akf_recv(akf_dev_t *a,u64 *v) {
 (void)a;reads++;*v=0x0600000000000002ULL;return available;
}
static u64 timeout_calculate(u32 d) { return ticks+d; }
static bool timeout_expired(u64 d) { return ++ticks>d; }
'''
tests = r'''
int main(void) {
 struct rtkit_dev r={0}; struct rtkit_message m={6,2};
 for(unsigned i=0;i<128;i++) assert(rtkit_akf_send(&r,&m));
 assert(sends==128 && r.p0_tx_count==128);
 assert(!rtkit_akf_send(&r,&m) && r.crashed && sends==128);
 assert(!rtkit_akf_send(&r,&m) && sends==128);
 r=(struct rtkit_dev){0};send_ok=false;sends=0;
 assert(!rtkit_akf_send(&r,&m) && r.crashed && sends==1);
 assert(!rtkit_akf_send(&r,&m) && sends==1);
 r=(struct rtkit_dev){0};reads=0;
 for(unsigned i=0;i<511;i++) assert(rtkit_akf_recv(&r,&m));
 assert(rtkit_akf_recv_timeout(&r,&m,5));
 assert(r.p0_rx_count==512 && reads==512);
 assert(!rtkit_akf_recv_timeout(&r,&m,5) && r.crashed && reads==512);
 assert(!rtkit_akf_recv(&r,&m) && reads==512);
 r=(struct rtkit_dev){0};available=false;reads=ticks=0;
 assert(!rtkit_akf_recv_timeout(&r,&m,5));
 assert(!r.p0_rx_count && !r.crashed && reads<=5 && ticks<=6);
 puts("P0 TX/RX cumulative bounds, timed RX sharing and first-send-failure latch passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'
out.mkdir(exist_ok=True)
c = out / 'rtkit-budget.c'
c.write_text(prefix + '\n'.join(function(n) for n in (
    'rtkit_akf_send', 'rtkit_akf_recv', 'rtkit_akf_recv_timeout')) + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'rtkit-budget.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
