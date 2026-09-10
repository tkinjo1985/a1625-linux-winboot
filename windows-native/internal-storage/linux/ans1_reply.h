/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_REPLY_H
#define A1625_ANS1_REPLY_H

#include "ans1_wire.h"

enum ans1_wait_phase {
	ANS1_WAIT_READY,
	ANS1_WAIT_COMMAND_BUFFER,
	ANS1_WAIT_READ,
};

enum ans1_reply_result {
	ANS1_REPLY_INVALID,
	ANS1_REPLY_NOTIFICATION,
	ANS1_REPLY_COMPLETE,
	ANS1_REPLY_COMMAND_ERROR,
};

/* Input is decoded mailbox data, not the combined endpoint/data wire word.
 * A notification never extends the caller's absolute completion deadline.
 * No timeout or reply error establishes that outstanding DMA has stopped.
 */
static inline enum ans1_reply_result
ans1_check_reply(u32 expected_endpoint, u32 endpoint, u64 data,
		 enum ans1_wait_phase phase)
{
	u32 tag, status, expected_tag, expected_status;

	if (expected_endpoint > 255 || endpoint != expected_endpoint)
		return ANS1_REPLY_INVALID;
	switch (phase) {
	case ANS1_WAIT_READY:
		expected_tag = 254;
		expected_status = 10;
		break;
	case ANS1_WAIT_COMMAND_BUFFER:
		expected_tag = 253;
		expected_status = 10;
		break;
	case ANS1_WAIT_READ:
		expected_tag = 0;
		expected_status = 0;
		break;
	default:
		return ANS1_REPLY_INVALID;
	}
	if (data == 4)
		return ANS1_REPLY_NOTIFICATION;
	if ((data & ~0xffffULL) || (data & 15) != 2)
		return ANS1_REPLY_INVALID;
	tag = (data >> 4) & 255;
	status = (data >> 12) & 15;
	if (tag != expected_tag)
		return ANS1_REPLY_INVALID;
	if (status == expected_status)
		return ANS1_REPLY_COMPLETE;
	if (status == 1 || status == 2)
		return ANS1_REPLY_COMMAND_ERROR;
	return ANS1_REPLY_INVALID;
}

#endif
