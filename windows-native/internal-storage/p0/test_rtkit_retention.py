"""Compile actual RTKit teardown bodies and reject all P0 AKF release paths."""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/rtkit.c').read_text()
def function(signature):
    start = source.index(signature + '\n{')
    return source[start:source.index('\n}', start) + 2]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef uint64_t u64;
struct rtkit_buffer { void *bfr; u64 dva; size_t sz; };
typedef struct rtkit_dev {
 void *iop_ops, *sart, *dart, *dart_iovad, *name;
 u64 dva_base;
 struct rtkit_buffer syslog_bfr, crashlog_bfr, ioreport_bfr;
} rtkit_dev_t;
static int token, releases;
static void *rtkit_akf_iop_ops=&token;
#define ANS1_P0 1
#define IOVA_MASK ((1ULL<<36)-1)
/* Firmware uses LP64; Windows host uses LLP64. Do not format its u64 logs. */
static void mock_log(const char *fmt, ...) {(void)fmt;}
#define rtkit_printf(...) mock_log(__VA_ARGS__)
static bool is_heap(void *p) { return p!=NULL; }
static bool sart_remove_allowed_region(void *s,void *p,size_t n) {
 (void)s;(void)p;(void)n; releases++;return true;
}
static void dart_unmap(void *d,u64 a,size_t n) {(void)d;(void)a;(void)n;releases++;}
static void iova_free(void *d,u64 a,size_t n) {(void)d;(void)a;(void)n;releases++;}
static void mock_free(void *p) {(void)p;releases++;}
#define free mock_free
bool rtkit_free_buffer(rtkit_dev_t *, struct rtkit_buffer *);
'''
tests = r'''
int main(void) {
 rtkit_dev_t r={0}; r.iop_ops=rtkit_akf_iop_ops;
 r.syslog_bfr=(struct rtkit_buffer){&token,0x1000,16384};
 r.crashlog_bfr=r.ioreport_bfr=r.syslog_bfr;
 for(int mode=0;mode<3;mode++) {
  r.dart=mode==1?&token:NULL; r.sart=mode==2?&token:NULL;
  assert(!rtkit_unmap(&r,0x1000,16384));
  assert(!rtkit_free_buffer(&r,&r.syslog_bfr));
  rtkit_free(&r);
  assert(!releases && r.syslog_bfr.bfr==&token);
  assert(r.crashlog_bfr.bfr==&token && r.ioreport_bfr.bfr==&token);
 }
 puts("P0 actual RTKit free/unmap paths retain all AKF shared regions");
}
'''
out = ROOT / 'artifacts/ans-p0-tests'
out.mkdir(exist_ok=True)
c = out / 'rtkit-retention.c'
c.write_text(prefix + '\n'.join(function(s) for s in (
    'bool rtkit_unmap(rtkit_dev_t *rtk, u64 dva, size_t sz)',
    'bool rtkit_free_buffer(rtkit_dev_t *rtk, struct rtkit_buffer *bfr)',
    'void rtkit_free(rtkit_dev_t *rtk)')) + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'rtkit-retention.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
