// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_PCI_SCAN_H
#define A1625_PCI_SCAN_H
#include <linux/sched/signal.h>
#include <linux/netdevice.h>
#include <net/net_namespace.h>
#include <linux/pci.h>
#include <linux/iommu.h>
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/mm.h>
#include "a1625_pci_node.h"

struct a1625_scan_control {
	u16 where;
	u8 bus, size;
	u32 saved, mask;
};

struct a1625_scan {
	void __iomem *rc, *ep;
	bool rejected;
	unsigned int devices;
	struct a1625_scan_control controls[26];
	unsigned int nr_controls;
	bool require_iommu;
	struct irq_domain *msi_domain;
	int msi_cap;
	bool msi_64;
	bool assign_memory;
	bool bind_firmware, firmware_active;
	unsigned int hold_seconds;
	bool hold_until_signal;
};

static int a1625_scan_cap(void __iomem *cfg, unsigned int id)
{
	unsigned int pos = readb(cfg + PCI_CAPABILITY_LIST), count;

	for (count = 0; count < 48 && pos; count++) {
		if (pos < 0x40 || pos > 0xfc || (pos & 3))
			return -EINVAL;
		if (readb(cfg + pos) == id)
			return pos;
		pos = readb(cfg + pos + 1);
	}
	return -ENOENT;
}

static int a1625_scan_extcap(void __iomem *cfg, unsigned int id)
{
	unsigned int pos = 0x100, count;
	u32 header;

	for (count = 0; count < 256 && pos; count++) {
		if (pos < 0x100 || pos > 0xffc || (pos & 3))
			return -EINVAL;
		header = readl(cfg + pos);
		if (!header || header == ~0U)
			break;
		if (PCI_EXT_CAP_ID(header) == id)
			return pos;
		pos = PCI_EXT_CAP_NEXT(header);
	}
	return -ENOENT;
}

static void a1625_scan_save_control(struct a1625_scan *scan, unsigned int bus,
				      unsigned int where, unsigned int size, u32 mask)
{
	struct a1625_scan_control *control = &scan->controls[scan->nr_controls++];
	void __iomem *cfg = bus ? scan->ep : scan->rc;

	control->bus = bus;
	control->where = where;
	control->size = size;
	control->mask = mask;
	control->saved = (size == 2 ? readw(cfg + where) : readl(cfg + where)) & mask;
}

