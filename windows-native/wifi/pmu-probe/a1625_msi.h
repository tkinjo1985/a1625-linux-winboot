// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_MSI_H
#define A1625_MSI_H
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/irqchip/irq-msi-lib.h>
#include <linux/msi.h>
#include <linux/atomic.h>

struct a1625_msi {
	struct irq_domain *domain;
	struct device_node *aic;
	struct fwnode_handle *fwnode;
	struct irq_fwspec spec;
	struct mutex lock;
	unsigned long used;
	atomic_t delivered[8];
};

static void a1625_msi_eoi(struct irq_data *data)
{
	struct a1625_msi *msi = irq_data_get_irq_chip_data(data);

	if (data->hwirq >= 8 && data->hwirq < 16)
		atomic_inc(&msi->delivered[data->hwirq - 8]);
	irq_chip_eoi_parent(data);
}

static void a1625_msi_compose(struct irq_data *data, struct msi_msg *msg)
{
	msg->address_hi = 0;
	msg->address_lo = 0xbffff000;
	msg->data = data->hwirq;
}

static struct irq_chip a1625_msi_chip = {
	.name = "A1625-MSI",
	.irq_mask = irq_chip_mask_parent,
	.irq_unmask = irq_chip_unmask_parent,
	.irq_eoi = a1625_msi_eoi,
	.irq_set_affinity = irq_chip_set_affinity_parent,
	.irq_set_type = irq_chip_set_type_parent,
	.irq_compose_msi_msg = a1625_msi_compose,
};

static int a1625_msi_alloc(struct irq_domain *domain, unsigned int virq,
			    unsigned int count, void *args)
{
	struct a1625_msi *msi = domain->host_data;
	struct irq_fwspec spec = msi->spec;
	int slot, ret;
	unsigned int i;

	if (!count || count > 8 || !is_power_of_2(count))
		return -EINVAL;
	mutex_lock(&msi->lock);
	slot = bitmap_find_free_region(&msi->used, 8, order_base_2(count));
	mutex_unlock(&msi->lock);
	if (slot < 0)
		return slot;
	spec.param[1] = 232 + slot;
	ret = irq_domain_alloc_irqs_parent(domain, virq, count, &spec);
	if (ret) {
		mutex_lock(&msi->lock);
		bitmap_release_region(&msi->used, slot, order_base_2(count));
		mutex_unlock(&msi->lock);
		return ret;
	}
	for (i = 0; i < count; i++)
		irq_domain_set_hwirq_and_chip(domain, virq + i, 8 + slot + i,
					      &a1625_msi_chip, msi);
	return 0;
}

static void a1625_msi_free(struct irq_domain *domain, unsigned int virq,
			    unsigned int count)
{
	struct a1625_msi *msi = domain->host_data;
	unsigned int i;

	for (i = 0; i < count; i++) {
		struct irq_data *data = irq_domain_get_irq_data(domain, virq + i);
		mutex_lock(&msi->lock);
		clear_bit(data->hwirq - 8, &msi->used);
		mutex_unlock(&msi->lock);
	}
	irq_domain_free_irqs_parent(domain, virq, count);
	for (i = 0; i < count; i++)
		irq_domain_reset_irq_data(irq_domain_get_irq_data(domain, virq + i));
}

static const struct irq_domain_ops a1625_msi_ops = {
	.alloc = a1625_msi_alloc,
	.free = a1625_msi_free,
};

static const struct msi_parent_ops a1625_msi_parent_ops = {
	.supported_flags = MSI_GENERIC_FLAGS_MASK | MSI_FLAG_PCI_MSIX | MSI_FLAG_MULTI_PCI_MSI,
	.required_flags = MSI_FLAG_USE_DEF_DOM_OPS | MSI_FLAG_USE_DEF_CHIP_OPS | MSI_FLAG_PCI_MSI_MASK_PARENT,
	.chip_flags = MSI_CHIP_FLAG_SET_EOI,
	.bus_select_token = DOMAIN_BUS_PCI_MSI,
	.init_dev_msi_info = msi_lib_init_dev_msi_info,
};

/* Radio off, inside the established T7000 power/PHY lifetime. This tests
 * allocation and composition, not activation or interrupt delivery.
 */
