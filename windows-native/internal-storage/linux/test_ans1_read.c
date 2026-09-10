/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ans1_read.h"

int main(void)
{
	u8 cmd[128], expected[128] = {0};
	const u64 base = 0x800000000ULL;
	unsigned int i;

	/* Literal wire fixture: final representable LBA, one 4 KiB DMA page. */
	expected[0] = 0x10;
	expected[2] = 8;
	expected[4] = expected[5] = expected[6] = expected[7] = 0xff;
	expected[8] = 1;
	expected[0x32] = 0x80;
	memset(cmd, 0xa5, sizeof(cmd));
	assert(ans1_build_read(cmd, 0xffffffffULL, 0x100000000ULL,
			       4096, base, base, 4096));
	assert(!memcmp(cmd, expected, sizeof(cmd)));

#define REJECT(lba, capacity, bytes, dma, begin, size) do { \
	memset(cmd, 0xa5, sizeof(cmd)); \
	assert(!ans1_build_read(cmd, lba, capacity, bytes, dma, begin, size)); \
	for (i = 0; i < sizeof(cmd); i++) assert(cmd[i] == 0xa5); \
} while (0)
	REJECT(1, 1, 4096, base, base, 4096);
	REJECT(0, 0, 4096, base, base, 4096);
	REJECT(0, 0x100000001ULL, 4096, base, base, 4096);
	REJECT(0x100000000ULL, 1, 4096, base, base, 4096);
	REJECT(0, 1, 512, base, base, 4096);
	REJECT(0, 1, 16384, base, base, 4096);
	REJECT(0, 1, 4096, base + 1, base, 8192);
	REJECT(0, 1, 4096, base, base + 4096, 4096);
	REJECT(0, 1, 4096, base, base, 4095);
	REJECT(0, 1, 4096, base + 4096, base, 8191);
	REJECT(0, 1, 4096, 1ULL << 44, 1ULL << 44, 4096);
	REJECT(0, 1, 4096, base, base, ~0ULL);
	assert(!ans1_build_read(NULL, 0, 1, 4096, base, base, 4096));
	assert(ans1_build_read(cmd, 0, 1, 4096, base + 4096, base, 8192));
	assert(ans1_build_read(cmd, 0, 1, 4096,
			       (1ULL << 44) - 4096, (1ULL << 44) - 4096, 4096));
	puts("ANS1 read encoding and range tests passed");
	return 0;
}