static int a1625_scan_save_controls(struct a1625_scan *scan)
{
	unsigned int bus;
	int pm, exp, l1ss;

	for (bus = 0; bus < 2; bus++) {
		void __iomem *cfg = bus ? scan->ep : scan->rc;
		pm = a1625_scan_cap(cfg, PCI_CAP_ID_PM);
		exp = a1625_scan_cap(cfg, PCI_CAP_ID_EXP);
		l1ss = a1625_scan_extcap(cfg, PCI_EXT_CAP_ID_L1SS);
		if (pm < 0 || exp < 0 || l1ss < 0 || exp + PCI_EXP_DEVCTL2 > 0xfe || l1ss + PCI_L1SS_CTL2 > 0xffc)
			return -ENODEV;
		if (readw(cfg + pm + PCI_PM_CTRL) & PCI_PM_CTRL_STATE_MASK)
			return -EBUSY;
		pr_info("a1625_pci_scan: bus=%u PM=%x PCIe=%x L1SS=%x\n", bus, pm, exp, l1ss);
		/* PM status is W1C; link retrain is a self-clearing command. Neither
		 * is replayed during restore. All accesses preserve register width.
		 */
		a1625_scan_save_control(scan, bus, pm + PCI_PM_CTRL, 2, 0xffff & ~PCI_PM_CTRL_PME_STATUS);
		a1625_scan_save_control(scan, bus, exp + PCI_EXP_DEVCTL2, 2, 0xffff);
		a1625_scan_save_control(scan, bus, exp + PCI_EXP_LNKCTL, 2, 0xffff & ~PCI_EXP_LNKCTL_RL);
		a1625_scan_save_control(scan, bus, l1ss + PCI_L1SS_CTL1, 4, ~0U);
		a1625_scan_save_control(scan, bus, l1ss + PCI_L1SS_CTL2, 4, ~0U);
	}
	a1625_scan_save_control(scan, 0, PCI_IO_BASE, 2, 0xffff);
	a1625_scan_save_control(scan, 0, PCI_PREF_MEMORY_BASE, 4, ~0U);
	if (scan->assign_memory) {
		a1625_scan_save_control(scan, 0, PCI_MEMORY_BASE, 4, ~0U);
		a1625_scan_save_control(scan, 0, PCI_PREF_BASE_UPPER32, 4, ~0U);
		a1625_scan_save_control(scan, 0, PCI_PREF_LIMIT_UPPER32, 4, ~0U);
		a1625_scan_save_control(scan, 0, PCI_IO_BASE_UPPER16, 4, ~0U);
	}
	if (scan->msi_domain) {
		u16 flags;
		scan->msi_cap = a1625_scan_cap(scan->ep, PCI_CAP_ID_MSI);
		if (scan->msi_cap < 0 || scan->msi_cap > 0xe8)
			return -ENODEV;
		flags = readw(scan->ep + scan->msi_cap + PCI_MSI_FLAGS);
		if (flags & PCI_MSI_FLAGS_ENABLE)
			return -EBUSY;
		scan->msi_64 = !!(flags & PCI_MSI_FLAGS_64BIT);
		a1625_scan_save_control(scan, 1, scan->msi_cap + PCI_MSI_FLAGS, 2, 0xffff);
		a1625_scan_save_control(scan, 1, scan->msi_cap + PCI_MSI_ADDRESS_LO, 4, ~0U);
		if (scan->msi_64)
			a1625_scan_save_control(scan, 1, scan->msi_cap + PCI_MSI_ADDRESS_HI, 4, ~0U);
		a1625_scan_save_control(scan, 1, scan->msi_cap + (scan->msi_64 ? PCI_MSI_DATA_64 : PCI_MSI_DATA_32), 2, 0xffff);
		if (flags & PCI_MSI_FLAGS_MASKBIT)
			a1625_scan_save_control(scan, 1, scan->msi_cap + (scan->msi_64 ? PCI_MSI_MASK_64 : PCI_MSI_MASK_32), 4, ~0U);
	}
	if (scan->bind_firmware) {
		/* Additional controls touched by brcmfmac's rev <=13 watchdog
		 * replay through BAR-mapped CONFIGADDR/CONFIGDATA, plus BAR0 window.
		 * Command, PM, MSI and L1SS controls are already covered above.
		 * Link status is not a restorable control: retain only its low word.
		 */
		a1625_scan_save_control(scan, 1, 0x80, 4, ~0U);
		a1625_scan_save_control(scan, 1, 0xdc, 2, 0xffff);
		a1625_scan_save_control(scan, 1, 0x228, 4, ~0U);
		a1625_scan_save_control(scan, 1, 0x4e0, 4, ~0U);
		a1625_scan_save_control(scan, 1, 0x4f4, 4, ~0U);
	}
	return 0;
}

static void __iomem *a1625_scan_config(struct pci_bus *bus, unsigned int devfn)
{
	struct a1625_scan *scan = bus->sysdata;

	if (bus->number == 0 && devfn == PCI_DEVFN(1, 0))
		return scan->rc;
	if (bus->number == 1 && devfn == PCI_DEVFN(0, 0))
		return scan->ep;
	return NULL;
}

static int a1625_scan_read(struct pci_bus *bus, unsigned int devfn,
			    int where, int size, u32 *value)
{
	void __iomem *cfg = a1625_scan_config(bus, devfn);

	*value = ~0U;
	if (!cfg)
		return PCIBIOS_DEVICE_NOT_FOUND;
	if (where < 0 || where + size > 4096 ||
	    (size != 1 && size != 2 && size != 4) || (where & (size - 1)))
		return PCIBIOS_BAD_REGISTER_NUMBER;
	*value = size == 4 ? readl(cfg + where) :
		 size == 2 ? readw(cfg + where) : readb(cfg + where);
	return PCIBIOS_SUCCESSFUL;
}

