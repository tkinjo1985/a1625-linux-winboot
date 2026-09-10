/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_READ_H
#define A1625_ANS1_READ_H

#include "ans1_wire.h"

/* Byte encoding avoids native packing and endianness dependencies. */
static inline void ans1_put_le32(u8 *p, u32 value)
{
	p[0] = value;
	p[1] = value >> 8;
	p[2] = value >> 16;
	p[3] = value >> 24;
}

/* Initial single-tag, single-page read only. Geometry must come from verified
 * controller evidence, never a guessed capacity. The DMA interval must be an
 * allocation owned/mapped by the caller for this controller, not System RAM.
 * This checks arithmetic containment, not DMA ownership or firmware readiness.
 */
static inline bool ans1_build_read(u8 command[128], u64 lba, u64 capacity,
				  u32 lba_bytes, u64 dma, u64 dma_base,
				  u64 dma_size)
{
	unsigned int i;

	if (!command || lba_bytes != 4096 || !capacity ||
	    capacity > 0x100000000ULL || lba >= capacity ||
	    (dma & 4095) || (dma >> 12) > 0xffffffffULL ||
	    dma < dma_base || dma_size < 4096 ||
	    dma - dma_base > dma_size - 4096 ||
	    dma_base > ~0ULL - dma_size)
		return false;

	/* No caller-controlled opcode, flags, tag, length, or auxiliary area. */
	for (i = 0; i < 128; i++)
		command[i] = 0;
	command[0] = 0x10;
	command[2] = 8;
	ans1_put_le32(command + 4, (u32)lba);
	ans1_put_le32(command + 8, 1);
	ans1_put_le32(command + 0x30, (u32)(dma >> 12));
	return true;
}

#endif
