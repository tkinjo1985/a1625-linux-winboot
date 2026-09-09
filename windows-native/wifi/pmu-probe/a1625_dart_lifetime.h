// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_DART_LIFETIME_H
#define A1625_DART_LIFETIME_H
#include <linux/device.h>
#include <linux/device/driver.h>
#include <linux/string.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>

/* Call only inside the verified power + PHY lifetime, with the radio off.
 * This registers the real DART driver and therefore resets its registers.
 * The callback must remove all IOMMU clients before returning. No DMA client
 * is created here. The packed-TCR fix must be in the running kernel before
 * a callback is permitted to attach a client.
 */
static int a1625_with_dart(int (*operate)(struct device *, void *), void *context,
			  bool test_dma_range)
{
	const char *compat[] = { "apple,t7000-dart", "apple,s5l8960x-dart" };
	u32 reg[] = { 6, 0x02002000, 0, 0x2000 };
	u32 irq[] = { 0, 216, 4 };
	/* Opt-in experiment: PCI DMA bfffe000 was mapped while this T7000
	 * reported a missing PMD at 3fffe000. Use the driver's existing S5L
	 * range/mask mechanism, without modifying hardware translation logic.
	 */
	u32 dma_range[] = { 0, 0x80000000, 0, 0x40000000 };
	struct device_node *soc = NULL, *aic = NULL, *node = NULL, *existing;
	struct platform_device *pdev = NULL;
	struct of_changeset changes;
	struct resource resource;
	bool applied = false;
	int ret, cleanup;

	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000"))
		return -ENODEV;
	existing = of_find_node_by_path("/soc/iommu@602002000");
	if (existing) {
		of_node_put(existing);
		return -EBUSY;
	}
	soc = of_find_node_by_path("/soc");
	aic = of_find_node_by_path("/soc/interrupt-controller@20e100000");
	if (!soc || !aic || !aic->phandle ||
	    !of_device_is_compatible(aic, "apple,aic")) {
		ret = -ENODEV;
		goto put_parents;
	}
	of_changeset_init(&changes);
	node = of_changeset_create_node(&changes, soc, "iommu@602002000");
	if (!node) {
		ret = -ENOMEM;
		goto destroy;
	}
	ret = of_changeset_add_prop_string_array(&changes, node, "compatible",
						compat, ARRAY_SIZE(compat));
	if (!ret)
		ret = of_changeset_add_prop_u32_array(&changes, node, "reg", reg, ARRAY_SIZE(reg));
	if (!ret)
		ret = of_changeset_add_prop_u32(&changes, node, "interrupt-parent", aic->phandle);
	if (!ret)
		ret = of_changeset_add_prop_u32_array(&changes, node, "interrupts", irq, ARRAY_SIZE(irq));
	if (!ret)
		ret = of_changeset_add_prop_u32(&changes, node, "#iommu-cells", 1);
	if (!ret && test_dma_range)
		ret = of_changeset_add_prop_u32_array(&changes, node,
			"apple,dma-range", dma_range, ARRAY_SIZE(dma_range));
	if (!ret && operate) {
		existing = of_find_node_by_phandle(0xa1625001);
		if (existing) {
			of_node_put(existing);
			ret = -EBUSY;
		} else {
			ret = of_changeset_add_prop_u32(&changes, node, "phandle", 0xa1625001);
		}
	}
	if (ret)
		goto destroy;
	/* create_node queues ATTACH first, but OF caches the phandle only at
	 * attachment. Apply properties while detached, then attach; reversal
	 * consequently detaches before removing those properties.
	 */
	if (operate)
		list_move_tail(changes.entries.next, &changes.entries);
	/* Suppress automatic population: retain an explicit device reference so
	 * driver teardown precedes changeset removal even if reverting fails.
	 */
	of_node_set_flag(node, OF_POPULATED);
	ret = of_changeset_apply(&changes);
	if (ret)
		goto clear_flag;
	applied = true;
	ret = of_address_to_resource(node, 0, &resource);
	if (ret || resource.start != 0x602002000ULL || resource_size(&resource) != 0x2000) {
		ret = ret ? ret : -EINVAL;
		goto clear_flag;
	}
	of_node_clear_flag(node, OF_POPULATED);
	pdev = of_platform_device_create(node, "a1625-dart-lifetime", NULL);
	if (!pdev) {
		ret = -ENODEV;
		goto clear_flag;
	}
	device_lock(&pdev->dev);
	ret = pdev->dev.driver && !strcmp(pdev->dev.driver->name, "apple-dart") ? 0 : -ENODEV;
	device_unlock(&pdev->dev);
	if (!ret) {
		pr_info("a1625_dart: driver bound while PCIe power and PHY are held\n");
		if (operate)
			ret = operate(&pdev->dev, context);
	}
	platform_device_unregister(pdev);
	pr_info("a1625_dart: platform device removed before PHY teardown\n");
clear_flag:
	/* Keep automatic population suppressed throughout error recovery. */
	of_node_set_flag(node, OF_POPULATED);
	if (applied) {
		cleanup = of_changeset_revert(&changes);
		if (cleanup) {
			pr_err("a1625_dart: changeset revert failed: %d\n", cleanup);
			ret = cleanup;
		}
	}
	/* An apply notifier can fail after entries have already been applied;
	 * the changeset API does not guarantee rollback in that case. This is
	 * our newly created, childless node, so explicitly detach any remainder.
	 * Its platform device has already been unregistered above.
	 */
	if (!of_node_check_flag(node, OF_DETACHED)) {
		cleanup = of_detach_node(node);
		if (cleanup)
			ret = cleanup;
	}
	of_node_clear_flag(node, OF_POPULATED);
destroy:
	of_changeset_destroy(&changes);
	of_node_put(node);
put_parents:
	of_node_put(aic);
	of_node_put(soc);
	return ret;
}
#endif
