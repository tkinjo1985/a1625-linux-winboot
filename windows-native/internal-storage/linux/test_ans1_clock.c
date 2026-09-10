/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include "ans1_clock.h"
int main(void)
{
	u32 rate=123, ccna=123;
	assert(ans1_pll_rate(0,1,0,&rate) && rate==24000000);
	assert(ans1_pll_rate(0,0,0,&rate) && !rate);
	assert(ans1_pll_rate(0x80000010U | (100U<<12),0,0,&rate));
	assert(rate==2400000000U);
	assert(ans1_ccna_rate(0x85000000,rate,&ccna) && ccna==266666666);
	/* Two identical read-only hardware snapshots from the owned T7000. */
	assert(ans1_pll_rate(0x80032010,0x40000000,0x88480348,&rate));
	assert(rate==2400000000U);
	assert(ans1_ccna_rate(0x85100000,rate,&ccna) && ccna==266666666);
	assert(ans1_ccna_rate(0x80000000,0,&ccna) && ccna==24000000);
	rate=123;
	assert(!ans1_pll_rate(0x80000000,0,0,&rate) && rate==123);
	assert(!ans1_pll_rate(0x80000010U | (511U<<12),0,1U<<27,&rate) && rate==123);
	ccna=123;
	assert(!ans1_ccna_rate(0,2400000000U,&ccna) && ccna==123);
	assert(!ans1_ccna_rate(0x81000000,2400000000U,&ccna) && ccna==123);
	assert(!ans1_ccna_rate(0xbf000000,2400000000U,&ccna) && ccna==123);
	puts("T7000 PLL/ANS clock arithmetic tests passed; synthetic and captured inputs");
}
