"""Fault injection for the generated shared-buffer function, without DMA."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
out = ROOT / 'artifacts/ans-rtkit-build'
source = (out / 'rtkit.c').read_text()
start = source.index('static int apple_rtkit_common_rx_get_buffer(')
end = source.index('static void apple_rtkit_free_buffer(', start)
defines = '\n'.join(line for line in source.splitlines() if
    line.startswith('#define APPLE_RTKIT_BUFFER_REQUEST') or
    line.startswith('#define APPLE_RTKIT_OSLOG_') or
    line.startswith('#define APPLE_RTKIT_SYSLOG_TYPE'))
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
typedef uint64_t u64;
typedef uint8_t u8;
#define GENMASK_ULL(h,l) ((~0ULL << (l)) & (~0ULL >> (63-(h))))
#define FIELD_GET(m,v) (((v) & (m)) >> __builtin_ctzll(m))
#define FIELD_PREP(m,v) (((u64)(v) << __builtin_ctzll(m)) & (m))
#define FIELD_FIT(m,v) ((u64)(v) <= ((m) >> __builtin_ctzll(m)))
#define APPLE_RTKIT_EP_OSLOG 8
#define GFP_KERNEL 0
#define dev_err(...) ((void)0)
#define dev_dbg(...) ((void)0)
struct apple_rtkit_shmem { size_t size; u64 iova; void *buffer, *iomem; bool is_mapped; };
struct ops { int (*shmem_setup)(void *, struct apple_rtkit_shmem *); };
struct apple_rtkit { struct ops *ops; void *cookie, *dev; };
static char allocation[4096];
static int allocations, sends, send_error;
static bool alloc_fail;
static u64 allocated_dma = 0x800000000ULL;
static size_t setup_size = 4096;
static int custom_setup(void *cookie, struct apple_rtkit_shmem *b) {
    (void)cookie; b->buffer=allocation; b->iova=allocated_dma;
    b->size=setup_size; return 0;
}
static void *dma_alloc_coherent(void *dev, size_t size, u64 *dma, int flags) {
    (void)dev; (void)flags; assert(size == 4096); allocations++;
    if (alloc_fail) return NULL;
    *dma = allocated_dma; return allocation;
}
static int apple_rtkit_send_message(struct apple_rtkit *rtk, u8 ep, u64 msg, void *c, bool a) {
    (void)rtk; (void)c; (void)a;
    assert((ep == 2 && msg == 0x0010100800000000ULL) ||
           (ep == 8 && msg == 0x0101000000800000ULL));
    sends++; return send_error;
}
'''
tests = r'''
int main(void) {
    struct ops ops = {0};
    struct apple_rtkit r = {.ops = &ops};
    struct apple_rtkit_shmem b = {0}, saved;
    const u64 request = 1ULL << 44;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, 0) == -EINVAL);
    assert(allocations == 0 && sends == 0);
    alloc_fail = true;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == -ENOMEM);
    assert(!b.size && !b.buffer && !b.iova && sends == 0);
    alloc_fail = false; send_error = -ETIMEDOUT;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == -ETIMEDOUT);
    assert(b.size == 4096 && b.buffer == allocation && b.iova == 0x800000000ULL);
    saved = b;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == -EBUSY);
    assert(!memcmp(&saved, &b, sizeof(b)) && allocations == 2 && sends == 1);
    b = (struct apple_rtkit_shmem){0}; /* Independent simulated allocation. */
    send_error = 0;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == 0);
    assert(b.buffer == allocation && sends == 2);
    b = (struct apple_rtkit_shmem){0}; allocated_dma = 1ULL << 44;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == -ERANGE);
    assert(b.buffer == allocation && b.iova == allocated_dma && sends == 2);
    const u64 oslog_request = 0x0001000000000000ULL;
    b = (struct apple_rtkit_shmem){0}; allocated_dma = 0x800000000ULL;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 8, oslog_request) == 0);
    assert(sends == 3 && b.size == 4096 && b.iova == allocated_dma);
    const u64 bad_dma[] = {0x800000001ULL, 1ULL << 48};
    for (unsigned int i=0; i<2; i++) {
        b = (struct apple_rtkit_shmem){0}; allocated_dma = bad_dma[i];
        assert(apple_rtkit_common_rx_get_buffer(&r, &b, 8, oslog_request) == -ERANGE);
        assert(sends == 3 && b.iova == allocated_dma && b.buffer == allocation);
    }
    ops.shmem_setup = custom_setup; allocated_dma = 0x800000000ULL;
    b = (struct apple_rtkit_shmem){0}; setup_size = 1U << 20;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 8, oslog_request) == -ERANGE);
    assert(sends == 3 && b.size == setup_size && b.buffer == allocation);
    b = (struct apple_rtkit_shmem){0}; setup_size = 4097;
    assert(apple_rtkit_common_rx_get_buffer(&r, &b, 2, request) == -ERANGE);
    assert(sends == 3 && b.size == setup_size && b.buffer == allocation);
    puts("RTKit generated shared-buffer fault-injection tests passed");
}
'''
test = out / 'test_rtkit_buffer.c'
test.write_text(prefix + defines + '\n' + source[start:end] + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_buffer.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
