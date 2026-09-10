/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include "ans1_queue.h"

int main(void)
{
	struct ans1_queue_messages out = {1, 2};
	assert(ans1_queue_messages(0x800000000ULL, 0x800000000ULL, 4096, &out));
	assert(out.register_buffer == 0x0008000000000020ULL);
	assert(out.register_tag == 0x02000001ULL);
	out = (struct ans1_queue_messages){1, 2};
#define REJECT(dma, base, size) do { \
	assert(!ans1_queue_messages(dma, base, size, &out)); \
	assert(out.register_buffer == 1 && out.register_tag == 2); \
} while (0)
	REJECT(1, 0, 4096);
	REJECT(1ULL << 40, 1ULL << 40, 4096);
	REJECT(4096, 4097, 4096);
	REJECT(4096, 0, 4096 + 127);
	REJECT(0, 0, 127);
	REJECT(4096, 4096, ~0ULL);
	assert(ans1_queue_messages(4096, 0, 4096 + 128, &out));
	assert(ans1_queue_messages((1ULL << 40) - 4096,
				   (1ULL << 40) - 4096, 4096, &out));
	puts("ANS1 command-buffer registration encoding tests passed");
	return 0;
}