static int a1625_scan_write(struct pci_bus *bus, unsigned int devfn,
			     int where, int size, u32 value)
{
	struct a1625_scan *scan = bus->sysdata;
	void __iomem *cfg = a1625_scan_config(bus, devfn);
	bool allowed;
	unsigned int i;

	if (!cfg)
		return PCIBIOS_DEVICE_NOT_FOUND;
	/* Scan may size BARs and set bridge bus numbers. Do not permit command
	 * dword writes (status is W1C), bus mastering, MSI, or unlisted controls.
	 * Unexpected writes fail closed and are reported after core teardown.
	 */
	allowed = where == PCI_COMMAND && size == 2 &&
		(!(value & PCI_COMMAND_MASTER) || scan->firmware_active);
	if (size == 4 && where >= 0x10 && where <= (bus->number ? 0x24 : 0x14) && !(where & 3))
		allowed = true;
	if (bus->number == 0 && where == PCI_PRIMARY_BUS && size == 4)
		allowed = (value & 0xffffff) == 0x010100 || !(value & 0xffffff);
	if (bus->number == 0 && where == PCI_BRIDGE_CONTROL && size == 2)
		allowed = !(value & PCI_BRIDGE_CTL_BUS_RESET);
	/* ROM BAR sizing is decoded off, with only the original enable bit 0. */
	if (where == (bus->number ? PCI_ROM_ADDRESS : PCI_ROM_ADDRESS1) && size == 4)
		allowed = !(value & PCI_ROM_ADDRESS_ENABLE);
	for (i = 0; i < scan->nr_controls; i++) {
		struct a1625_scan_control *control = &scan->controls[i];
		if (control->bus != bus->number || control->where != where || control->size != size)
			continue;
		allowed = true;
		if (control->mask == (0xffff & ~PCI_PM_CTRL_PME_STATUS))
			allowed = !(value & PCI_PM_CTRL_STATE_MASK);
		if (control->mask == (0xffff & ~PCI_EXP_LNKCTL_RL))
			allowed = !(value & PCI_EXP_LNKCTL_LD);
	}
	if (bus->number == 1 && scan->firmware_active) {
		if (where == 0x80 && size == 4)
			allowed = !(value & 0xfff) && value >= 0x18000000 && value <= 0x1810f000;
		/* Driver writes the link control/status dword to change ASPM.
		 * Preserve status by issuing just the control word (no W1C replay).
		 */
		if (where == 0xbc && size == 4) {
			allowed = !(value & PCI_EXP_LNKCTL_LD);
			size = 2;
			value &= 0xffff;
		}
		/* SBMBX is a command, never saved or replayed by host cleanup. */
		if (where == 0x98 && size == 4)
			allowed = value == 1;
	}
	/* Core scan acknowledges stale bridge errors; this is W1C, not a
	 * restorable control value. No device DMA has been enabled.
	 */
	if (bus->number == 0 && where == PCI_SEC_STATUS && size == 2 && value == 0xffff)
		allowed = true;
	pr_info("a1625_pci_scan: write bus=%u offset=%x size=%d value=%08x allowed=%u\n",
		bus->number, where, size, value, allowed);
	if (!allowed) {
		scan->rejected = true;
		return PCIBIOS_SET_FAILED;
	}
	if (size == 2)
		writew(value, cfg + where);
	else
		writel(value, cfg + where);
	return PCIBIOS_SUCCESSFUL;
}

static struct pci_ops a1625_scan_ops = {
	.read = a1625_scan_read,
	.write = a1625_scan_write,
};

static int a1625_scan_endpoint_msi(struct pci_dev *dev, struct a1625_scan *scan)
{
	struct irq_data *data;
	int ret, irq;
	u16 flags;

	ret = pci_alloc_irq_vectors(dev, 1, 1, PCI_IRQ_MSI);
	if (ret < 0)
		return ret;
	irq = pci_irq_vector(dev, 0);
	data = irq >= 0 ? irq_domain_get_irq_data(scan->msi_domain, irq) : NULL;
	flags = readw(scan->ep + scan->msi_cap + PCI_MSI_FLAGS);
	ret = data && data->parent_data && data->hwirq == 8 &&
		data->parent_data->hwirq == 0x100e8 &&
		(flags & PCI_MSI_FLAGS_ENABLE) && !(flags & PCI_MSI_FLAGS_QSIZE) &&
		readl(scan->ep + scan->msi_cap + PCI_MSI_ADDRESS_LO) == 0xbffff000 &&
		(!scan->msi_64 || !readl(scan->ep + scan->msi_cap + PCI_MSI_ADDRESS_HI)) &&
		readw(scan->ep + scan->msi_cap + (scan->msi_64 ? PCI_MSI_DATA_64 : PCI_MSI_DATA_32)) == 8 ? 0 : -EIO;
	pci_free_irq_vectors(dev);
	if (readw(scan->ep + scan->msi_cap + PCI_MSI_FLAGS) & PCI_MSI_FLAGS_ENABLE)
		ret = -EIO;
	pr_info("a1625_pci_scan: endpoint MSI address/data/route verified and disabled result=%d; no IRQ requested\n", ret);
	return ret;
}

