/* Read-only A1625/T7000 clock/revision snapshot. Fixed registers, no arguments. */
typedef unsigned long ulong;
#ifndef ANS_FW_CAPTURE_BYTES
#define ANS_FW_CAPTURE_BYTES 4096
#endif
#if ANS_FW_CAPTURE_BYTES != 4096 && ANS_FW_CAPTURE_BYTES != 10485760
#error unsupported capture size
#endif
static long call6(long n, long a, long b, long c, long d, long e, long f)
{
    register long x8 __asm__("x8") = n;
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    register long x4 __asm__("x4") = e;
    register long x5 __asm__("x5") = f;
    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
                     "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
    return x0;
}
static __attribute__((noreturn)) void finish(long status)
{
    call6(93, status, 0, 0, 0, 0, 0);
    __builtin_unreachable();
}
static int compatible(const char *s, long n, const char *expected)
{
    for (long p=0; p<n;) {
        long i=0;
        while (p+i<n && s[p+i] && expected[i] && s[p+i]==expected[i]) i++;
        if (p+i<n && !s[p+i] && !expected[i]) return 1;
        while (p<n && s[p]) p++;
        p++;
    }
    return 0;
}

void _start(void)
{
    char identity[256], output[90];
    const char hex[]="0123456789abcdef";
    unsigned values[10];
    long fd=call6(56,-100,(long)"/proc/device-tree/compatible",0,0,0,0);
    if (fd<0) finish(10);
    long n=call6(63,fd,(long)identity,sizeof(identity),0,0,0);
    call6(57,fd,0,0,0,0,0);
    if (n<=0 || n==(long)sizeof(identity) ||
        !compatible(identity,n,"apple,j42d") ||
        !compatible(identity,n,"apple,t7000")) finish(11);
    fd=call6(56,-100,(long)"/dev/mem",0,0,0,0);
    if (fd<0) finish(12);
    long pll=call6(222,0,4096,1,1,fd,0x20e004000UL);
    if ((ulong)pll >= (ulong)-4095) finish(13);
    long selector=call6(222,0,4096,1,1,fd,0x20e010000UL);
    if ((ulong)selector >= (ulong)-4095) finish(13);
    long revision=call6(222,0,4096,1,1,fd,0x20e02a000UL);
    if ((ulong)revision >= (ulong)-4095) finish(13);
    for (unsigned pass=0;pass<2;pass++) {
        __asm__ volatile("dmb sy" ::: "memory");
        values[pass*5]=*(volatile const unsigned *)(selector+0xc0);
        for (unsigned i=0;i<3;i++)
            values[pass*5+i+1]=((volatile const unsigned *)pll)[i];
        values[pass*5+4]=*(volatile const unsigned *)(revision+0x10);
        __asm__ volatile("dmb sy" ::: "memory");
    }
    call6(215,pll,4096,0,0,0,0);
    call6(215,selector,4096,0,0,0,0);
    call6(215,revision,4096,0,0,0,0);
    call6(57,fd,0,0,0,0,0);
    for (unsigned i=0;i<5;i++) if(values[i]!=values[i+5]) finish(15);
    for (unsigned i=0;i<10;i++) {
        for (unsigned j=0;j<8;j++) output[i*9+j]=hex[(values[i]>>(28-j*4))&15];
        output[i*9+8]='\n';
    }
    ulong written=0;
    while(written<sizeof(output)) {
        n=call6(64,1,(long)(output+written),sizeof(output)-written,0,0,0);
        if(n<=0) finish(14);
        written+=(ulong)n;
    }
    finish(0);
}
