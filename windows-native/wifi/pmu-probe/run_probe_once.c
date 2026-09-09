/* SPDX-License-Identifier: GPL-2.0-only */
/* Freestanding AArch64 Linux runner: exactly one finit_module syscall. */
#if !defined(__aarch64__) || !defined(__linux__)
#error This runner is only for AArch64 Linux
#endif

static long syscall3(long nr, long a, long b, long c)
{
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x8 __asm__("x8") = nr;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory", "cc");
	return x0;
}

static void message(const char *text, unsigned long length)
{
	(void)syscall3(64, 2, (long)text, length);
}

#define MESSAGE(text) message(text, sizeof(text) - 1)

__attribute__((used, noreturn)) static void run(long *stack)
{
	long fd, result;
	const char *path;

	if (stack[0] != 2 && stack[0] != 3) {
		MESSAGE("usage: run_probe_once /run/path/to/probe.ko [module-options]\n");
		(void)syscall3(93, 2, 0, 0);
		__builtin_unreachable();
	}
	path = (const char *)stack[2];
	/* openat(AT_FDCWD, path, O_RDONLY|O_CLOEXEC); no mode argument needed. */
	fd = syscall3(56, -100, (long)path, 0x80000);
	if (fd < 0) {
		MESSAGE("probe file open failed\n");
		(void)syscall3(93, 1, 0, 0);
		__builtin_unreachable();
	}
	result = syscall3(273, fd, stack[0] == 3 ? stack[3] : (long)"", 0);
	(void)syscall3(57, fd, 0, 0);
	/* Never retry with init_module, including when finit_module is unavailable. */
	if (result == -125) {
		MESSAGE("probe returned expected ECANCELED; verify kernel log and module absence\n");
		(void)syscall3(93, 0, 0, 0);
	} else {
		MESSAGE("unexpected finit_module result; stopped without retry\n");
		(void)syscall3(93, 1, 0, 0);
	}
	__builtin_unreachable();
}

__attribute__((naked, noreturn)) void _start(void)
{
	__asm__ volatile("mov x0, sp\n\tb run");
}
