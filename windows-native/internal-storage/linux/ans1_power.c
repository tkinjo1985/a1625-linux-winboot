// SPDX-License-Identifier: GPL-2.0-only
#include <linux/errno.h>
#include <linux/ioport.h>
#include <linux/mfd/syscon.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/regmap.h>
#include "ans1_power.h"

int ans1_power_require_off(void)
{
	struct device_node *node;
	struct resource resource;
	struct regmap *map;
	unsigned int ans, debug;
	int ret;

	if (!of_machine_is_compatible("apple,j42d") ||
	    !of_machine_is_compatible("apple,t7000"))
		return -ENODEV;
	node = of_find_node_by_path("/soc/power-management@20e000000");
	if (!node)
		return -ENODEV;
	ret = -ENODEV;
	if (!of_device_is_compatible(node, "apple,t7000-pmgr"))
		goto out;
	ret = of_address_to_resource(node, 0, &resource);
	if (ret)
		goto out;
	ret = -EINVAL;
	if (resource.start != 0x20e000000ULL || resource_size(&resource) != 0x24000 ||
	    of_find_property(node, "clocks", NULL) ||
	    of_find_property(node, "resets", NULL) ||
	    of_find_property(node, "hwlocks", NULL))
		goto out;
	/* Existing syscon only; avoid implicit clock/reset operations. */
	map = device_node_to_regmap(node);
	if (IS_ERR(map)) {
		ret = PTR_ERR(map);
		goto out;
	}
	ret = regmap_read(map, 0x20318, &ans);
	if (ret)
		goto out;
	ret = regmap_read(map, 0x20118, &debug);
	if (!ret)
		ret = (ans == 0x0f000200 && debug == 0x00000200) ? 0 : -EBUSY;
out:
	of_node_put(node);
	return ret;
}
