/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_BLOCK_H
#define A1625_ANS1_BLOCK_H
#include <linux/types.h>
struct device;
struct ans1_block;
/* read_page must return within 3 seconds, never expose partial/error data, and
 * own all DMA separately from this CPU buffer. No hardware recovery here.
 */
struct ans1_block *ans1_block_create(struct device *parent, u64 pages,
	int (*read_page)(void *cookie, u32 lba, void *cpu_page), void *cookie);
void ans1_block_destroy(struct ans1_block *block);
#endif
