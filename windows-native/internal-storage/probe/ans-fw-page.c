/* SPDX-License-Identifier: MIT
 * Read-only DRAM capture, from the owned A1625's saved live ADT.
 * No arguments, MMIO, mailbox, power transition or storage writes.
 * Default is one page. The only larger build is the exact 10 MiB ADT region.
 */
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
static unsigned char page[ANS_FW_CAPTURE_BYTES];
void _start(void)
{
    char identity[256];
    long fd=call6(56, -100, (long)"/proc/device-tree/compatible", 0, 0, 0, 0);
    if (fd<0) finish(10);
    long n=call6(63, fd, (long)identity, sizeof(identity), 0, 0, 0);
    call6(57, fd, 0, 0, 0, 0, 0);
    if (n<=0 || n==(long)sizeof(identity) ||
        !compatible(identity,n,"apple,j42d") ||
        !compatible(identity,n,"apple,t7000")) finish(11);
    fd=call6(56, -100, (long)"/dev/mem", 0, 0, 0, 0); /* O_RDONLY */
    if (fd<0) finish(12);
    /* mmap(NULL, fixed size, PROT_READ, MAP_SHARED, fd, fixed DRAM address). */
    long address=call6(222, 0, sizeof(page), 1, 1, fd, 0x87f600000UL);
    if ((ulong)address >= (ulong)-4095) finish(13);
    volatile const unsigned char *mapped=(const unsigned char *)address;
    for (ulong i=0; i<sizeof(page); i++) page[i]=mapped[i];
    call6(215, address, sizeof(page), 0, 0, 0, 0);
    call6(57, fd, 0, 0, 0, 0, 0);
    ulong written=0;
    while (written<sizeof(page)) {
        n=call6(64, 1, (long)(page+written), sizeof(page)-written, 0, 0, 0);
        if (n<=0) finish(14);
        written+=(ulong)n;
    }
    finish(0);
}
