"""Fault-inject the actual P0 unwind and sleep function bodies on the host."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
src = ROOT / 'third_party/HoolockLinux-m1n1-p0/src'
def function(text, signature):
    start = text.index(signature + '\n{')
    end = text.index('\n}', start) + 2
    return text[start:end]
unwind = function((src / 'ans1.c').read_text(), 'static void ans1_unwind(void)')
sleep = function((src / 'rtkit.c').read_text(), 'bool rtkit_sleep(rtkit_dev_t *rtk)')
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
struct rtkit_dev;
struct ops { void (*cpu_stop)(struct rtkit_dev *); };
typedef struct rtkit_dev { struct ops *iop_ops; } rtkit_dev_t;
static int switches, stops, rfree, cfree, afree, disables;
static bool sleep_ok, stuck;
static bool ans1_dead, ans1_initialized, ans1_ready, ans1_powered;
static void *ans1_akf, *cmd;
static rtkit_dev_t *ans1_rtkit;
#define RTKIT_POWER_SLEEP 1
static bool rtkit_switch_power_state(rtkit_dev_t *r,int p) {
 assert(r && p==1); switches++; return sleep_ok;
}
static void cpu_stop(rtkit_dev_t *r) { assert(r); stops++; }
static void akf_cpu_stop(void *a) { assert(a); stops++; }
static bool akf_cpu_running(void *a) { assert(a); return stuck; }
static void rtkit_free(void *r) { assert(r && !stuck); rfree++; }
static void mock_free(void *p) { if(p) { assert(!stuck); cfree++; } }
#define free mock_free
static void akf_free(void *a) { assert(a && !stuck); afree++; }
static int pmgr_adt_power_disable(const char *p) { assert(p && !stuck); disables++; return 0; }
'''
tests = r'''
int main(void) {
 struct ops o={cpu_stop}; rtkit_dev_t r={&o};
 for(int ok=0;ok<2;ok++) {
  sleep_ok=ok; switches=stops=0;
  assert(rtkit_sleep(&r)==(bool)ok);
  assert(switches==1 && stops==ok);
 }
 for(int failure=0;failure<2;failure++) {
  for(int sleeping=0;sleeping<2;sleeping++) {
   stuck=failure; sleep_ok=sleeping;
   switches=stops=rfree=cfree=afree=disables=0;
   ans1_akf=&o; cmd=&o; ans1_rtkit=&r;
   ans1_powered=ans1_initialized=ans1_ready=true; ans1_dead=false;
   ans1_unwind();
   assert(ans1_dead && !ans1_initialized && !ans1_ready);
   assert(switches==1 && stops==sleeping+1);
   if(stuck) {
    assert(!rfree && !cfree && !afree && !disables);
    assert(cmd && ans1_akf && ans1_rtkit && ans1_powered);
   } else {
    assert(rfree==1 && cfree==1 && afree==1 && disables==1);
    assert(!cmd && !ans1_akf && !ans1_rtkit && !ans1_powered);
    ans1_unwind();
    assert(rfree==1 && cfree==1 && afree==1 && disables==1);
   }
  }
 }
 /* Partial power enable / AKF allocation failure: CPU state is unknown. */
 ans1_akf=cmd=NULL; ans1_rtkit=NULL; ans1_powered=true;
 switches=stops=rfree=cfree=afree=disables=0;
 ans1_unwind();
 assert(ans1_dead && ans1_powered);
 assert(!switches && !stops && !rfree && !cfree && !afree && !disables);
 puts("P0 bool sleep and stop-readback retention/unwind tests passed");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'
out.mkdir(exist_ok=True)
c = out / 'unwind.c'; c.write_text(prefix + sleep + '\n' + unwind + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'unwind.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
