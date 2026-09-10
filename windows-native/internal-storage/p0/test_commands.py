"""Exhaustive opcode gate test using the actual modified command sender."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/ans1.c').read_text()
def function(signature):
    start = source.index(signature + '\n{')
    return source[start:source.index('\n}', start) + 2]
prefix = '\n'.join(x for x in source[:source.index('static bool ans1_epmap_cb')].splitlines()
                   if not x.startswith('#include'))
prefix = prefix.replace('static void ans1_unwind(void);', '')
mocks = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int akf_dev_t; typedef int rtkit_dev_t;
#define PACKED __attribute__((packed))
#define ANS1_P0 1
#define BIT(n) (1ULL<<(n))
#define GENMASK(h,l) ((~0ULL >> (63-(h))) & (~0ULL<<(l)))
#define FIELD_PREP(m,v) (((u64)(v)<<__builtin_ctzll(m))&(m))
#define static_assert _Static_assert
struct rtkit_message { u64 msg; u8 ep; };
static int sends, unwinds; static bool send_ok=true, wait_ok=true;
static void dma_wmb(void) {} static void dma_rmb(void) {}
static bool rtkit_send(rtkit_dev_t *r,struct rtkit_message *m) {
 (void)r; assert(m->msg==0xff003); sends++; return send_ok;
}
static bool ans1_wait_for_tag(rtkit_dev_t *r,u8 tag) { (void)r; assert(!tag); return wait_ok; }
static void ans1_unwind(void) { unwinds++; }
'''
tests = r'''
int main(void) {
 unsigned char storage[128]; cmd=(void *)storage;
 for(int op=0;op<256;op++) {
  memset(storage,0,sizeof(storage)); cmd->op=op;
  if(op==0x10) { cmd->length=1; cmd->flags=8; }
  sends=0; ans1_dead=false;
  assert(ans1_exec_command()==(op==0 || op==0x10));
  assert(sends==(op==0 || op==0x10));
 }
 for(int failure=0;failure<4;failure++) {
  memset(storage,0,sizeof(storage)); cmd->op=0x10; cmd->length=1; cmd->flags=8;
  if(failure==0) cmd->tag=1;
  if(failure==1) cmd->length=2;
  if(failure==2) cmd->slba=2;
  if(failure==3) cmd->flags=0;
  sends=0; ans1_dead=false;
  assert(!ans1_exec_command() && !sends && ans1_dead);
 }
 for(int failure=0;failure<2;failure++) {
  memset(storage,0,sizeof(storage)); sends=0; ans1_dead=false;
  send_ok=failure!=0; wait_ok=failure!=1;
  assert(!ans1_exec_command() && ans1_dead);
  assert(!ans1_exec_command() && sends==1);
 }
 send_ok=wait_ok=true; ans1_initialized=true;
 for(int failure=0;failure<4;failure++) {
  ans1_dead=false; sends=unwinds=0;
  u64 address=failure==0?0:failure==1?0x1001:failure==2?(1ULL<<44):0x1000;
  assert(!ans1_read_main_storage(failure==3?2:0,(void *)(uintptr_t)address));
  assert(ans1_dead && !sends && unwinds==1);
 }
 /* Silence unused globals copied from the production declaration section. */
 (void)ans1_akf; (void)ans1_attempted; (void)ans1_powered; (void)ans1_ready; (void)ans1_identify_result;
 puts("P0 all 256 opcodes, request bounds and DEAD latch passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'; out.mkdir(exist_ok=True)
c = out / 'commands.c'
c.write_text(mocks + prefix + '\n' + function('static bool ans1_exec_command(void)') + '\n' +
             function('bool ans1_read_main_storage(u64 lba, void *buffer)') + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'commands.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