static int a1625_scan_identify(struct pci_dev *dev, void *data)
{
	struct a1625_scan *scan = data;
	bool root = dev->bus->number == 0 && dev->devfn == PCI_DEVFN(1, 0) &&
		dev->vendor == 0x106b && dev->device == 0x1002 && dev->class == 0x060400;
	bool radio = dev->bus->number == 1 && dev->devfn == 0 &&
		dev->vendor == 0x14e4 && dev->device == 0x43a3 && dev->class == 0x028000;

	pr_info("a1625_pci_scan: Linux device %s vendor=%04x device=%04x class=%06x\n",
		pci_name(dev), dev->vendor, dev->device, dev->class);
	scan->devices++;
	if (!root && !radio)
		scan->rejected = true;
	if (dev->dev.driver || (readw((radio ? scan->ep : scan->rc) + PCI_COMMAND) & PCI_COMMAND_MASTER))
		scan->rejected = true;
	if (radio && scan->require_iommu) {
		struct iommu_domain *domain = iommu_get_domain_for_dev(&dev->dev);
		struct iommu_resv_region *region;
		void __iomem *regs;
		LIST_HEAD(regions);
		bool reserved = false;

		if (!domain || (domain->type != IOMMU_DOMAIN_DMA && domain->type != IOMMU_DOMAIN_DMA_FQ)) {
			scan->rejected = true;
			return -ENODEV;
		}
		iommu_get_resv_regions(&dev->dev, &regions);
		list_for_each_entry(region, &regions, list)
			if (region->start == 0xbffff000 && region->length == 4096 && region->type == IOMMU_RESV_MSI)
				reserved = true;
		iommu_put_resv_regions(&dev->dev, &regions);
		regs = ioremap(0x602002000ULL, 0x100);
		if (!regs || !reserved || readl(regs + 0xc) != 0x80)
			scan->rejected = true;
		if (regs)
			iounmap(regs);
		pr_info("a1625_pci_scan: endpoint translated domain, MSI reservation=%u stream0 check=%u; no DMA started\n",
			reserved, !scan->rejected);
	}
	/* A standalone MSI allocation leaves managed per-device MSI metadata
	 * even after vectors are freed. Driver core requires an empty devres
	 * list before probing. The firmware driver must make its own first
	 * allocation; the separate MSI diagnostic already validates this path.
	 */
	if (radio && scan->msi_domain && !scan->bind_firmware && !scan->rejected && a1625_scan_endpoint_msi(dev, scan))
		scan->rejected = true;
	if (radio && scan->assign_memory) {
		unsigned int bar;
		for (bar = 0; bar <= 2; bar += 2) {
			struct resource *resource = &dev->resource[bar];
			resource_size_t expected = bar ? 0x400000 : 0x8000;
			if (!resource->parent || !(resource->flags & IORESOURCE_MEM) ||
			    (resource->flags & IORESOURCE_UNSET) || resource_size(resource) != expected ||
			    resource->start < 0x7c0000000ULL || resource->end > 0x7ffffffffULL)
				scan->rejected = true;
			pr_info("a1625_pci_scan: BAR%u assigned CPU=%llx size=%llx\n",
				bar, (unsigned long long)resource->start, (unsigned long long)resource_size(resource));
		}
	}
	return root || radio ? 0 : -ENODEV;
}