static int a1625_with_msi(void __iomem *port,
			   int (*operate)(struct irq_domain *, void *), void *context)
{
	struct a1625_msi msi = {};
	struct irq_domain_info info = { .size = 16, .ops = &a1625_msi_ops, .host_data = &msi };
	unsigned int irqs[8] = {}, i;
	u32 control = readl(port + 0x124), base = readl(port + 0x128);
	int ret = -ENODEV;
	bool touched = false;

	if (!of_device_is_compatible(of_root, "apple,j42d") ||
	    !of_device_is_compatible(of_root, "apple,t7000") || control || base)
		return -EBUSY;
	msi.aic = of_find_node_by_path("/soc/interrupt-controller@20e100000");
	if (!msi.aic || !of_device_is_compatible(msi.aic, "apple,aic"))
		goto out;
	msi.spec.fwnode = of_fwnode_handle(msi.aic);
	msi.spec.param_count = 3;
	msi.spec.param[0] = 0;
	msi.spec.param[1] = 232;
	msi.spec.param[2] = IRQ_TYPE_EDGE_RISING;
	info.parent = irq_find_matching_fwspec(&msi.spec, DOMAIN_BUS_WIRED);
	if (!info.parent)
		goto out;
	for (i = 0; i < 8; i++)
		if (irq_find_mapping(info.parent, 0x10000 | (232 + i))) {
			ret = -EBUSY;
			goto out;
		}
	msi.fwnode = irq_domain_alloc_named_fwnode("a1625-msi-probe");
	if (!msi.fwnode) {
		ret = -ENOMEM;
		goto out;
	}
	info.fwnode = msi.fwnode;
	mutex_init(&msi.lock);
	for (i = 0; i < 8; i++)
		atomic_set(&msi.delivered[i], 0);
	msi.domain = msi_create_parent_irq_domain(&info, &a1625_msi_parent_ops);
	if (!msi.domain) {
		ret = -ENOMEM;
		goto out;
	}
	touched = true;
	writel(0x31, port + 0x124);
	writel(0x00080008, port + 0x128);
	if (readl(port + 0x124) != 0x31 || readl(port + 0x128) != 0x00080008) {
		ret = -EIO;
		goto out;
	}
	for (i = 0; i < 8; i++) {
		struct irq_data *data;
		struct msi_msg message = {};
		int irq = irq_domain_alloc_irqs(msi.domain, 1, NUMA_NO_NODE, NULL);
		if (irq < 0) {
			ret = irq;
			goto out;
		}
		irqs[i] = irq;
		data = irq_domain_get_irq_data(msi.domain, irq);
		if (!data || !data->parent_data) {
			ret = -ENODEV;
			goto out;
		}
		a1625_msi_compose(data, &message);
		if (data->hwirq != 8 + i || data->parent_data->hwirq != (0x10000 | (232 + i)) ||
		    message.address_hi || message.address_lo != 0xbffff000 || message.data != 8 + i) {
			ret = -EIO;
			goto out;
		}
		pr_info("a1625_msi: message=%u parent-index=%u allocation verified\n", message.data, 232 + i);
	}
	ret = 0;
	for (i = 0; i < 8; i++) {
		irq_domain_free_irqs(irqs[i], 1);
		irqs[i] = 0;
	}
	if (operate)
		ret = operate(msi.domain, context);
out:
	for (i = 0; i < 8; i++)
		if (irqs[i])
			irq_domain_free_irqs(irqs[i], 1);
	if (msi.domain) {
		if (msi.used)
			ret = -EIO;
		for (i = 0; i < 8; i++)
			if (irq_find_mapping(info.parent, 0x10000 | (232 + i)))
				ret = -EIO;
		irq_domain_remove(msi.domain);
		for (i = 0; i < 8; i++)
			pr_info("a1625_msi: message=%u EOI count=%d\n", 8 + i,
				atomic_read(&msi.delivered[i]));
	}
	if (touched) {
		writel(control, port + 0x124);
		writel(base, port + 0x128);
		if (readl(port + 0x124) != control || readl(port + 0x128) != base)
			ret = -EIO;
	}
	if (msi.fwnode)
		irq_domain_free_fwnode(msi.fwnode);
	of_node_put(msi.aic);
	pr_info("a1625_msi: domains/IRQs removed and port restored result=%d\n", ret);
	return ret;
}

static int a1625_msi_probe(void __iomem *port)
{
	return a1625_with_msi(port, NULL, NULL);
}
#endif
