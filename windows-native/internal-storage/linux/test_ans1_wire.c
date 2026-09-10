/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stddef.h>
#include "ans1_wire.h"

int main(void)
{
	u64 word = 0;
	const u64 samples[] = {0, 1, 0x00200000000a000aULL,
			       0x00000000000ff003ULL, ANS1_WIRE_DATA_MASK};

	/* Endpoint is not a second 32-bit register as with ASC mailboxes. */
	assert(ans1_wire_encode(5, 0xff003, &word));
	assert(word == 0x05000000000ff003ULL);
	assert(ans1_wire_endpoint(0xab123456789abcdeULL) == 0xab);
	assert(ans1_wire_data(0xab123456789abcdeULL) == 0x123456789abcdeULL);
	for (u32 ep = 0; ep < 256; ep++) {
		for (unsigned int i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
			assert(ans1_wire_encode(ep, samples[i], &word));
			assert(ans1_wire_endpoint(word) == ep);
			assert(ans1_wire_data(word) == samples[i]);
		}
	}
	/* Never truncate high message bits into a different valid command. */
	for (unsigned int bit = 56; bit < 64; bit++) {
		word = 0xdeadbeefULL;
		assert(!ans1_wire_encode(5, 1ULL << bit, &word));
		assert(word == 0xdeadbeefULL);
	}
	word = 0xdeadbeefULL;
	assert(!ans1_wire_encode(256, 0, &word));
	assert(!ans1_wire_encode(0xffffffffU, 0, &word));
	assert(word == 0xdeadbeefULL);
	assert(!ans1_wire_encode(0, 0, NULL));
	return 0;
}
