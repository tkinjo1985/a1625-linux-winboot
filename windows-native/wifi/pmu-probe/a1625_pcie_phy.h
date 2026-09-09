// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_PCIE_PHY_H
#define A1625_PCIE_PHY_H
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/i2c.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/of.h>
#include <linux/regmap.h>
/* Requires all three PCIe domains held by the caller. The callback must
 * finish child teardown before returning; MMIO and PHY are then restored.
 */
struct core_step {
	unsigned int offset, mask, bits, delay_us, saved;
};

static int radio_is_off(void)
{
	struct device_node *node;
	struct i2c_client *client;
	struct regmap *map;
	unsigned int value;
	int ret = -ENODEV;

	node = of_find_node_by_path("/soc/i2c@20a110000/pmic@74");
	if (!node)
		return ret;
	client = of_find_i2c_device_by_node(node);
	of_node_put(node);
	if (!client)
		return ret;
	device_lock(&client->dev);
	if (client->addr == 0x74 && client->dev.driver) {
		map = dev_get_regmap(&client->dev, NULL);
		if (map) {
			ret = regmap_read(map, 0x406, &value);
			if (!ret && value != 0)
				ret = -EBUSY;
		}
	}
	device_unlock(&client->dev);
	put_device(&client->dev);
	return ret;
}

static int a1625_with_pcie_phy(bool prepare_port, bool inspect_prefix,
			       bool test_refclk,
			       int (*operate)(void __iomem *port, void *context),
			       void *context)
{
	static const unsigned int core_offsets[] = {
		0x90, 0x100, 0x108, 0x10c, 0x118, 0x130, 0x134,
		0x180, 0x188, 0x18c, 0x198,
	};
	static const unsigned int port_offsets[] = { 0x80, 0x88, 0x124, 0x128 };
	/* T7000 shared PHY0 setup, then port1 internal enable.
	 * J42d has no apcie-common-tunables. Its apcie-config-tunables belong
	 * to PCI configuration space and MUST NOT be written to this block.
	 * Every changed mask is saved independently for reverse-order rollback.
	 * No LTSSM, endpoint power, PCI config, DART or MSI writes are performed.
	 */
	struct core_step steps[] = {
		{ 0x40, 1, 1 }, { 0x100, 1, 1 }, { 0x118, 1, 1 },
		{ 0x118, 1, 0 }, { 0x100, 1, 0 }, { 0x40, 1, 0 },
		{ 0x198, 1, 0 }, { 0x188, 1, 1, 100 },
		{ 0x18c, 1, 0 }, { 0x180, 1, 1, 100 },
		{ 0x198, 1, 1 }, { 0x860, ~0U, 3 }, { 0x188, 0x100, 0 },
	};
	void __iomem *core = NULL, *port = NULL;
	bool core_owned = false, port_owned = false;
	bool changed = false, restored = true;
	unsigned int i, value;
	int ret = -EBUSY;
	int applied = 0;

	if ((inspect_prefix && !prepare_port) || (test_refclk && !inspect_prefix))
		return -EINVAL;
	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;
	if (!request_mem_region(0x600000000ULL, 0x2000, "a1625-pcie-core-probe"))
		goto out;
	core_owned = true;
	if (!request_mem_region(0x602004000ULL, 0x1000, "a1625-pcie-port1-probe"))
		goto out;
	port_owned = true;
	core = ioremap(0x600000000ULL, 0x2000);
	port = ioremap(0x602004000ULL, 0x1000);
	if (!core || !port) {
		ret = -ENOMEM;
		goto out;
	}
	if (prepare_port) {
		ret = radio_is_off();
		if (ret)
			goto out;
		for (i = 0; i < ARRAY_SIZE(steps); i++) {
			if (inspect_prefix && i == 11) {
				if (!test_refclk)
					break;
				/* Keep the unresolved counter command out of this diagnostic.
				 * Replace it with the following ordinary clock control so
				 * the rollback stack stays contiguous.
				 */
				steps[i] = steps[i + 1];
			}
			if (inspect_prefix && i == 12)
				break;
			value = readl(core + steps[i].offset);
			if (value == ~0U) {
				ret = -ENODEV;
				goto out;
			}
			steps[i].saved = value & steps[i].mask;
			applied++;
			changed = true;
			writel((value & ~steps[i].mask) | steps[i].bits,
			       core + steps[i].offset);
			value = readl(core + steps[i].offset);
			if (value == ~0U || (value & steps[i].mask) != steps[i].bits) {
				pr_err("a1625_pcie_domains: internal step %u offset=0x%x mask=0x%x wanted=0x%x actual=0x%x\n",
					i, steps[i].offset, steps[i].mask, steps[i].bits, value);
				ret = -EIO;
				goto out;
			}
			if (steps[i].delay_us)
				udelay(steps[i].delay_us);
		}
		pr_info("a1625_pcie_domains: %u internal steps checked; prefix=%u; radio remains off\n",
			i, inspect_prefix);
	}
	for (i = 0; i < ARRAY_SIZE(core_offsets); i++) {
		value = readl(core + core_offsets[i]);
		pr_info("a1625_pcie_domains: core[0x%x]=0x%08x\n",
			core_offsets[i], value);
		if (value == ~0U) {
			ret = -ENODEV;
			goto out;
		}
	}
	for (i = 0; i < ARRAY_SIZE(port_offsets); i++) {
		value = readl(port + port_offsets[i]);
		pr_info("a1625_pcie_domains: port1[0x%x]=0x%08x\n",
			port_offsets[i], value);
		if (value == ~0U) {
			pr_err("a1625_pcie_domains: port1 inaccessible; do not decode status bits\n");
			ret = -ENODEV;
			goto out;
		}
	}
	ret = operate ? operate(port, context) : 0;
out:
	while (applied) {
		struct core_step *step = &steps[--applied];
		value = readl(core + step->offset);
		if (value == ~0U) {
			pr_err("a1625_pcie_domains: core inaccessible during rollback; no further writes\n");
			restored = false;
			ret = -EIO;
			break;
		}
		writel((value & ~step->mask) | step->saved, core + step->offset);
		value = readl(core + step->offset);
		if (value == ~0U || (value & step->mask) != step->saved) {
			pr_err("a1625_pcie_domains: internal rollback failed offset=0x%x\n", step->offset);
			restored = false;
			ret = -EIO;
		}
	}
	if (changed && restored)
		pr_info("a1625_pcie_domains: internal control masks restored\n");
	if (port)
		iounmap(port);
	if (core)
		iounmap(core);
	if (port_owned)
		release_mem_region(0x602004000ULL, 0x1000);
	if (core_owned)
		release_mem_region(0x600000000ULL, 0x2000);
	return ret;
}

#endif
