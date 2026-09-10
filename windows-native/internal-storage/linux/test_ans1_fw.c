/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include "ans1_fw.h"

int main(void)
{
	struct ans1_fw_segment s[2] = {{0x800000000ULL, 0, 0x1000},
		{0x800002000ULL, 0x2000, 0x1000}};
	struct ans1_fw_segment result = {1, 2, 3};
	assert(ans1_fw_region(s, 2, 0x800000000ULL, 0x3000, &result));
	assert(result.phys == s[0].phys && result.iova == 0 && result.size == 0x3000);
	result = (struct ans1_fw_segment){1, 2, 3};
#define REJECT(base, span, count) do { \
	assert(!ans1_fw_region(s, count, base, span, &result)); \
	assert(result.phys == 1 && result.iova == 2 && result.size == 3); \
} while (0)
	REJECT(s[0].phys, 0x2fff, 2);
	REJECT(s[0].phys + 1, 0x3000, 2);
	REJECT(s[0].phys, ~0ULL, 2);
	REJECT(s[0].phys, 0x3000, 0);
	REJECT(s[0].phys, 0x3000, 33);
	s[1].iova++;
	REJECT(s[0].phys, 0x3000, 2);
	s[1] = (struct ans1_fw_segment){s[0].phys, 0, 0x1000};
	REJECT(s[0].phys, 0x3000, 2);
	s[1] = (struct ans1_fw_segment){s[0].phys - 0x1000, 0, 0x1000};
	REJECT(s[0].phys, 0x3000, 2);
	s[0].size = 0;
	REJECT(s[0].phys, 0x3000, 1);
	s[0] = (struct ans1_fw_segment){~0ULL - 10, 0, 11};
	REJECT(0, ~0ULL, 1);
	s[0] = (struct ans1_fw_segment){0, ~0ULL - 10, 11};
	REJECT(0, 4096, 1);
	puts("ANS1 firmware interval validation tests passed");
	struct ans1_fw_image_segment image[2] = {
		{0, 0x47b88, 0x47b88}, {0x48000, 0x181c4, 0xa8bc4}};
	assert(ans1_fw_heap(image, 2, 0x87f600000ULL, 0xa00000,
			    0xf1000, 0xe00000, &result));
	assert(result.phys == 0x87f6f1000ULL && result.iova == 0xf1000 &&
	       result.size == 0x90f000);
	assert(ans1_fw_heap(image, 2, 0x87f600000ULL, 0xa00000,
			    0xf1000, 0x1000, &result) && result.size == 0x1000);
#define BAD_HEAP(base, span, extent) do { \
	result = (struct ans1_fw_segment){1, 2, 3}; \
	assert(!ans1_fw_heap(image, 2, base, span, extent, 0xe00000, &result)); \
	assert(result.phys == 1 && result.iova == 2 && result.size == 3); \
} while (0)
	BAD_HEAP(0x87f600001ULL, 0xa00000, 0xf1000);
	BAD_HEAP(~0xfffULL, 0x2000, 0x1000);
	BAD_HEAP(0x87f600000ULL, 0xa00000, 0xf0000);
	BAD_HEAP(0x87f600000ULL, 0xf1000, 0xf1000);
	image[1].address = 0x47000;
	BAD_HEAP(0x87f600000ULL, 0xa00000, 0xf1000);
	image[1].address = 0x48000;
	image[1].file_bytes = image[1].memory_bytes + 1;
	BAD_HEAP(0x87f600000ULL, 0xa00000, 0xf1000);
	puts("ANS1 finite heap placement tests passed");
	return 0;
}