static int a1625_scan_fault_tables(struct pci_dev *dev)
{
	struct iommu_domain *domain = iommu_get_domain_for_dev(&dev->dev);
	void __iomem *regs = ioremap(0x602002000ULL, 0x100);
	unsigned int attempt, table;
	u32 error = 0, address;

	if (!regs)
		return -ENOMEM;
	/* Caller retains the PCI device, domain and all root tables. Do not
	 * follow leaf pointers: firmware cleanup can unmap them concurrently.
	 * This observes CPU-visible entries, not the DART's cache contents.
	 */
	for (attempt = 0; attempt < 2000; attempt++) {
		error = readl(regs + 0x10);
		if (error & BIT(31))
			break;
		msleep(10);
	}
	if (error & BIT(31)) {
		address = readl(regs + 0x1c);
		pr_info("a1625_pci_scan: live fault error=%08x address=%08x\n", error, address);
		for (table = 0; table < 4; table++) {
			unsigned long candidate = (address & 0x3fffffffUL) |
				((unsigned long)table << 30);
			phys_addr_t translated = domain ?
				iommu_iova_to_phys(domain, candidate) : 0;
			u32 ttbr = readl(regs + 0x40 + 4 * table);
			phys_addr_t base = (phys_addr_t)(ttbr & 0xffffff) << 12;
			unsigned int index = (address >> 21) & 0x1ff;
			u64 *entry;

			pr_info("a1625_pci_scan: live candidate=%08lx mapped=%u\n",
				candidate, !!translated);
			if (!(ttbr & BIT(31)) || !pfn_valid(PHYS_PFN(base)))
				continue;
			entry = (u64 *)phys_to_virt(base) + index;
			pr_info("a1625_pci_scan: live root=%u index=%u entry=%016llx\n",
				table, index, (unsigned long long)READ_ONCE(*entry));
		}
	} else {
		pr_info("a1625_pci_scan: no DART fault observed in bounded window\n");
	}
	iounmap(regs);
	return 0;
}

static int a1625_hold_wifi(struct pci_dev *dev, unsigned int seconds, bool until_signal)
{
	struct net_device *netdev;
	void __iomem *regs;
	unsigned long deadline;
	int ret = 0;

	if (!seconds && !until_signal)
		return 0;
	netdev = dev_get_by_name(&init_net, "wlan0");
	if (!netdev)
		return -ENODEV;
	if (netdev->dev.parent != &dev->dev)
		ret = -ENODEV;
	dev_put(netdev);
	if (ret)
		return ret;
	regs = ioremap(0x602002000ULL, 0x100);
	if (!regs)
		return -ENOMEM;
	deadline = jiffies + seconds * HZ;
	pr_info("a1625_pci_scan: Wi-Fi hold begins seconds=%u until_signal=%u; signal runner to clean up\n", seconds, until_signal);
	while (until_signal || time_before(jiffies, deadline)) {
		bool bound;
		if (signal_pending(current))
			break;
		device_lock(&dev->dev);
		bound = !!dev->dev.driver;
		device_unlock(&dev->dev);
		if (!bound || (readl(regs + 0x10) & BIT(31))) {
			ret = -EIO;
			break;
		}
		msleep_interruptible(100);
	}
	pr_info("a1625_pci_scan: Wi-Fi hold ended signal=%u result=%d; cleaning up\n",
		!!signal_pending(current), ret);
	iounmap(regs);
	return ret;
}

