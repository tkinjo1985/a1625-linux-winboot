"""Run the actual validator with Windows SHA-256 and the pinned local image.

The crypto backend is BCrypt rather than the kernel's SHA library; no hardware
access, allocation of device RAM, or firmware transfer occurs.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
out = ROOT / 'artifacts/ans-offline-tests'
report = out / 'firmware-validation.json'
report.write_text(json.dumps({'status': 'running', 'hardware_validation': False}), encoding='utf-8')
source = (HERE / 'ans1_firmware.c').read_text()
for line in ('#include <crypto/sha2.h>\n', '#include <linux/errno.h>\n',
             '#include <linux/string.h>\n', '#include <linux/slab.h>\n',
             '#include <linux/vmalloc.h>\n'):
    if source.count(line) != 1:
        raise ValueError('unexpected validator include')
    source = source.replace(line, '')
prefix = r'''
#include <windows.h>
#include <bcrypt.h>
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "ans1_firmware.h"
#define SHA256_DIGEST_SIZE 32
#define GFP_KERNEL 0
static int allocation, fail_allocation, outstanding;
static void *kmemdup(const void *p, size_t n, int flags) {
    (void)flags; if (++allocation==fail_allocation) return NULL;
    void *r=malloc(n); assert(r); memcpy(r,p,n); outstanding++; return r;
}
static void *vzalloc(size_t n) {
    if (++allocation==fail_allocation) return NULL;
    void *r=calloc(1,n); assert(r); outstanding++; return r;
}
static void kfree(void *p) { if(p) { outstanding--; free(p); } }
static void vfree(void *p) { kfree(p); }
static unsigned hash_calls;
static void sha256(const u8 *data, size_t len, u8 *digest) {
    BCRYPT_ALG_HANDLE alg;
    hash_calls++;
    assert(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,NULL,0)>=0);
    assert(BCryptHash(alg,NULL,0,(PUCHAR)data,(ULONG)len,digest,32)>=0);
    assert(BCryptCloseAlgorithmProvider(alg,0)>=0);
}
'''
tests = r'''
static u8 image[0x60240];
static u8 copy[0x60240];
int main(int argc, char **argv) {
    assert(argc==2);
    FILE *f=fopen(argv[1],"rb"); assert(f);
    assert(fread(image,1,sizeof(image),f)==sizeof(image));
    assert(fgetc(f)==EOF && !ferror(f)); fclose(f);
    struct ans1_firmware_plan plan, sentinel;
    memset(&sentinel,0xa5,sizeof(sentinel));
    assert(ans1_firmware_validate(image,sizeof(image),0x87f600000ULL,0xa00000,&plan)==0);
    assert(hash_calls==1 && plan.heap.phys==0x87f6f1000ULL && plan.heap.size==0x90f000);
    const u32 offsets[]={0,0x40000,0x48070,0x480cd,0x6023f};
    for (u32 i=0;i<sizeof(offsets)/sizeof(offsets[0]);i++) {
        image[offsets[i]]^=1; plan=sentinel;
        assert(ans1_firmware_validate(image,sizeof(image),0x87f600000ULL,0xa00000,&plan)==-EBADMSG);
        assert(!memcmp(&plan,&sentinel,sizeof(plan)));
        image[offsets[i]]^=1;
    }
    unsigned before=hash_calls;
    plan=sentinel;
    assert(ans1_firmware_validate(image,sizeof(image)-1,0x87f600000ULL,0xa00000,&plan)==-EINVAL);
    assert(ans1_firmware_validate(image,sizeof(image),0x87f600001ULL,0xa00000,&plan)==-EINVAL);
    assert(ans1_firmware_validate(image,sizeof(image),0x87f600000ULL,0xa01000,&plan)==-EINVAL);
    assert(ans1_firmware_validate(NULL,sizeof(image),0x87f600000ULL,0xa00000,&plan)==-EINVAL);
    assert(ans1_firmware_validate(image,sizeof(image),0x87f600000ULL,0xa00000,NULL)==-EINVAL);
    assert(hash_calls==before && !memcmp(&plan,&sentinel,sizeof(plan)));
    memcpy(copy,image,sizeof(copy));
    assert(ans1_firmware_parameters(copy,sizeof(copy),0x80,266666666,0x12340056,&plan)==-EINVAL);
    assert(ans1_firmware_parameters(copy,sizeof(copy),0x11,0,0x12340056,&plan)==-EINVAL);
    assert(ans1_firmware_parameters(copy,sizeof(copy),0x11,266666666,0x12345678,&plan)==-EINVAL);
    assert(!memcmp(copy,image,sizeof(copy)) && !memcmp(&plan,&sentinel,sizeof(plan)));
    assert(ans1_firmware_parameters(copy,sizeof(copy),0x11,266666666,0x12340056,&plan)==0);
    assert(ans1_fwsg_parameters_710(copy,sizeof(copy)));
    assert(ans1_fwsg_u32(copy+0x48014)==0x7000);
    assert(ans1_fwsg_u32(copy+0x48020)==0x11);
    assert(ans1_fwsg_u32(copy+0x480b1)==266666666);
    assert(ans1_fwsg_u32(copy+0x480bd)==0x7f6f1000);
    assert(ans1_fwsg_u32(copy+0x480c1)==8);
    const u32 starts[]={0x48008,0x48014,0x48020,0x4802c,0x4803c,0x480a5,0x480b1,0x480bd,0x480cd};
    const u32 sizes[]={4,4,4,8,8,4,4,8,4};
    for (u32 i=0;i<sizeof(copy);i++) {
        bool allowed=false;
        for (u32 j=0;j<9;j++) allowed |= i>=starts[j] && i-starts[j]<sizes[j];
        if (!allowed) assert(copy[i]==image[i]);
    }
    assert(ans1_firmware_parameters(copy,sizeof(copy),0x11,266666666,0x12340056,&plan)==-EBADMSG);
    struct ans1_firmware_staging staging={0};
    for (int i=1;i<=2;i++) {
        allocation=0; fail_allocation=i;
        assert(ans1_firmware_build(image,sizeof(image),0x11,266666666,0x12340056,&staging)==-ENOMEM);
        assert(!staging.data && !staging.bytes && !outstanding);
    }
    allocation=0; fail_allocation=0;
    assert(ans1_firmware_build(image,sizeof(image),0x11,266666666,0x12340056,&staging)==0);
    assert(staging.bytes==0xa00000 && outstanding==1);
    for (u32 i=0;i<staging.bytes;i++) {
        bool file_byte = i<0x47b88 || (i>=0x48000 && i<0x601c4);
        assert(staging.data[i]==(file_byte ? copy[i] : 0));
    }
    assert(ans1_firmware_build(image,sizeof(image),0x11,266666666,0x12340056,&staging)==-EINVAL);
    ans1_firmware_free(&staging);
    assert(!staging.data && !staging.bytes && !outstanding);
    ans1_firmware_free(&staging);
    assert(!outstanding);
    puts("Pinned firmware validation with Windows SHA-256 passed");
}
'''
test = out / 'test_firmware.c'
test.write_text(prefix + source + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_firmware.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
               '-I', str(HERE), str(test), '-lbcrypt', '-o', str(exe)], check=True)
image = ROOT / 'artifacts/ans-pristine-candidate/ans1-710.500.1-17L256-analysis-only.fwsg'
subprocess.run([str(exe), str(image)], check=True)
report.write_text(json.dumps({
    'status': 'passed', 'hardware_validation': False,
    'crypto_backend': 'Windows BCrypt SHA-256, not kernel SHA-256',
    'image_sha256': hashlib.sha256(image.read_bytes()).hexdigest(),
    'validator_sha256': hashlib.sha256((HERE / 'ans1_firmware.c').read_bytes()).hexdigest(),
    'test_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'coverage': ['pinned image', 'five whole-image mutations', 'truncated size',
                 'wrong reservation base/size', 'null inputs', 'unchanged failure output',
                 'staging allocation failures', 'all staging bytes', 'staging cleanup'],
}, indent=2), encoding='utf-8')
