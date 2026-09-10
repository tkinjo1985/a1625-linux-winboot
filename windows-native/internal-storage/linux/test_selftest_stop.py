"""Test synthetic module teardown callback using lifetime/order mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
source = (HERE / 'block_selftest.c').read_text()
start = source.index('static struct device *parent;')
end = source.index('static const struct kernel_param_ops', start)
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
struct device { int dummy; };
struct ans1_block { int dummy; };
struct kernel_param { int dummy; };
#define DEFINE_MUTEX(name) int name
#define IS_ERR_OR_NULL(p) (!(p) || (uintptr_t)(p) >= (uintptr_t)-4095)
#define pr_info(...) ((void)0)
static int held, destroyed, unregistered;
static void mutex_lock(int *m) { (void)m; assert(!held); held=1; }
static void mutex_unlock(int *m) { (void)m; assert(held); held=0; }
static int kstrtobool(const char *s, bool *b) {
    if (!strcmp(s,"true")) { *b=true; return 0; }
    if (!strcmp(s,"false")) { *b=false; return 0; }
    return -EINVAL;
}
static void ans1_block_destroy(struct ans1_block *b) {
    assert(held && b && !destroyed && !unregistered); destroyed++;
}
static void root_device_unregister(struct device *d) {
    assert(held && d && destroyed==1 && !unregistered); unregistered++;
}
'''
tests = r'''
int main(void) {
    struct ans1_block b; struct device d;
    assert(stop_selftest("true",NULL)==-ENODEV && !held);
    block=&b; parent=&d;
    assert(stop_selftest("invalid",NULL)==-EINVAL);
    assert(stop_selftest("false",NULL)==-EINVAL);
    assert(block==&b && parent==&d && !destroyed && !unregistered && !held);
    assert(stop_selftest("true",NULL)==0);
    assert(!block && !parent && destroyed==1 && unregistered==1 && !held);
    assert(stop_selftest("true",NULL)==-ENODEV);
    mutex_lock(&teardown_lock); remove_synthetic_disk(); mutex_unlock(&teardown_lock);
    assert(destroyed==1 && unregistered==1 && !held);
    puts("Synthetic module stop lifetime tests passed");
}
'''
test = out / 'test_selftest_stop.c'
test.write_text(prefix + source[start:end] + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_selftest_stop.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror',
    '-Wno-unused-parameter', '-O2', str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