static int a1625_scan_firmware(struct pci_bus *root, struct a1625_scan *scan)
{
	struct pci_bus *child = pci_find_bus(pci_domain_nr(root), 1);
	struct pci_dev *dev;
	void __iomem *dart_regs;
	int ret;

	if (!child || !scan->require_iommu || !scan->msi_domain ||
	    !scan->assign_memory || scan->rejected)
		return -EINVAL;
	dev = pci_get_slot(child, PCI_DEVFN(0, 0));
	if (!dev)
		return -ENODEV;
	ret = device_set_driver_override(&dev->dev, "brcmfmac");
	if (ret)
		goto put;
	scan->firmware_active = true;
	/* Add only the checked endpoint. All caller-owned PCI/DART/MSI/power
	 * objects remain alive through driver removal and firmware completion.
	 */
	pci_bus_add_device(dev);
	ret = device_attach(&dev->dev);
	if (ret < 0)
		goto detach;
	pr_info("a1625_pci_scan: firmware observation begins; attach=%d\n", ret);
	ret = a1625_scan_fault_tables(dev);
	device_lock(&dev->dev);
	pr_info("a1625_pci_scan: firmware observation ends; bound=%u\n",
		!!dev->dev.driver);
	device_unlock(&dev->dev);
	/* The bounded observation window is not a completion fence.
	 * The verified patched brcmfmac remove waits for fw_setup_done.
	 * It can wait longer when the firmware loader is still outstanding.
	 */
	if (!ret)
		ret = a1625_hold_wifi(dev, scan->hold_seconds, scan->hold_until_signal);
	detach:
	device_release_driver(&dev->dev);
	/* Keep the translated PCI client and DART alive for this snapshot.
	 * Once PCI is removed, TCR/TTBR cleanup would hide the active state.
	 * Read-only offsets follow apple-dart.c's S5L8960X register layout.
	 */
	dart_regs = ioremap(0x602002000ULL, 0x100);
	if (dart_regs) {
		pr_info("a1625_pci_scan: firmware DART tcr=%08x error=%08x fault_addr=%08x ttbr=%08x/%08x/%08x/%08x\n",
			readl(dart_regs + 0xc), readl(dart_regs + 0x10),
			readl(dart_regs + 0x1c), readl(dart_regs + 0x40),
			readl(dart_regs + 0x44), readl(dart_regs + 0x48),
			readl(dart_regs + 0x4c));
		iounmap(dart_regs);
	} else {
		ret = -ENOMEM;
	}
	pci_clear_master(dev);
	pr_info("a1625_pci_scan: firmware driver removed; endpoint master cleared\n");
put:
	pci_dev_put(dev);
	return ret < 0 ? ret : 0;
}

/* Caller owns both ECAM pages and holds verified power, PHY and link.
 * Firmware binding is opt-in and requires the live completion-fenced kernel.
 */
