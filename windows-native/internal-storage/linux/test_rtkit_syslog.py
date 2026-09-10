"""Check actual generated syslog receive code against bounded backing storage."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-rtkit-build'
source = (out / 'rtkit.c').read_text()
start = source.index('static void apple_rtkit_syslog_rx_init(')
end = source.index('static void apple_rtkit_syslog_rx(', start)
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
typedef uint8_t u8;
typedef uint64_t u64;
#define APPLE_RTKIT_EP_SYSLOG 2
#define dev_warn(...) ((void)0)
#define dev_info(...) ((void)0)
#define dev_dbg(...) ((void)0)
#define GFP_KERNEL 0
#define APPLE_RTKIT_SYSLOG_N_ENTRIES 0xffULL
#define APPLE_RTKIT_SYSLOG_MSG_SIZE 0xff000000ULL
#define FIELD_GET(mask, val) (((val) & (mask)) / ((mask) & -(mask)))
static unsigned int allocations;
static bool oom;
static void *kzalloc(size_t size,int flags) {
    assert(!flags && size); if(oom) return NULL;
    void *p=calloc(1,size); assert(p); allocations++; return p;
}
static void kfree(void *p) { if(p) { assert(allocations); allocations--; free(p); } }
struct buffer { size_t size; void *buffer, *iomem; };
struct apple_rtkit {
    size_t syslog_n_entries, syslog_msg_size;
    char *syslog_msg_buffer;
    struct buffer syslog_buffer;
};
static unsigned int copies, acks;
static u64 last_ack;
static void apple_rtkit_memcpy(struct apple_rtkit *r, void *dst,
    struct buffer *b, size_t offset, size_t size) {
    (void)r; assert(offset <= b->size && size <= b->size-offset);
    assert(b->buffer); memcpy(dst,(char *)b->buffer+offset,size); copies++;
}
static int apple_rtkit_send_message(struct apple_rtkit *r,int ep,u64 msg,void *c,bool atomic) {
    (void)r; assert(ep==2 && !c && !atomic); acks++; last_ack=msg; return 0;
}
'''
tests = r'''
int main(void) {
    char backing[128], message[32];
    memset(backing,'x',sizeof(backing));
    struct apple_rtkit r={2,32,message,{128,backing,NULL}};
    for(unsigned int idx=0;idx<4;idx++) {
        copies=acks=0; u64 msg=(5ULL<<52)|idx;
        apple_rtkit_syslog_rx_log(&r,msg);
        assert(copies==(idx<2?2U:0U) && acks==1 && last_ack==msg);
    }
    r.syslog_buffer.size=127; copies=acks=0;
    apple_rtkit_syslog_rx_log(&r,1); assert(!copies && acks==1);
    r.syslog_buffer.size=63; copies=acks=0;
    apple_rtkit_syslog_rx_log(&r,0); assert(!copies && acks==1);
    r.syslog_buffer.size=128; r.syslog_msg_size=0; copies=acks=0;
    apple_rtkit_syslog_rx_log(&r,0); assert(!copies && acks==1);
    r.syslog_msg_size=32; r.syslog_n_entries=0; copies=acks=0;
    apple_rtkit_syslog_rx_log(&r,0); assert(!copies && acks==1);
    r.syslog_n_entries=2; r.syslog_msg_buffer=NULL; copies=acks=0;
    apple_rtkit_syslog_rx_log(&r,0); assert(!copies && acks==1);
    r.syslog_n_entries=0; r.syslog_msg_size=0;
    for(unsigned int i=1;i<=3;i++) {
        apple_rtkit_syslog_rx_init(&r,((u64)(i*16)<<24)|i);
        assert(allocations==1 && r.syslog_n_entries==i && r.syslog_msg_size==i*16);
    }
    oom=true; apple_rtkit_syslog_rx_init(&r,(32ULL<<24)|2);
    assert(!allocations && !r.syslog_msg_buffer && !r.syslog_n_entries && !r.syslog_msg_size);
    oom=false; apple_rtkit_syslog_rx_init(&r,(32ULL<<24)|2);
    apple_rtkit_syslog_rx_init(&r,2);
    assert(!allocations && !r.syslog_msg_buffer && !r.syslog_n_entries && !r.syslog_msg_size);
    apple_rtkit_syslog_rx_init(&r,(32ULL<<24)|2);
    apple_rtkit_syslog_rx_init(&r,32ULL<<24);
    assert(!allocations && !r.syslog_msg_buffer && !r.syslog_n_entries && !r.syslog_msg_size);
    puts("Syslog bounds, repeated initialization, invalid metadata and allocation failure passed");
}
'''
test = out / 'test_rtkit_syslog.c'
test.write_text(prefix + source[start:end] + tests)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_rtkit_syslog.exe'
subprocess.run([str(gcc), '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-O2',
                str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
