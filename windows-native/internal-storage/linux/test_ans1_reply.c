/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include "ans1_reply.h"

int main(void)
{
	unsigned int word, bit;
	assert(ans1_check_reply(5, 5, 0xafe2, ANS1_WAIT_READY) == ANS1_REPLY_COMPLETE);
	assert(ans1_check_reply(6, 6, 0xafd2, ANS1_WAIT_COMMAND_BUFFER) == ANS1_REPLY_COMPLETE);
	assert(ans1_check_reply(5, 5, 2, ANS1_WAIT_READ) == ANS1_REPLY_COMPLETE);
	/* Exhaust the low word: only one successful single-tag read response. */
	for (word = 0; word < 65536; word++) {
		enum ans1_reply_result expected = ANS1_REPLY_INVALID;
		if (word == 2) expected = ANS1_REPLY_COMPLETE;
		if (word == 4) expected = ANS1_REPLY_NOTIFICATION;
		if (word == 0x1002 || word == 0x2002)
			expected = ANS1_REPLY_COMMAND_ERROR;
		assert(ans1_check_reply(5, 5, word, ANS1_WAIT_READ) == expected);
	}
	for (bit = 16; bit < 64; bit++)
		assert(ans1_check_reply(5, 5, 2 | (1ULL << bit), ANS1_WAIT_READ) == ANS1_REPLY_INVALID);
	assert(ans1_check_reply(5, 6, 2, ANS1_WAIT_READ) == ANS1_REPLY_INVALID);
	assert(ans1_check_reply(256, 256, 2, ANS1_WAIT_READ) == ANS1_REPLY_INVALID);
	assert(ans1_check_reply(5, 5, 2, ANS1_WAIT_READY) == ANS1_REPLY_INVALID);
	assert(ans1_check_reply(5, 5, 0xafe2, ANS1_WAIT_COMMAND_BUFFER) == ANS1_REPLY_INVALID);
	assert(ans1_check_reply(5, 5, 4, (enum ans1_wait_phase)99) == ANS1_REPLY_INVALID);
	puts("ANS1 completion classification tests passed");
	return 0;
}
