"""Exercise the compiled P0 outbound policy with synthetic protocol traces."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
src = ROOT / 'third_party/HoolockLinux-m1n1-p0/src'
program = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint64_t u64; typedef uint32_t u32; typedef uint8_t u8;
#include "rtkit_p0.h"
static void denied(struct rtkit_p0_policy *p,u8 ep,u64 msg) {
 struct rtkit_p0_policy before=*p;
 assert(!rtkit_p0_tx(p,ep,msg,0,0));
 assert(!memcmp(p,&before,sizeof(*p)));
}
int main(void) {
 for(int version=10;version<=12;version++) {
  struct rtkit_p0_policy p={0}; p.cmd=0x800100000ULL;
  denied(&p,0,P0_TYPE(2)|0xa000a);
  assert(rtkit_p0_tx(&p,0,P0_TYPE(6)|0x220,0,0));
  denied(&p,0,P0_TYPE(6)|0x220);
  rtkit_p0_observe(&p,0,P0_TYPE(1)|((u64)version<<16)|10);
  denied(&p,0,P0_TYPE(2)|0xd000d);
  assert(rtkit_p0_tx(&p,0,P0_TYPE(2)|((u64)version<<16)|version,0,0));
  u32 bits=(1U<<1)|(1U<<2)|(1U<<4);
  if(version==10)bits|=(1U<<5)|(1U<<6);
  rtkit_p0_observe(&p,0,P0_TYPE(8)|bits);
  denied(&p,0,P0_TYPE(8)|0x100);
  assert(rtkit_p0_tx(&p,0,P0_TYPE(8)|(version==10?0:1),0,0));
  if(version>10) {
   rtkit_p0_observe(&p,0,P0_TYPE(8)|(1ULL<<51)|(1ULL<<32)|1);
   assert(rtkit_p0_tx(&p,0,P0_TYPE(8)|(1ULL<<51)|(1ULL<<32),0,0));
  }
  u8 app=version==10?6:32;
  denied(&p,0,P0_TYPE(5)|(7ULL<<32)|2);
  denied(&p,0,P0_TYPE(5)|(5ULL<<32)|2);
  for(int ep=1;ep<=4;ep++) {
   if(ep==3)continue;
   assert(rtkit_p0_tx(&p,0,P0_TYPE(5)|((u64)ep<<32)|2,0,0));
   denied(&p,0,P0_TYPE(5)|((u64)ep<<32)|2);
  }
  assert(rtkit_p0_tx(&p,0,P0_TYPE(5)|((u64)app<<32)|2,0,0));
  denied(&p,app,(p.cmd<<16)|0x20);
  rtkit_p0_observe(&p,app,0xafe2);
  denied(&p,app,(p.cmd<<16)|0x20);
  rtkit_p0_observe(&p,0,P0_TYPE(7)|0x20);
  assert(rtkit_p0_tx(&p,0,P0_TYPE(0xb)|0x20,0,0));
  denied(&p,app,((p.cmd+0x1000)<<16)|0x20);
  assert(rtkit_p0_tx(&p,app,(p.cmd<<16)|0x20,0,0));
  denied(&p,app,0x2000001);
  rtkit_p0_observe(&p,app,0xafd2);
  assert(rtkit_p0_tx(&p,app,0x2000001,0,0));
  denied(&p,app,0x2000011);
  for(int command=0;command<5;command++) {
   assert(rtkit_p0_tx(&p,app,0xff003,0,0));
   denied(&p,app,0xff003);
   rtkit_p0_observe(&p,app,2);
  }
  denied(&p,app,0xff003);
  const u64 selectors[]={0x480,0x7080,0x7180,0x8580,0xb080};
  for(unsigned i=0;i<5;i++)denied(&p,app,selectors[i]);
  for(int ep=1;ep<=4;ep++) {
   if(ep==3)continue;
   u64 req=P0_TYPE(1)|(1ULL<<44), addr=0x800200000ULL;
   rtkit_p0_observe(&p,ep,req);
   assert(!rtkit_p0_tx(&p,ep,req|addr,addr,4096));
   assert(rtkit_p0_tx(&p,ep,req|addr,addr,16384));
   assert(!rtkit_p0_tx(&p,ep,req|addr,addr,16384));
  }
  rtkit_p0_observe(&p,2,P0_TYPE(5)|3);
  assert(rtkit_p0_tx(&p,2,P0_TYPE(5)|3,0,0));
  denied(&p,2,P0_TYPE(5)|3);
  rtkit_p0_observe(&p,4,P0_TYPE(8));
  assert(rtkit_p0_tx(&p,4,P0_TYPE(8),0,0));
  rtkit_p0_observe(&p,4,P0_TYPE(8)|0x480);
  denied(&p,4,P0_TYPE(8)|0x480);
  denied(&p,0,P0_TYPE(6)|1);
  assert(rtkit_p0_tx(&p,0,P0_TYPE(0xb)|0x10,0,0));
  denied(&p,app,0xff003);
  rtkit_p0_observe(&p,0,P0_TYPE(0xb)|(version==10?0:0x10));
  assert(rtkit_p0_tx(&p,0,P0_TYPE(6)|1,0,0));
  denied(&p,0,P0_TYPE(6)|1);
 }
 puts("P0 v10-v12 outbound traces, registration bounds, one inflight, ACK and stop policy passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'
out.mkdir(exist_ok=True)
c = out / 'rtkit-policy.c'; c.write_text(program)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'rtkit-policy.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(src), str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
