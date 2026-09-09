// SPDX-License-Identifier: GPL-2.0-only
/* One-shot, read-only WL_REG_ON diagnostic for the owned J42d board. */
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/i2c.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>

#define J42D_PMU_PATH "/soc/i2c@20a110000/pmic@74"
#define J42D_WL_REG_ON_CONFIG 0x406

static int __init a1625_pmu_probe_init(void)
{
	struct device_node *node;
	struct i2c_client *client;
	struct regmap *map;
	unsigned int value;
	int ret;

	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;

	node = of_find_node_by_path(J42D_PMU_PATH);
	if (!node)
		return -ENODEV;
	if (!of_device_is_compatible(node, "apple,i2c-pmic")) {
		of_node_put(node);
		return -ENODEV;
	}
	client = of_find_i2c_device_by_node(node);
	of_node_put(node);
	if (!client)
		return -ENODEV;

	/* Serialize against driver removal and use the existing bus/regmap locks. */
	device_lock(&client->dev);
	if (client->addr != 0x74 || !client->dev.driver) {
		ret = -ENODEV;
		goto out;
	}
	map = dev_get_regmap(&client->dev, NULL);
	if (!map) {
		ret = -ENODEV;
		goto out;
	}
	ret = regmap_read(map, J42D_WL_REG_ON_CONFIG, &value);
	if (!ret)
		pr_info("a1625_pmu_probe: WL_REG_ON config[0x406]=0x%02x; no writes\n",
			value);
out:
	device_unlock(&client->dev);
	put_device(&client->dev);
	if (ret) {
		pr_err("a1625_pmu_probe: read failed: %d\n", ret);
		return ret;
	}
	/* CONFIG_MODULE_UNLOAD=n: an init error frees this one-shot module. */
	pr_info("a1625_pmu_probe: complete; intentional -ECANCELED releases module\n");
	return -ECANCELED;
}
module_init(a1625_pmu_probe_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("J42d WL_REG_ON one-shot read-only PMU diagnostic");
