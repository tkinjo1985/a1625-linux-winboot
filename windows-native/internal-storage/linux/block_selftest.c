// SPDX-License-Identifier: GPL-2.0-only OR MIT
/* RAM-only synthetic block frontend test. No controller, MMIO or DMA calls. */
#include <linux/device.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/mutex.h>
#include "ans1_block.h"

static struct device *parent;
static struct ans1_block *block;
static DEFINE_MUTEX(teardown_lock);

/* This removes only the synthetic disk. It never resets an ANS controller. */
static void remove_synthetic_disk(void)
{
	if (!IS_ERR_OR_NULL(block)) {
		ans1_block_destroy(block);
		block = NULL;
		root_device_unregister(parent);
		parent = NULL;
	}
}

static int stop_selftest(const char *value, const struct kernel_param *kp)
{
	bool stop;
	int ret = kstrtobool(value, &stop);

	if (ret)
		return ret;
	if (!stop)
		return -EINVAL;
	mutex_lock(&teardown_lock);
	if (IS_ERR_OR_NULL(block))
		ret = -ENODEV;
	else {
		remove_synthetic_disk();
		pr_info("ANS1 block selftest: synthetic disk removed\n");
	}
	mutex_unlock(&teardown_lock);
	return ret;
}

static const struct kernel_param_ops stop_ops = { .set = stop_selftest };
module_param_cb(stop, &stop_ops, NULL, 0200);
MODULE_PARM_DESC(stop, "Write true after testing to remove the synthetic disk; no restart");

static int synthetic_read(void *cookie, u32 lba, void *page)
{
	u8 *bytes = page;
	unsigned int i;

	if (lba == 15)
		return -EIO; /* Explicit fault-injection page; latches frontend error. */
	for (i = 0; i < 4096; i++)
		bytes[i] = (u8)(lba ^ i ^ (i >> 8));
	return 0;
}

static int __init block_selftest_init(void)
{
	if (!of_machine_is_compatible("apple,j42d") ||
	    !of_machine_is_compatible("apple,t7000"))
		return -ENODEV;
	parent = root_device_register("ans1-block-selftest");
	if (IS_ERR(parent))
		return PTR_ERR(parent);
	block = ans1_block_create(parent, 16, synthetic_read, NULL);
	if (IS_ERR(block)) {
		int ret = PTR_ERR(block);
		root_device_unregister(parent);
		return ret;
	}
	pr_info("ANS1 block selftest: synthetic RAM data only; no NAND access\n");
	return 0;
}

static void __exit block_selftest_exit(void)
{
	mutex_lock(&teardown_lock);
	remove_synthetic_disk();
	mutex_unlock(&teardown_lock);
}

module_init(block_selftest_init);
module_exit(block_selftest_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A1625 RAM-only synthetic read-only block frontend test");
