// SPDX-License-Identifier: GPL-2.0-only
/* Read PMGR status only. No ANS MMIO/FIFO access or power transition. */
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/ioport.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/regmap.h>

static int __init a1625_ans_power_snapshot_init(void)
{
	struct device_node *node;
	struct resource resource;
	struct regmap *map;
	unsigned int ans, debug;
	int ret;

	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;
	node = of_find_node_by_path("/soc/power-management@20e000000");
	if (!node)
		return -ENODEV;
	if (!of_device_is_compatible(node, "apple,t7000-pmgr")) {
		ret = -ENODEV;
		goto out_node;
	}
	ret = of_address_to_resource(node, 0, &resource);
	if (ret)
		goto out_node;
	if (resource.start != 0x20e000000ULL || resource_size(&resource) != 0x24000) {
		ret = -EINVAL;
		goto out_node;
	}
	/* Refuse resource descriptions that could turn a read into an implicit
	 * clock/reset/hardware-lock operation. Do not use the resource-managing
	 * syscon lookup in a read-only diagnostic.
	 */
	if (of_find_property(node, "clocks", NULL) ||
	    of_find_property(node, "resets", NULL) ||
	    of_find_property(node, "hwlocks", NULL)) {
		ret = -EINVAL;
		goto out_node;
	}
	map = device_node_to_regmap(node);
	if (IS_ERR(map)) {
		ret = PTR_ERR(map);
		goto out_node;
	}
	/* Captured PMGR gate IDs 0x16/0x35 resolve to these exact offsets.
	 * PMGR uses uncached status reads in the pinned pmgr-pwrstate driver.
	 * Do not infer that power stays active after this snapshot.
	 */
	ret = regmap_read(map, 0x20318, &ans);
	if (ret)
		goto out_node;
	ret = regmap_read(map, 0x20118, &debug);
	if (ret)
		goto out_node;
	pr_info("a1625_ans_power_snapshot: ans=%08x target=%x actual=%x debug=%08x target=%x actual=%x\n",
		ans, ans & 0xf, (ans >> 4) & 0xf,
		debug, debug & 0xf, (debug >> 4) & 0xf);
	pr_info("a1625_ans_power_snapshot: complete; two PMGR reads; no writes or ANS access\n");
	ret = -ECANCELED;
out_node:
	of_node_put(node);
	return ret;
}
module_init(a1625_ans_power_snapshot_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A1625 ANS/DEBUG PMGR status snapshot without power changes");
