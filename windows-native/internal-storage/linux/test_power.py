"""Exercise the actual power preflight with counted, read-only host mocks."""
from pathlib import Path
import os
import subprocess

HERE = Path(__file__).resolve().parent
out = HERE.parents[2] / 'artifacts/ans-offline-tests'
out.mkdir(parents=True, exist_ok=True)
source = '\n'.join(line for line in (HERE / 'ans1_power.c').read_text().splitlines()
                   if not line.startswith('#include <linux/'))
prefix = r'''
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct device_node { int unused; };
struct regmap { int unused; };
struct resource { uint64_t start, end; };
static struct device_node node;
static struct regmap map;
static bool j42d, t7000, present, compatible;
static const char *property;
static int address_error, map_error, read_error, fail_read;
static int finds, node_puts, maps, reads;
static uint64_t base, span;
static unsigned int ans, debug;
#define IS_ERR(p) ((uintptr_t)(p) >= (uintptr_t)-4095)
#define PTR_ERR(p) ((int)(intptr_t)(p))
static bool of_machine_is_compatible(const char *s) {
    if (!strcmp(s,"apple,j42d")) return j42d;
    assert(!strcmp(s,"apple,t7000")); return t7000;
}
static struct device_node *of_find_node_by_path(const char *s) {
    assert(!strcmp(s,"/soc/power-management@20e000000")); finds++;
    return present ? &node : NULL;
}
static bool of_device_is_compatible(struct device_node *n,const char *s) {
    assert(n==&node && !strcmp(s,"apple,t7000-pmgr")); return compatible;
}
static int of_address_to_resource(struct device_node *n,int index,struct resource *r) {
    assert(n==&node && !index); r->start=base; r->end=base+span-1;
    return address_error;
}
static uint64_t resource_size(struct resource *r) { return r->end-r->start+1; }
static void *of_find_property(struct device_node *n,const char *s,void *length) {
    assert(n==&node && !length); return property && !strcmp(property,s) ? &node : NULL;
}
static struct regmap *device_node_to_regmap(struct device_node *n) {
    assert(n==&node); maps++; return map_error ? (struct regmap *)(intptr_t)map_error : &map;
}
static int regmap_read(struct regmap *m,unsigned int reg,unsigned int *value) {
    assert(m==&map); reads++;
    assert(reg==(reads==1 ? 0x20318U : 0x20118U));
    if(reads==fail_read) return read_error;
    *value=reads==1 ? ans : debug; return 0;
}
static void of_node_put(struct device_node *n) { assert(n==&node); node_puts++; }
static void reset(void) {
    j42d=t7000=present=compatible=true; property=NULL;
    address_error=map_error=read_error=fail_read=0;
    finds=node_puts=maps=reads=0; base=0x20e000000ULL; span=0x24000;
    ans=0x0f000200; debug=0x200;
}
static void check(int expected,int expected_maps,int expected_reads) {
    assert(ans1_power_require_off()==expected);
    assert(maps==expected_maps && reads==expected_reads);
    assert(node_puts==(finds && present ? 1 : 0));
}
'''
# The helper calls the API before its definition.
prefix = '#include "ans1_power.h"\n' + prefix
tests = r'''
int main(void) {
    reset(); check(0,1,2);
    reset(); j42d=false; check(-ENODEV,0,0); assert(!finds);
    reset(); t7000=false; check(-ENODEV,0,0); assert(!finds);
    reset(); present=false; check(-ENODEV,0,0);
    reset(); compatible=false; check(-ENODEV,0,0);
    reset(); address_error=-EIO; check(-EIO,0,0);
    reset(); base++; check(-EINVAL,0,0);
    reset(); span--; check(-EINVAL,0,0);
    reset(); span++; check(-EINVAL,0,0);
    const char *properties[]={"clocks","resets","hwlocks"};
    for(unsigned int i=0;i<3;i++) {
        reset(); property=properties[i]; check(-EINVAL,0,0);
    }
    reset(); map_error=-ENXIO; check(-ENXIO,1,0);
    for(int i=1;i<=2;i++) {
        reset(); fail_read=i; read_error=-EIO; check(-EIO,1,i);
    }
    for(unsigned int bit=0;bit<32;bit++) {
        reset(); ans^=1U<<bit; check(-EBUSY,1,2);
        reset(); debug^=1U<<bit; check(-EBUSY,1,2);
    }
    reset(); ans=debug=0; check(-EBUSY,1,2);
    printf("Power preflight guards, errors, states and node references passed\n");
}
'''
test = out / 'test_power.c'
test.write_text(prefix + source + tests, encoding='utf-8')
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
exe = out / 'test_power.exe'
subprocess.run([str(gcc), '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                '-I', str(HERE), str(test), '-o', str(exe)], check=True)
subprocess.run([str(exe)], check=True)
