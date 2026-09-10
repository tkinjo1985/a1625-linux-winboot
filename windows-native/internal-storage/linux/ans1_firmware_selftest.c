// SPDX-License-Identifier: GPL-2.0-only OR MIT
/* Ordinary-RAM validation only: no MMIO, DMA, ANS start, or block device. */
#include <linux/firmware.h>
#include <linux/module.h>
#include <linux/of.h>
#include "ans1_firmware.h"
#include "ans1_reservation.h"

static int __init ans1_firmware_selftest_init(void)
{
	const struct firmware *fw;
	struct ans1_firmware_staging staging = {};
	struct ans1_reservation *owner = NULL, *other = NULL;
	u32 i;
	int ret;

	if (!of_machine_is_compatible("apple,j42d") ||
	    !of_machine_is_compatible("apple,t7000"))
		return -ENODEV;
	ret = ans1_reservation_claim(&owner);
	if (ret)
		return ret;
	ret = ans1_reservation_claim(&other);
	if (ret != -EBUSY || other) {
		ans1_reservation_release(other);
		ans1_reservation_release(owner);
		return -EINVAL;
	}
	ans1_reservation_release(owner);
	owner = NULL;
	ret = ans1_reservation_claim(&owner);
	if (ret)
		return ret;
	ans1_reservation_release(owner);
	pr_info("ans1-firmware-selftest: PASS reservation conflict and release; no mapping or memory access\n");
	ret = request_firmware(&fw, "a1625/ans1-analysis-only.fwsg", NULL);
	if (ret)
		return ret;
	if (fw->size != 0x60240) {
		ret = -EINVAL;
		goto release;
	}
	/* Test inputs only, not a bootable payload or a generated stack guard. */
	ret = ans1_firmware_build(fw->data, fw->size, 0x11, 266666666,
				 0x12340056, &staging);
	if (ret)
		goto release;
	if (staging.plan.heap.phys != 0x87f6f1000ULL ||
	    staging.plan.heap.size != 0x90f000) {
		ret = -EINVAL;
		goto free;
	}
	for (i = 0x601c4; i < staging.bytes; i++) {
		if (staging.data[i]) {
			ret = -EINVAL;
			goto free;
		}
	}
	pr_info("ans1-firmware-selftest: PASS hash, layout, parameters, zero tail; no device I/O\n");
free:
	ans1_firmware_free(&staging);
release:
	release_firmware(fw);
	/* Never remain loaded, even when module unloading is disabled. */
	return ret ? ret : -ECANCELED;
}
module_init(ans1_firmware_selftest_init);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_DESCRIPTION("A1625 ordinary-RAM ANS firmware validation selftest");
