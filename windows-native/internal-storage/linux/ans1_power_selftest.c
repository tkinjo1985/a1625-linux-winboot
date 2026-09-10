// SPDX-License-Identifier: GPL-2.0-only
/* Read-only PMGR preflight: no power writes, ANS access, or firmware start. */
#include <linux/errno.h>
#include <linux/module.h>
#include "ans1_power.h"

static int __init ans1_power_selftest_init(void)
{
	int ret = ans1_power_require_off();

	if (ret) {
		pr_err("ans1-power-selftest: preflight rejected: %d\n", ret);
		return ret;
	}
	pr_info("ans1-power-selftest: PASS read-only off-state preflight; no power ownership or DMA quiescence established\n");
	/* Self-cleaning even on kernels without module unloading. */
	return -ECANCELED;
}
module_init(ans1_power_selftest_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A1625 read-only ANS power preflight selftest");
