/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_QUEUE_H
#define A1625_ANS1_QUEUE_H
#include "ans1_wire.h"

struct ans1_queue_messages { u64 register_buffer, register_tag; };

/* One 128-byte command at offset zero, tag zero. Caller owns/mapped the
 * allocation and must retain it through any timeout until proven quiescent.
 * Registration is not submission: wait for tag 253 before registering tag 0.
 */
static inline bool ans1_queue_messages(u64 dma, u64 owned_base, u64 owned_size,
				       struct ans1_queue_messages *out)
{
	if (!out || (dma & 4095) || dma >= (1ULL << 40) ||
	    owned_size < 128 || owned_base > ~0ULL - owned_size ||
	    dma < owned_base || dma - owned_base > owned_size - 128)
		return false;
	out->register_buffer = (dma << 16) | 0x20;
	out->register_tag = 0x02000001;
	return true;
}
#endif