static int a1625_pci_scan(void __iomem *rc, void __iomem *ep, struct device *dart,
			  struct irq_domain *msi_domain, bool assign_memory, bool bind_firmware,
			  unsigned int hold_seconds, bool hold_until_signal)
{
	struct a1625_scan scan = { .rc = rc, .ep = ep, .require_iommu = !!dart,
		.msi_domain = msi_domain, .assign_memory = assign_memory,
		.bind_firmware = bind_firmware, .hold_seconds = hold_seconds,
		.hold_until_signal = hold_until_signal };
	struct a1625_pci_node node = {};
	struct pci_host_bridge *bridge;
	struct device *parent;
	struct resource buses = { .name = "a1625-pci-buses", .start = 0, .end = 1,
		.flags = IORESOURCE_BUS };
	struct resource memory = { .name = "a1625-pci-memory", .start = 0x7c0000000ULL,
		.end = 0x7ffffffffULL, .flags = IORESOURCE_MEM };
	bool memory_owned = false;
	u32 rc_bars[2], ep_bars[6], rc_rom, ep_rom, bus_numbers;
	u16 rc_command, ep_command, control;
	int ret, i, cleanup;

	if (pci_find_bus(0, 0) || readl(rc) != 0x1002106b || readl(ep) != 0x43a314e4)
		return -EBUSY;
	rc_command = readw(rc + PCI_COMMAND);
	ep_command = readw(ep + PCI_COMMAND);
	if (rc_command || ep_command)
		return -EBUSY;
	control = readw(rc + PCI_BRIDGE_CONTROL);
	bus_numbers = readl(rc + PCI_PRIMARY_BUS);
	if ((bus_numbers & 0xffffff) != 0x010100 || (control & PCI_BRIDGE_CTL_BUS_RESET))
		return -EBUSY;
	for (i = 0; i < 2; i++)
		rc_bars[i] = readl(rc + 0x10 + 4 * i);
	for (i = 0; i < 6; i++)
		ep_bars[i] = readl(ep + 0x10 + 4 * i);
	rc_rom = readl(rc + PCI_ROM_ADDRESS1);
	ep_rom = readl(ep + PCI_ROM_ADDRESS);
	if ((rc_rom | ep_rom) & PCI_ROM_ADDRESS_ENABLE)
		return -EBUSY;
	ret = a1625_scan_save_controls(&scan);
	if (ret)
		return ret;
	if (dart) {
		ret = a1625_pci_node_create(&node, dart);
		if (ret)
			goto node_out;
	}
	parent = root_device_register("a1625-pci-scan");
	if (IS_ERR(parent)) {
		ret = PTR_ERR(parent);
		goto node_out;
	}
	parent->of_node = of_node_get(node.node);
	bridge = pci_alloc_host_bridge(0);
	if (!bridge) {
		ret = -ENOMEM;
		goto parent_out;
	}
	bridge->dev.parent = parent;
	dev_set_msi_domain(&bridge->dev, msi_domain);
	bridge->ops = &a1625_scan_ops;
	bridge->sysdata = &scan;
	bridge->busnr = 0;
	pci_add_resource(&bridge->windows, &buses);
	if (assign_memory) {
		ret = request_resource(&iomem_resource, &memory);
		if (ret) {
			pci_free_host_bridge(bridge);
			goto parent_out;
		}
		memory_owned = true;
		/* Live J42d ADT non-prefetchable window: PCI c0000000 -> CPU 7c0000000. */
		pci_add_resource_offset(&bridge->windows, &memory, 0x700000000ULL);
	}
	ret = pci_scan_root_bus_bridge(bridge);
	if (!ret && assign_memory) {
		pci_bus_size_bridges(bridge->bus);
		pci_bus_assign_resources(bridge->bus);
	}
	if (!ret)
		pci_walk_bus(bridge->bus, a1625_scan_identify, &scan);
	if (!ret && (scan.rejected || scan.devices != 2))
		ret = -EIO;
	if (!ret && bind_firmware)
		ret = a1625_scan_firmware(bridge->bus, &scan);
	if (bridge->bus) {
		pci_stop_root_bus(bridge->bus);
		pci_remove_root_bus(bridge->bus);
	}
	pci_free_host_bridge(bridge);
	if (memory_owned && release_resource(&memory))
		ret = -EIO;
	for (i = scan.nr_controls - 1; i >= 0; i--) {
		struct a1625_scan_control *saved = &scan.controls[i];
		void __iomem *cfg = saved->bus ? ep : rc;
		u32 observed;
		if (saved->size == 2)
			writew(saved->saved, cfg + saved->where);
		else
			writel(saved->saved, cfg + saved->where);
		observed = saved->size == 2 ? readw(cfg + saved->where) : readl(cfg + saved->where);
		if ((observed & saved->mask) != saved->saved)
			ret = -EIO;
	}
	/* Only known writable controls are restored; never write status fields. */
	writew(ep_command, ep + PCI_COMMAND);
	writew(rc_command, rc + PCI_COMMAND);
	for (i = 0; i < 2; i++) {
		writel(rc_bars[i], rc + 0x10 + 4 * i);
		if (readl(rc + 0x10 + 4 * i) != rc_bars[i])
			ret = -EIO;
	}
	for (i = 0; i < 6; i++) {
		writel(ep_bars[i], ep + 0x10 + 4 * i);
		if (readl(ep + 0x10 + 4 * i) != ep_bars[i])
			ret = -EIO;
	}
	writel(rc_rom, rc + PCI_ROM_ADDRESS1);
	writel(ep_rom, ep + PCI_ROM_ADDRESS);
	writel(bus_numbers, rc + PCI_PRIMARY_BUS);
	writew(control, rc + PCI_BRIDGE_CONTROL);
	if (readw(rc + PCI_COMMAND) != rc_command || readw(ep + PCI_COMMAND) != ep_command ||
	    readl(rc + PCI_ROM_ADDRESS1) != rc_rom || readl(ep + PCI_ROM_ADDRESS) != ep_rom ||
	    readl(rc + PCI_PRIMARY_BUS) != bus_numbers || readw(rc + PCI_BRIDGE_CONTROL) != control)
		ret = -EIO;
	if (scan.rejected)
		ret = -EIO;
	pr_info("a1625_pci_scan: host removed and config restored; devices=%u rejected=%u result=%d\n",
		scan.devices, scan.rejected, ret);
parent_out:
	of_node_put(parent->of_node);
	parent->of_node = NULL;
	root_device_unregister(parent);
node_out:
	if (dart) {
		cleanup = a1625_pci_node_remove(&node);
		if (cleanup)
			ret = cleanup;
	}
	return ret;
}
#endif
