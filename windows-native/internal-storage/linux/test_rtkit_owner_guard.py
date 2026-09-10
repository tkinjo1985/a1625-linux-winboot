"""Exercise the generated RTKit init preflight before any allocation or I/O."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-rtkit-build'
source = (out / 'rtkit.c').read_text()
start = source.index('struct apple_rtkit *apple_rtkit_init(')
start = source.index('\tif (!ops', start)
end = source.index('\trtk = kzalloc_obj', start)
guard = source[start:end]
test = out / 'test_rtkit_owner_guard.c'
test.write_text(r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#define ERR_PTR(e) ((void *)(intptr_t)(e))
struct apple_rtkit_ops { bool ans1_endpoint5; void (*shmem_setup)(void); void (*shmem_destroy)(void); };
static int allocations_reached;
static void callback(void) {}
static void *preflight(struct apple_rtkit_ops *ops) {
''' + guard + r'''
    allocations_reached++; return NULL;
}
int main(void) {
    assert(preflight(NULL)==ERR_PTR(-EINVAL) && !allocations_reached);
    for(int ans=0;ans<2;ans++) for(int mask=0;mask<4;mask++) {
        struct apple_rtkit_ops ops={ans,mask&1?callback:NULL,mask&2?callback:NULL};
        allocations_reached=0;
        bool allowed=!ans || mask==3;
        assert(preflight(&ops)==(allowed?NULL:ERR_PTR(-EINVAL)));
        assert(allocations_reached==(int)allowed);
    }
    puts("ANS1 ownership callbacks required before allocation; default mode preserved");
}
''')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_owner_guard.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
