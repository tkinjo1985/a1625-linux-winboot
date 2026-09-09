// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_PCIE_DOMAINS_H
#define A1625_PCIE_DOMAINS_H
#include <linux/device.h>
#include <linux/err.h>
#include <linux/mfd/syscon.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
/* Bounded power lifetime. The callback must remove every child and DMA client
 * before returning, including on failure. It runs before AUTO/power rollback.
 * This helper does not enable the PHY or register any PCI/DART devices.
 */
struct domain_probe {
	const char *path;
	unsigned int offset;
	struct platform_device *consumer;
	bool attached;
	bool resumed;
	bool forced;
	unsigned int saved_auto;
};

static int a1625_with_pcie_domains(bool cycle, bool force_active, int (*operate)(void *), void *context)
{
	struct domain_probe domains[] = {
		{ .path = "/soc/power-management@20e000000/power-controller@20308", .offset = 0x20308 },
		{ .path = "/soc/power-management@20e000000/power-controller@20310", .offset = 0x20310 },
		{ .path = "/soc/power-management@20e000000/power-controller@20220", .offset = 0x20220 },
	};
	struct of_phandle_args spec = { .args_count = 0 };
	struct device_node *node;
	struct regmap *map;
	unsigned int reg;
	int i, ret = 0, cleanup;

	if (!cycle && (force_active || operate))
		return -EINVAL;
	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;
	node = of_find_node_by_path("/soc/power-management@20e000000");
	if (!node)
		return -ENODEV;
	if (!of_device_is_compatible(node, "apple,t7000-pmgr")) {
		of_node_put(node);
		return -ENODEV;
	}
	map = syscon_node_to_regmap(node);
	of_node_put(node);
	if (IS_ERR(map))
		return PTR_ERR(map);
	for (i = 0; i < ARRAY_SIZE(domains); i++) {
		ret = regmap_read(map, domains[i].offset, &reg);
		if (ret)
			goto done;
		pr_info("a1625_pcie_domains: baseline offset=0x%x value=0x%08x\n",
			domains[i].offset, reg);
		/* Only cycle a domain which is off, without AUTO, RESET or DISABLE. */
		if (cycle && (reg & (0x900004ffU))) {
			ret = -EBUSY;
			goto done;
		}
	}
	if (!cycle)
		goto done;
	for (i = 0; i < ARRAY_SIZE(domains); i++) {
		spec.np = of_find_node_by_path(domains[i].path);
		if (!spec.np) {
			ret = -ENODEV;
			goto release;
		}
		if (!of_device_is_compatible(spec.np, "apple,t7000-pmgr-pwrstate")) {
			of_node_put(spec.np);
			ret = -ENODEV;
			goto release;
		}
		domains[i].consumer = platform_device_register_simple("a1625-pcie-domain-probe",
								     i, NULL, 0);
		if (IS_ERR(domains[i].consumer)) {
			ret = PTR_ERR(domains[i].consumer);
			domains[i].consumer = NULL;
			of_node_put(spec.np);
			goto release;
		}
		/* Provider lookup uses the node itself, not an invented DT phandle. */
		ret = of_genpd_add_device(&spec, &domains[i].consumer->dev);
		of_node_put(spec.np);
		if (ret)
			goto release;
		domains[i].attached = true;
		pm_runtime_enable(&domains[i].consumer->dev);
	}
	for (i = 0; i < ARRAY_SIZE(domains); i++) {
		ret = pm_runtime_resume_and_get(&domains[i].consumer->dev);
		if (ret < 0)
			goto release;
		domains[i].resumed = true;
		ret = regmap_read(map, domains[i].offset, &reg);
		if (ret)
			goto release;
		pr_info("a1625_pcie_domains: enabled offset=0x%x value=0x%08x\n",
			domains[i].offset, reg);
		if ((reg & 0xf) != 0xf || (reg & 0x80000400U)) {
			ret = -EIO;
			goto release;
		}
	}
	if (force_active) {
		for (i = 0; i < ARRAY_SIZE(domains); i++) {
			ret = regmap_read(map, domains[i].offset, &reg);
			if (ret)
				goto release;
			domains[i].saved_auto = reg & BIT(28);
			domains[i].forced = true;
			/* Match m1n1 PMGR active mode: suppress AUTO and clear history flags
			 * in the written value while preserving the requested active state.
			 */
			ret = regmap_update_bits(map, domains[i].offset,
						 BIT(28) | BIT(9) | BIT(8), 0);
			if (ret)
				goto release;
			ret = regmap_read_poll_timeout(map, domains[i].offset, reg,
						      (reg & 0xff) == 0xff, 10, 10000);
			pr_info("a1625_pcie_domains: forced-active offset=0x%x value=0x%08x result=%d\n",
				domains[i].offset, reg, ret);
			if (ret)
				goto release;
		}
	}
	if (operate)
		ret = operate(context);
release:
	for (i = ARRAY_SIZE(domains) - 1; i >= 0; i--) {
		if (!domains[i].consumer)
			continue;
		if (domains[i].forced) {
			cleanup = regmap_update_bits(map, domains[i].offset,
						     BIT(28) | BIT(9) | BIT(8), domains[i].saved_auto);
			if (cleanup)
				ret = cleanup;
		}
		if (domains[i].resumed) {
			cleanup = pm_runtime_put_sync_suspend(&domains[i].consumer->dev);
			if (cleanup < 0) {
				pr_err("a1625_pcie_domains: suspend failed offset=0x%x: %d\n",
					domains[i].offset, cleanup);
				ret = cleanup;
			}
		}
		if (domains[i].attached) {
			pm_runtime_disable(&domains[i].consumer->dev);
			cleanup = pm_genpd_remove_device(&domains[i].consumer->dev);
			if (cleanup) {
				pr_err("a1625_pcie_domains: detach failed; retained consumer %s: %d\n",
					dev_name(&domains[i].consumer->dev), cleanup);
				ret = cleanup;
				continue;
			}
		}
		platform_device_unregister(domains[i].consumer);
	}
	for (i = 0; i < ARRAY_SIZE(domains); i++) {
		cleanup = regmap_read(map, domains[i].offset, &reg);
		if (cleanup) {
			ret = cleanup;
			continue;
		}
		pr_info("a1625_pcie_domains: released offset=0x%x value=0x%08x\n",
			domains[i].offset, reg);
		/* History bits may change; target/actual and AUTO must be off again. */
		if (reg & 0x900004ffU)
			ret = -EIO;
	}
done:
	if (ret) {
		pr_err("a1625_pcie_domains: stopped: %d\n", ret);
		return ret;
	}
	pr_info("a1625_pcie_domains: domain callback complete; cycle=%u\n", cycle);
	return 0;
}
#endif
