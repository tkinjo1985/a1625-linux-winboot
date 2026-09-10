/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_CLOCK_H
#define A1625_ANS1_CLOCK_H
#include "ans1_wire.h"

/* Pure arithmetic from pinned T7000 iBoot 0x1512c. Caller supplies a coherent
 * read-only snapshot of PLL registers +0, +4, +8; this performs no MMIO.
 */
static inline bool ans1_pll_rate(u32 control, u32 bypass, u32 mode, u32 *rate)
{
	u64 value;
	u32 post;
	if (!rate)
		return false;
	if (!(control & (1U << 31))) {
		*rate = (bypass & 1) ? 24000000 : 0;
		return true;
	}
	post = (control >> 4) & 31;
	if (!post)
		return false;
	value = (control >> 12) & 511;
	if (mode & (1U << 27))
		value *= 48000000;
	else
		value = value * 24000000 / ((control & 15) + 1);
	value /= post;
	if (value > 0xffffffffULL)
		return false;
	*rate = value;
	return true;
}

/* Slot 56 selectors 0 and 5..10 only. Others need additional clock sources.
 * Source slot 5 is PLL index 4, because PLL i populates cache slot i+1.
 */
static inline bool ans1_ccna_rate(u32 control, u32 pll4_rate, u32 *rate)
{
	static const u32 divisors[] = {9,7,8,12,18,24};
	u32 selector = (control >> 24) & 63;
	if (!rate || !(control & (1U << 31)))
		return false;
	if (!selector) {
		*rate = 24000000;
		return true;
	}
	if (selector < 5 || selector > 10 || !pll4_rate)
		return false;
	pll4_rate /= divisors[selector - 5];
	if (!pll4_rate)
		return false;
	*rate = pll4_rate;
	return true;
}
#endif
