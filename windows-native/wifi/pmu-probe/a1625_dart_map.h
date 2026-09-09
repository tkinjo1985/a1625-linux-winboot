// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_DART_MAP_H
#define A1625_DART_MAP_H
#include <linux/dma-mapping.h>
#include <linux/iommu.h>
#include <linux/mm.h>

/* Software page-table and hardware stream-enable check, not an endpoint DMA
 * transfer. The radio remains off throughout. Bus probe configures the normal
 * DMA domain; driver/device removal releases it before DART is removed.
 */
static int a1625_map_probe(struct platform_device *pdev)
{
	struct iommu_domain *domain = iommu_get_domain_for_dev(&pdev->dev);
	struct page *page;
	void __iomem *regs;
	dma_addr_t address;
	int *result = dev_get_platdata(&pdev->dev);
	int ret = -ENODEV;

	if (!domain || (domain->type != IOMMU_DOMAIN_DMA &&
			 domain->type != IOMMU_DOMAIN_DMA_FQ))
		goto out;
	pr_info("a1625_dart_map: aperture=%llx..%llx forced=%u\n",
		(unsigned long long)domain->geometry.aperture_start,
		(unsigned long long)domain->geometry.aperture_end,
		domain->geometry.force_aperture);
	regs = ioremap(0x602002000ULL, 0x100);
	if (!regs) {
		ret = -ENOMEM;
		goto out;
	}
	/* Only the Wi-Fi mapper's stream 0 may be enabled. */
	if (readl(regs + 0xc) != 0x80) {
		pr_err("a1625_dart_map: unexpected stream-enable register\n");
		goto unmap_regs;
	}
	page = alloc_page(GFP_KERNEL | __GFP_ZERO);
	if (!page) {
		ret = -ENOMEM;
		goto unmap_regs;
	}
	address = dma_map_page(&pdev->dev, page, 0, PAGE_SIZE, DMA_BIDIRECTIONAL);
	if (dma_mapping_error(&pdev->dev, address)) {
		ret = -EIO;
		goto free_page;
	}
	ret = address <= U32_MAX - (PAGE_SIZE - 1) &&
		address >= domain->geometry.aperture_start &&
		address + PAGE_SIZE - 1 <= domain->geometry.aperture_end &&
		iommu_iova_to_phys(domain, address) == page_to_phys(page) &&
		iommu_iova_to_phys(domain, address + PAGE_SIZE - 1) ==
			page_to_phys(page) + PAGE_SIZE - 1 ? 0 : -EIO;
	pr_info("a1625_dart_map: mapped IOVA=%llx result=%d\n",
		(unsigned long long)address, ret);
	dma_unmap_page(&pdev->dev, address, PAGE_SIZE, DMA_BIDIRECTIONAL);
	if (iommu_iova_to_phys(domain, address))
		ret = -EIO;
	pr_info("a1625_dart_map: stream0 TCR=0x80; 4K map/lookup/unmap result=%d; no endpoint DMA\n", ret);
free_page:
	__free_page(page);
unmap_regs:
	iounmap(regs);
out:
	*result = ret;
	return ret;
}

static struct platform_driver a1625_map_driver = {
	.probe = a1625_map_probe,
	.driver = { .name = "a1625-dart-map" },
};

static int a1625_dart_map(struct device *dart, void *context)
{
	struct of_changeset changes;
	struct device_node *node, *existing;
	struct platform_device *pdev = NULL;
	u32 spec[] = { 0xa1625001, 0 };
	int result = -ENODEV, ret, cleanup;
	bool applied = false, registered = false;

	if (PAGE_SIZE != 4096 || dart->of_node->phandle != spec[0])
		return -EINVAL;
	existing = of_find_node_by_path("/soc/a1625-dart-map");
	if (existing) {
		of_node_put(existing);
		return -EBUSY;
	}
	of_changeset_init(&changes);
	node = of_changeset_create_node(&changes, dart->of_node->parent, "a1625-dart-map");
	if (!node) {
		ret = -ENOMEM;
		goto destroy;
	}
	ret = of_changeset_add_prop_u32_array(&changes, node, "iommus", spec, 2);
	if (ret)
		goto destroy;
	of_node_set_flag(node, OF_POPULATED);
	ret = of_changeset_apply(&changes);
	if (ret)
		goto detach;
	applied = true;
	ret = platform_driver_register(&a1625_map_driver);
	if (ret)
		goto detach;
	registered = true;
	pdev = platform_device_alloc("a1625-dart-map", PLATFORM_DEVID_NONE);
	if (!pdev) {
		ret = -ENOMEM;
		goto detach;
	}
	pdev->dev.of_node = of_node_get(node);
	pdev->dev.coherent_dma_mask = DMA_BIT_MASK(32);
	pdev->dev.dma_mask = &pdev->dev.coherent_dma_mask;
	ret = platform_device_add_data(pdev, &result, sizeof(result));
	if (!ret)
		ret = platform_device_add(pdev);
	if (ret) {
		platform_device_put(pdev);
	} else {
		ret = *(int *)dev_get_platdata(&pdev->dev);
		if (!pdev->dev.driver)
			ret = ret ? ret : -ENODEV;
		platform_device_unregister(pdev);
		pr_info("a1625_dart_map: DMA client removed before DART teardown\n");
	}
detach:
	if (registered)
		platform_driver_unregister(&a1625_map_driver);
	if (applied) {
		cleanup = of_changeset_revert(&changes);
		if (cleanup)
			ret = cleanup;
	}
	if (!of_node_check_flag(node, OF_DETACHED)) {
		cleanup = of_detach_node(node);
		if (cleanup)
			ret = cleanup;
	}
	of_node_clear_flag(node, OF_POPULATED);
destroy:
	of_changeset_destroy(&changes);
	of_node_put(node);
	return ret;
}
#endif
