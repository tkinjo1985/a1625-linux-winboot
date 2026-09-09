// SPDX-License-Identifier: GPL-2.0-only
/* Bounded J42d power stage; optional observer must restore PERST low before return. */
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/machine.h>
#include <linux/i2c.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>

GPIO_LOOKUP_SINGLE(reset_lookup, NULL, NULL, 77,
		   "a1625-research-reset", GPIO_ACTIVE_HIGH);

static int read_equal(struct regmap *map, unsigned int reg, unsigned int expected)
{
	unsigned int value;
	int ret = regmap_read_bypassed(map, reg, &value);

	if (ret)
		return ret;
	if (value != expected) {
		pr_err("a1625_power_probe: reg=0x%x expected=0x%x actual=0x%x\n",
		       reg, expected, value);
		return -EIO;
	}
	return 0;
}

static int a1625_radio_pulse(bool pulse, int (*observe)(void *, struct gpio_desc *, struct regmap *), void *context)
{
	struct device_node *node;
	struct platform_device *gpio_dev;
	struct i2c_client *pmu;
	struct regmap *gpio_map, *pmu_map;
	struct gpio_desc *reset = NULL;
	unsigned int reset_saved, pmu_saved, clkreq;
	bool reset_touched = false, power_touched = false;
	bool safe_to_restore_reset = true;
	int ret = -ENODEV, rollback;

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
	gpio_dev = of_find_device_by_node(node);
	of_node_put(node);
	if (!gpio_dev)
		return -ENODEV;
	node = of_find_node_by_path("/soc/i2c@20a110000/pmic@74");
	if (!node) {
		put_device(&gpio_dev->dev);
		return -ENODEV;
	}
	if (!of_device_is_compatible(node, "apple,i2c-pmic")) {
		of_node_put(node);
		put_device(&gpio_dev->dev);
		return -ENODEV;
	}
	pmu = of_find_i2c_device_by_node(node);
	of_node_put(node);
	if (!pmu) {
		put_device(&gpio_dev->dev);
		return -ENODEV;
	}
	device_lock(&gpio_dev->dev);
	device_lock(&pmu->dev);
	if (!gpio_dev->dev.driver || !pmu->dev.driver || pmu->addr != 0x74)
		goto out;
	gpio_map = dev_get_regmap(&gpio_dev->dev, NULL);
	pmu_map = dev_get_regmap(&pmu->dev, NULL);
	if (!gpio_map || !pmu_map)
		goto out;
	/* Only the exact baseline established by the read-only probes is accepted. */
	ret = regmap_read(gpio_map, 4 * 77, &reset_saved);
	if (ret)
		goto out;
	ret = regmap_read(pmu_map, 0x406, &pmu_saved);
	if (ret)
		goto out;
	if (reset_saved != 0x76200 || pmu_saved != 0) {
		ret = -EBUSY;
		goto out;
	}
	ret = read_equal(gpio_map, 4 * 77, reset_saved);
	if (ret)
		goto out;
	ret = read_equal(gpio_map, 4 * 41, 0x76221);
	if (ret)
		goto out;
	ret = read_equal(gpio_map, 4 * 63, 0x72202);
	if (ret)
		goto out;
	if (!pulse) {
		pr_info("a1625_power_probe: baseline verified; pulse disabled; no writes\n");
		goto out;
	}
	/* Normal consumer acquisition must refuse a line already owned elsewhere. */
	reset_lookup.dev_id = dev_name(&pmu->dev);
	reset_lookup.table[0].key = dev_name(&gpio_dev->dev);
	gpiod_add_lookup_table(&reset_lookup);
	reset = gpiod_get(&pmu->dev, "a1625-research-reset", GPIOD_ASIS);
	gpiod_remove_lookup_table(&reset_lookup);
	if (IS_ERR(reset)) {
		ret = PTR_ERR(reset);
		reset = NULL;
		goto out;
	}
	reset_touched = true;
	ret = gpiod_direction_output_raw(reset, 0);
	if (ret)
		goto restore;
	ret = read_equal(gpio_map, 4 * 77, 0x76202);
	if (ret)
		goto restore;
	/* PERST remains asserted until the optional observer. The observer owns
	 * restoration of any link control and must reassert PERST before return.
	 */
	power_touched = true;
	ret = regmap_write(pmu_map, 0x406, 0x02);
	if (ret)
		goto restore;
	ret = read_equal(pmu_map, 0x406, 0x02);
	if (ret)
		goto restore;
	msleep(100);
	ret = read_equal(gpio_map, 4 * 77, 0x76202);
	if (ret)
		goto restore;
	ret = regmap_read_bypassed(gpio_map, 4 * 41, &clkreq);
	if (ret)
		goto restore;
	pr_info("a1625_power_probe: WL_REG_ON=0x02 PERST=0x76202 CLKREQ=0x%x; held 100ms\n",
		clkreq);
	if (!ret && observe)
		ret = observe(context, reset, gpio_map);
restore:
	if (power_touched) {
		rollback = regmap_write(pmu_map, 0x406, pmu_saved);
		if (!rollback)
			rollback = read_equal(pmu_map, 0x406, pmu_saved);
		if (rollback) {
			pr_err("a1625_power_probe: power rollback failed; PERST left held low\n");
			safe_to_restore_reset = false;
			ret = rollback;
		} else {
			msleep(100);
		}
	}
	if (reset_touched && safe_to_restore_reset) {
		rollback = regmap_write(gpio_map, 4 * 77, reset_saved);
		if (!rollback)
			rollback = read_equal(gpio_map, 4 * 77, reset_saved);
		if (rollback) {
			pr_err("a1625_power_probe: reset configuration rollback failed\n");
			ret = rollback;
		}
	}
	if (reset)
		gpiod_put(reset);
	if (!ret)
		pr_info("a1625_power_probe: rollback verified; WL_REG_ON=0x00 PERST=0x76200\n");
out:
	device_unlock(&pmu->dev);
	device_unlock(&gpio_dev->dev);
	put_device(&pmu->dev);
	put_device(&gpio_dev->dev);
	if (ret) {
		pr_err("a1625_power_probe: stopped: %d\n", ret);
		return ret;
	}
	return 0;
}
