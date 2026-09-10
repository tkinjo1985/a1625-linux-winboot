/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_WIRE_H
#define A1625_ANS1_WIRE_H

#ifdef __KERNEL__
#include <linux/types.h>
#else
#include <stdbool.h>
#include <stdint.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t u8;
#endif

/* AKF carries an endpoint byte and 56 data bits in one 64-bit word.
 * Register access/endianness belongs to the mailbox driver, not this codec.
 */
#define ANS1_WIRE_DATA_MASK 0x00ffffffffffffffULL

static inline bool ans1_wire_encode(u32 endpoint, u64 data, u64 *wire)
{
	if (!wire || endpoint > 255 || (data & ~ANS1_WIRE_DATA_MASK))
		return false;
	*wire = ((u64)endpoint << 56) | data;
	return true;
}

static inline u8 ans1_wire_endpoint(u64 wire)
{
	return wire >> 56;
}

static inline u64 ans1_wire_data(u64 wire)
{
	return wire & ANS1_WIRE_DATA_MASK;
}

#endif
