"""Compile actual session/proxy predicates; exhaust opcodes and transfer bounds."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
src = ROOT / 'third_party/HoolockLinux-m1n1-p0/src'
def function(path, signature):
    s = (src / path).read_text()
    start = s.index(signature + '\n{')
    return s[start:s.index('\n}', start) + 2]
header = (src / 'proxy.h').read_text()
enum = header[header.index('typedef enum {'):header.index('} ProxyOp;') + len('} ProxyOp;')]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
typedef uint64_t u64;
#define SZ_4K 4096
static bool ans1_p0_session,ans1_attempted,ans1_dead;
static void *ans1_p0_read_buffer;
static unsigned allocations, shutdowns;
#define T7000 0x7000
static unsigned chip_id=T7000,board_id=0x34;
static bool akf_p0_reserve_firmware(void) {return true;}
static void *memalign(size_t a,size_t s) {assert(a==4096 && s==4096);allocations++;return (void *)0x1000;}
static void ans1_shutdown(void) {shutdowns++;}
'''
tests = r'''
int main(void) {
 assert(!ans1_p0_session_locked());
 assert(p0_proxy_allowed(P_FREE));
 assert(ans1_p0_prepare_buffer()==(void *)0x1000);
 assert(ans1_p0_session_locked() && allocations==1);
 for(u64 op=0;op<65536;op++) {
  bool allowed=op==P_NOP || op==P_ANS1_INIT || op==P_ANS1_READ ||
               op==P_ANS1_RESERVED || op==P_ANS1_SHUTDOWN;
  assert(p0_proxy_allowed(op)==allowed);
 }
 assert(!p0_proxy_allowed(UINT64_MAX));
 assert(!ans1_p0_prepare_buffer() && allocations==1);
 assert(ans1_p0_read_buffer==(void *)0x1000);
 assert(ans1_p0_memread_allowed(0x1000,4096));
 assert(ans1_p0_memread_allowed(0x1000,128));
 assert(ans1_p0_memread_allowed(0x1fff,1));
 assert(!ans1_p0_memread_allowed(0xfff,1));
 assert(!ans1_p0_memread_allowed(0x2000,1));
 assert(!ans1_p0_memread_allowed(0x1000,4097));
 assert(!ans1_p0_memread_allowed(UINT64_MAX,1));
 assert(!ans1_p0_memread_allowed(0x1000,UINT64_MAX));
 ans1_p0_abort();
 assert(ans1_dead && ans1_attempted && shutdowns==1);
 assert(ans1_p0_session_locked() && !p0_proxy_allowed(P_REBOOT));
 assert(ans1_p0_memread_allowed(0x1000,4096));
 puts("P0 sealed proxy opcodes, immutable buffer, transfer bounds and abort latch passed");
}
'''
parts = [function('ans1.c', sig) for sig in (
    'void *ans1_p0_prepare_buffer(void)', 'bool ans1_p0_session_locked(void)',
    'bool ans1_p0_memread_allowed(u64 addr, u64 size)', 'void ans1_p0_abort(void)')]
parts.append(function('proxy.c', 'static bool p0_proxy_allowed(u64 opcode)'))
out = ROOT / 'artifacts/ans-p0-tests'; out.mkdir(exist_ok=True)
c = out / 'session-lock.c'; c.write_text(prefix + enum + '\n'.join(parts) + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'session-lock.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
