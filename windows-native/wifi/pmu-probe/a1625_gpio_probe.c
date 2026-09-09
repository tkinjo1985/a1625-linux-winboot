// SPDX-License-Identifier: GPL-2.0-only
/* Read-only PCIe control pin snapshot using the bound pinctrl regmap. */
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>

static int __init a1625_gpio_probe_init(void)
{
	static const unsigned int pins[] = { 77, 41, 63 };
	struct device_node *node;
	struct platform_device *pdev;
	struct regmap *map;
	unsigned int i, cached, live;
	int ret = -ENODEV;

	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;
	node = of_find_node_by_path("/soc/pinctrl@20e300000");
	if (!node)
		return -ENODEV;
	if (!of_device_is_compatible(node, "apple,t7000-pinctrl")) {
		of_node_put(node);
		return -ENODEV;
	}
	pdev = of_find_device_by_node(node);
	of_node_put(node);
	if (!pdev)
		return -ENODEV;
	device_lock(&pdev->dev);
	if (!pdev->dev.driver)
		goto out;
	map = dev_get_regmap(&pdev->dev, NULL);
	if (!map)
		goto out;
	for (i = 0; i < ARRAY_SIZE(pins); i++) {
		ret = regmap_read(map, 4 * pins[i], &cached);
		if (ret)
			goto out;
		/* Input levels in this driver's flat cache may be stale. */
		ret = regmap_read_bypassed(map, 4 * pins[i], &live);
		if (ret)
			goto out;
		pr_info("a1625_gpio_probe: pin=%u cached=0x%08x live=0x%08x; no writes\n",
			pins[i], cached, live);
	}
out:
	device_unlock(&pdev->dev);
	put_device(&pdev->dev);
	if (ret) {
		pr_err("a1625_gpio_probe: read failed: %d\n", ret);
		return ret;
	}
	pr_info("a1625_gpio_probe: complete; intentional -ECANCELED releases module\n");
	return -ECANCELED;
}
module_init(a1625_gpio_probe_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("J42d PCIe control GPIO read-only diagnostic");
