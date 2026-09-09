// SPDX-License-Identifier: GPL-2.0-only
/* Temporary consumers of the three existing J42d PCIe power domains. */
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/init.h>
#include <linux/i2c.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/iopoll.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include "a1625_radio_pulse.h"
#include "a1625_pcie_domains.h"
#include "a1625_pcie_phy.h"
#include "a1625_dart_lifetime.h"
#include "a1625_dart_map.h"
#include "a1625_pci_scan.h"
#include "a1625_msi.h"

static bool cycle;
module_param(cycle, bool, 0400);
MODULE_PARM_DESC(cycle, "Enable and release PCIe domains once; default reads state only");

static bool force_active;
module_param(force_active, bool, 0400);
MODULE_PARM_DESC(force_active, "Temporarily suppress PMGR automatic clock gating while domain consumers are active");

static bool snapshot;
module_param(snapshot, bool, 0400);
MODULE_PARM_DESC(snapshot, "Read known core/port1 registers while domains are enabled; requires cycle=1");

static bool prepare_port;
module_param(prepare_port, bool, 0400);
MODULE_PARM_DESC(prepare_port, "Temporarily initialize T7000 internal port controls, then restore; requires cycle=1 snapshot=1");

static bool inspect_prefix;
module_param(inspect_prefix, bool, 0400);
MODULE_PARM_DESC(inspect_prefix, "Snapshot after the 11 verified PHY steps, before counter control; requires prepare_port=1");

static bool test_refclk;
module_param(test_refclk, bool, 0400);
MODULE_PARM_DESC(test_refclk, "Also test the stock port clock-enable bit without counter commands; requires inspect_prefix=1");

static bool inspect_rc;
module_param(inspect_rc, bool, 0400);
MODULE_PARM_DESC(inspect_rc, "Read only root port 00:01.0 identification; requires inspect_prefix=1");

static bool inspect_dart;
module_param(inspect_dart, bool, 0400);
MODULE_PARM_DESC(inspect_dart, "Read S5L8960X DART control/error/stream0 TTBRs only; requires test_refclk=1");

static bool probe_dart;
static bool scan_iommu;
static bool probe_msi;
module_param(probe_msi, bool, 0400);
MODULE_PARM_DESC(probe_msi, "EXPERIMENTAL: allocate/free T7000 MSI parent routes with radio off; requires test_refclk=1 force_active=1");
module_param(probe_dart, bool, 0400);
MODULE_PARM_DESC(probe_dart, "EXPERIMENTAL: register/reset/remove the DART driver without DMA clients; requires inspect_dart=1 force_active=1, radio off");

static bool map_dart;
static bool test_dma_range;
module_param(test_dma_range, bool, 0400);
MODULE_PARM_DESC(test_dma_range, "EXPERIMENTAL: DART DMA aperture 80000000..bfffffff; requires map_dart or scan_iommu");
module_param(map_dart, bool, 0400);
MODULE_PARM_DESC(map_dart, "EXPERIMENTAL: map/unmap one RAM page through stream0; requires probe_dart=1 and the fixed experimental kernel");

static int snapshot_dart(bool reset_expected)
{
	static const unsigned int offsets[] = { 0x0, 0xc, 0x10, 0x40, 0x44, 0x48, 0x4c };
	void __iomem *dart;
	unsigned int i, value;
	int ret = 0;

	if (!request_mem_region(0x602002000ULL, 0x2000, "a1625-dart-state"))
		return -EBUSY;
	dart = ioremap(0x602002000ULL, 0x2000);
	if (!dart) {
		ret = -ENOMEM;
		goto out;
	}
	for (i = 0; i < ARRAY_SIZE(offsets); i++) {
		value = readl(dart + offsets[i]);
		pr_info("a1625_pcie_domains: dart[0x%x]=0x%08x\n", offsets[i], value);
		if (value == ~0U) {
			ret = -ENODEV;
			break;
		}
		if (((probe_dart || scan_iommu) && offsets[i] == 0xc && value) ||
		    (reset_expected && offsets[i] >= 0x40 && value)) {
			ret = -EBUSY;
			pr_err("a1625_pcie_domains: unexpected DART state; stopping\n");
			break;
		}
	}
	iounmap(dart);
out:
	release_mem_region(0x602002000ULL, 0x2000);
	return ret;
}

static bool pulse_radio;
module_param(pulse_radio, bool, 0400);
MODULE_PARM_DESC(pulse_radio, "Pulse radio with PERST held while verified host clocks are active; requires test_refclk=1 inspect_rc=1 force_active=1");

static bool train_link;
module_param(train_link, bool, 0400);
MODULE_PARM_DESC(train_link, "Release PERST and attempt link training for at most 500ms, then stop and reset; requires pulse_radio=1");

static bool identify_endpoint;
module_param(identify_endpoint, bool, 0400);
MODULE_PARM_DESC(identify_endpoint, "Temporarily route bus 1 and read endpoint ID only; requires train_link=1");

static bool identify_chip;
module_param(identify_chip, bool, 0400);
MODULE_PARM_DESC(identify_chip, "Temporarily map BAR0 for chip ID read, never enable bus mastering; requires identify_endpoint=1");

static bool inspect_erom;
module_param(inspect_erom, bool, 0400);
MODULE_PARM_DESC(inspect_erom, "Read verified BCM4350 EROM component identifiers; requires identify_chip=1");

static bool scan_pci;
module_param(scan_pci, bool, 0400);
MODULE_PARM_DESC(scan_pci, "EXPERIMENTAL: bounded Linux PCI enumeration without driver binding or bus mastering; requires identify_endpoint=1");

static struct device *scan_dart;
static struct irq_domain *scan_msi_domain;
static bool scan_msi;
static bool assign_memory;
module_param(assign_memory, bool, 0400);
MODULE_PARM_DESC(assign_memory, "EXPERIMENTAL: assign PCI memory BARs in the verified J42d window; requires scan_msi=1");
static bool bind_firmware;
static unsigned int hold_seconds;
module_param(hold_seconds, uint, 0400);
MODULE_PARM_DESC(hold_seconds, "Hold initialized Wi-Fi for 1..3600 seconds; SIGTERM to runner ends hold and cleans up; requires bind_firmware");
static bool hold_until_signal;
module_param(hold_until_signal, bool, 0400);
MODULE_PARM_DESC(hold_until_signal, "Keep RAM Wi-Fi alive until signal or hardware fault; mutually exclusive with hold_seconds; requires bind_firmware");
module_param(bind_firmware, bool, 0400);
MODULE_PARM_DESC(bind_firmware, "EXPERIMENTAL: bounded brcmfmac binding; requires assign_memory=1 and completion-fenced kernel");
module_param(scan_msi, bool, 0400);
MODULE_PARM_DESC(scan_msi, "EXPERIMENTAL: allocate/free endpoint MSI through T7000 parent; requires scan_iommu=1");
module_param(scan_iommu, bool, 0400);
MODULE_PARM_DESC(scan_iommu, "EXPERIMENTAL: attach PCI endpoint to DART stream0 during scan; requires scan_pci=1 inspect_dart=1 and the fixed kernel");

static int snapshot_chip(void __iomem *rc, void __iomem *ep)
{
	void __iomem *bar = NULL;
	u32 low, high, window, mem, mask_low, mask_high, value;
	u16 rc_command, ep_command;
	u64 size;
	bool touched = false;
	int ret = -EBUSY;

	/* J42d ADT non-prefetchable PCI range: bus c0000000 -> CPU 7c0000000.
	 * Reserve the 32 KiB BAR aperture; read chip ID and the EROM pointer.
	 */
	if (!request_mem_region(0x7c0000000ULL, 0x8000, "a1625-brcm-chip-id"))
		return ret;
	low = readl(ep + 0x10);
	high = readl(ep + 0x14);
	window = readl(ep + 0x80);
	mem = readl(rc + 0x20);
	rc_command = readw(rc + 4);
	ep_command = readw(ep + 4);
	if (readl(ep) != 0x43a314e4 || readl(ep + 8) != 0x02800008 ||
	    low != 4 || high || window != 0x18003000 || mem ||
	    rc_command || ep_command)
		goto out;
	touched = true;
	/* Standard BAR sizing with memory decode and bus mastering disabled. */
	writel(~0U, ep + 0x10);
	writel(~0U, ep + 0x14);
	mask_low = readl(ep + 0x10);
	mask_high = readl(ep + 0x14);
	writel(high, ep + 0x14);
	writel(low, ep + 0x10);
	size = ~(((u64)mask_high << 32) | (mask_low & ~0xfU)) + 1;
	pr_info("a1625_pcie_domains: BAR0 sizing low=0x%08x high=0x%08x size=0x%llx\n",
		mask_low, mask_high, size);
	ret = -EIO;
	if (readl(ep + 0x10) != low || readl(ep + 0x14) != high || size != 0x8000)
		goto restore;
	bar = ioremap(0x7c0000000ULL, 0x1000);
	if (!bar) {
		ret = -ENOMEM;
		goto restore;
	}
	writel(0xc0000004, ep + 0x10);
	if (readl(ep + 0x10) != 0xc0000004)
		goto restore;
	writel(0xc000c000, rc + 0x20);
	if (readl(rc + 0x20) != 0xc000c000)
		goto restore;
	writel(0x18000000, ep + 0x80);
	if (readl(ep + 0x80) != 0x18000000)
		goto restore;
	writew(2, rc + 4);
	if (readw(rc + 4) != 2)
		goto restore;
	writew(2, ep + 4);
	if (readw(ep + 4) != 2)
		goto restore;
	value = readl(bar);
	pr_info("a1625_pcie_domains: chipcommon ID=0x%08x chip=0x%x revision=%u\n",
		value, value & 0xffff, (value >> 16) & 0xf);
	ret = value == ~0U || (value & 0xffff) != 0x4350 ? -ENODEV : 0;
	if (!ret) {
		/* chipcommon.h: eromptr at 0xfc. Observe only; do not follow an
		 * unverified backplane pointer or change the window here.
		 */
		value = readl(bar + 0xfc);
		pr_info("a1625_pcie_domains: chipcommon EROM pointer=0x%08x\n", value);
		if (!value || value == ~0U || (value & 3))
			ret = -ENODEV;
		if (!ret && inspect_erom) {
			unsigned int offset, components = 0, pcie = 0;
			bool ended = false;
			u32 first, second;

			/* Owned BCM4350 rev8: pointer observed in the preceding probe.
			 * Read at most its first 4 KiB; no backplane register writes.
			 * DMP component layout follows brcmfmac/chip.c.
			 */
			ret = -ENODEV;
			if (value != 0x1810d000)
				goto restore;
			writel(value, ep + 0x80);
			if (readl(ep + 0x80) != value)
				goto restore;
			for (offset = 0; offset < 0x1000; offset += 4) {
				first = readl(bar + offset);
				if (first == ~0U)
					goto restore;
				if ((first & 0xf) == 0xf) {
					ended = true;
					break;
				}
				if ((first & 0xfff0000f) != 0x4bf00001)
					continue;
				if (offset + 4 >= 0x1000)
					goto restore;
				second = readl(bar + offset + 4);
				if ((second & 0xf) != 1)
					goto restore;
				offset += 4;
				components++;
				if (((first >> 8) & 0xfff) == 0x83c)
					pcie++;
				pr_info("a1625_pcie_domains: EROM component=%03x revision=%u\n",
					(first >> 8) & 0xfff, second >> 24);
			}
			pr_info("a1625_pcie_domains: EROM end=%u components=%u PCIe2=%u\n",
				ended, components, pcie);
			ret = ended && components && pcie == 1 ? 0 : -ENODEV;
		}
	}
restore:
	/* Disable decode before restoring addresses. Use 16-bit command writes
	 * to avoid writing status W1C bits. Bus mastering is never enabled.
	 */
	if (touched) {
		writew(ep_command, ep + 4);
		writew(rc_command, rc + 4);
		writel(window, ep + 0x80);
		writel(high, ep + 0x14);
		writel(low, ep + 0x10);
		writel(mem, rc + 0x20);
		if (readw(ep + 4) != ep_command || readw(rc + 4) != rc_command ||
		    readl(ep + 0x80) != window || readl(ep + 0x14) != high ||
		    readl(ep + 0x10) != low || readl(rc + 0x20) != mem) {
			pr_err("a1625_pcie_domains: BAR/decode rollback mismatch\n");
			ret = -EIO;
		} else {
			pr_info("a1625_pcie_domains: BAR/window/decode restored; bus mastering off\n");
		}
	}
out:
	if (bar)
		iounmap(bar);
	release_mem_region(0x7c0000000ULL, 0x8000);
	return ret;
}

static int snapshot_endpoint(void)
{
	void __iomem *rc = NULL, *ep = NULL;
	bool rc_owned = false, ep_owned = false, changed = false;
	unsigned int buses = 0, value;
	int ret = -EBUSY;

	if (!request_mem_region(0x610008000ULL, 0x1000, "a1625-pcie-rc-id"))
		goto out;
	rc_owned = true;
	if (!request_mem_region(0x610100000ULL, 0x1000, "a1625-pcie-ep-id"))
		goto out;
	ep_owned = true;
	rc = ioremap(0x610008000ULL, 0x1000);
	ep = ioremap(0x610100000ULL, 0x1000);
	if (!rc || !ep) {
		ret = -ENOMEM;
		goto out;
	}
	ret = -ENODEV;
	if (readl(rc) != 0x1002106b || readl(rc + 8) != 0x06040001)
		goto out;
	buses = readl(rc + 0x18);
	pr_info("a1625_pcie_domains: root bus register before=0x%08x\n", buses);
	if (buses == ~0U || ((buses & 0xffffff) != 0 &&
			    (buses & 0xffffff) != 0x010100))
		goto out;
	if ((buses & 0xffffff) == 0) {
		changed = true;
		writel((buses & 0xff000000) | 0x010100, rc + 0x18);
		if (readl(rc + 0x18) != ((buses & 0xff000000) | 0x010100)) {
			ret = -EIO;
			goto out;
		}
	}
	/* Configuration readiness after PERST; no BAR, command or DMA writes. */
	msleep(100);
	value = readl(ep);
	pr_info("a1625_pcie_domains: endpoint 01:00.0 id=0x%08x\n", value);
	if ((value & 0xffff) != 0x14e4)
		goto out;
	value = readl(ep + 8);
	pr_info("a1625_pcie_domains: endpoint class-revision=0x%08x\n", value);
	if ((value >> 16) != 0x0280)
		goto out;
	value = readl(ep + 4);
	pr_info("a1625_pcie_domains: endpoint command-status=0x%08x\n", value);
	if (value == ~0U || (value & 4))
		goto out;
	value = readl(ep + 0x2c);
	pr_info("a1625_pcie_domains: endpoint subsystem-id=0x%08x\n", value);
	ret = value == ~0U ? -ENODEV : 0;
	if (!ret) {
		static const unsigned int offsets[] = { 0x10, 0x14, 0x18, 0x1c, 0x80 };
		unsigned int i;
		for (i = 0; i < ARRAY_SIZE(offsets); i++) {
			value = readl(ep + offsets[i]);
			pr_info("a1625_pcie_domains: endpoint config[0x%x]=0x%08x\n",
				offsets[i], value);
			if (value == ~0U) {
				ret = -ENODEV;
				goto out;
			}
		}
		pr_info("a1625_pcie_domains: root command=0x%04x memory-window=0x%08x\n",
			readw(rc + 4), readl(rc + 0x20));
	}
	if (!ret && identify_chip)
		ret = snapshot_chip(rc, ep);
	if (!ret && scan_pci)
		ret = a1625_pci_scan(rc, ep, scan_dart, scan_msi_domain, assign_memory, bind_firmware, hold_seconds, hold_until_signal);
out:
	if (changed) {
		if (readl(rc + 0x18) == ~0U) {
			ret = -EIO;
		} else {
			writel(buses, rc + 0x18);
			if (readl(rc + 0x18) != buses)
				ret = -EIO;
			else
				pr_info("a1625_pcie_domains: root bus register restored\n");
		}
	}
	if (ep)
		iounmap(ep);
	if (rc)
		iounmap(rc);
	if (ep_owned)
		release_mem_region(0x610100000ULL, 0x1000);
	if (rc_owned)
		release_mem_region(0x610008000ULL, 0x1000);
	return ret;
}

static int observe_held_radio(void *context, struct gpio_desc *reset,
			      struct regmap *gpio_map)
{
	void __iomem *port = context;
	unsigned int control = readl(port + 0x80);
	unsigned int status;
	int ret, cleanup;

	pr_info("a1625_pcie_domains: powered reset-held port control=0x%08x\n", control);
	if (control == ~0U || (control & 1))
		return -EIO;
	status = readl(port + 0x88);
	pr_info("a1625_pcie_domains: powered reset-held port status=0x%08x\n", status);
	if (status == ~0U || (status & 1))
		return -EIO;
	if (!train_link)
		return 0;
	ret = read_equal(gpio_map, 4 * 41, 0x76220);
	if (ret)
		return ret;
	ret = gpiod_direction_output_raw(reset, 1);
	if (ret)
		goto reset_again;
	ret = read_equal(gpio_map, 4 * 77, 0x76203);
	if (ret)
		goto reset_again;
	pr_info("a1625_pcie_domains: CLKREQ asserted; PERST released\n");
	writel(control | 1, port + 0x80);
	status = readl(port + 0x80);
	if (status != (control | 1)) {
		ret = -EIO;
		goto stop_link;
	}
	ret = readl_poll_timeout(port + 0x88, status,
				 status == ~0U || (status & 1), 1000, 500000);
	if (status == ~0U)
		ret = -ENODEV;
	pr_info("a1625_pcie_domains: training result=%d status=0x%08x\n", ret, status);
	if (!ret && identify_endpoint)
		ret = snapshot_endpoint();
stop_link:
	status = readl(port + 0x80);
	if (status != ~0U) {
		writel(control, port + 0x80);
		if (readl(port + 0x80) != control)
			ret = -EIO;
		else
			pr_info("a1625_pcie_domains: LTSSM control restored\n");
	} else {
		ret = -ENODEV;
	}
reset_again:
	cleanup = gpiod_direction_output_raw(reset, 0);
	if (!cleanup)
		cleanup = read_equal(gpio_map, 4 * 77, 0x76202);
	if (cleanup)
		ret = cleanup;
	else
		pr_info("a1625_pcie_domains: PERST held again before power off\n");
	return ret;
}

static int snapshot_root_port(void)
{
	void __iomem *cfg;
	unsigned int value;
	int ret = -ENODEV;

	/* Stock configRead32: reg[0] + bus<<20 + device<<15 + function<<12.
	 * Only bus 0, device 1, function 0; no endpoint scan or config writes.
	 */
	if (!request_mem_region(0x610008000ULL, 0x1000, "a1625-pcie-rc-probe"))
		return -EBUSY;
	cfg = ioremap(0x610008000ULL, 0x1000);
	if (!cfg) {
		ret = -ENOMEM;
		goto out;
	}
	value = readl(cfg);
	pr_info("a1625_pcie_domains: rc 00:01.0 id=0x%08x\n", value);
	if ((value & 0xffff) != 0x106b)
		goto unmap;
	value = readl(cfg + 8);
	pr_info("a1625_pcie_domains: rc class-revision=0x%08x\n", value);
	if ((value >> 16) != 0x0604)
		goto unmap;
	ret = 0;
unmap:
	iounmap(cfg);
out:
	release_mem_region(0x610008000ULL, 0x1000);
	return ret;
}

static int observe_radio_with_dart(struct device *dart, void *port)
{
	int ret;

	scan_dart = dart;
	ret = a1625_radio_pulse(true, observe_held_radio, port);
	scan_dart = NULL;
	return ret;
}

static int observe_pci_with_msi(struct irq_domain *domain, void *port)
{
	int ret;

	scan_msi_domain = domain;
	ret = a1625_with_dart(observe_radio_with_dart, port, test_dma_range);
	scan_msi_domain = NULL;
	return ret;
}

static int observe_ready_phy(void __iomem *port, void *context)
{
	int ret;
	ret = inspect_rc ? snapshot_root_port() : 0;
	if (!ret && inspect_dart)
		ret = snapshot_dart(false);
	if (!ret && probe_msi)
		ret = a1625_msi_probe(port);
	if (!ret && probe_dart)
		ret = a1625_with_dart(map_dart ? a1625_dart_map : NULL, NULL, test_dma_range);
	if (!ret && probe_dart)
		ret = snapshot_dart(true);
	if (!ret && scan_msi)
		ret = a1625_with_msi(port, observe_pci_with_msi, port);
	if (!ret && scan_iommu && !scan_msi)
		ret = a1625_with_dart(observe_radio_with_dart, port, test_dma_range);
	if (!ret && scan_iommu)
		ret = snapshot_dart(true);
	if (!ret && pulse_radio && !scan_iommu)
		ret = a1625_radio_pulse(true, observe_held_radio, port);
	return ret;
}

static int snapshot_registers(void)
{
	return a1625_with_pcie_phy(prepare_port, inspect_prefix, test_refclk,
				    observe_ready_phy, NULL);
}

static int run_domain_observation(void *context)
{
	return snapshot_registers();
}

static int __init a1625_pcie_domains_init(void)
{
	int ret;
	if (snapshot && !cycle)
		return -EINVAL;
	if (force_active && !cycle)
		return -EINVAL;
	if (prepare_port && (!snapshot || !cycle))
		return -EINVAL;
	if (inspect_prefix && !prepare_port)
		return -EINVAL;
	if (inspect_rc && !inspect_prefix)
		return -EINVAL;
	if (test_refclk && !inspect_prefix)
		return -EINVAL;
	if (inspect_dart && !test_refclk)
		return -EINVAL;
	if (probe_dart && (!inspect_dart || !force_active || pulse_radio))
		return -EINVAL;
	if (map_dart && !probe_dart)
		return -EINVAL;
	if (test_dma_range && !map_dart && !scan_iommu)
		return -EINVAL;
	if (pulse_radio && (!test_refclk || !inspect_rc || !force_active))
		return -EINVAL;
	if (train_link && !pulse_radio)
		return -EINVAL;
	if (identify_endpoint && !train_link)
		return -EINVAL;
	if (identify_chip && !identify_endpoint)
		return -EINVAL;
	if (inspect_erom && !identify_chip)
		return -EINVAL;
	if (scan_pci && (!identify_endpoint || identify_chip))
		return -EINVAL;
	if (scan_iommu && (!scan_pci || !inspect_dart || probe_dart || map_dart))
		return -EINVAL;
	if (scan_msi && !scan_iommu)
		return -EINVAL;
	if (assign_memory && !scan_msi)
		return -EINVAL;
	if (bind_firmware && !assign_memory)
		return -EINVAL;
	if (hold_seconds && (!bind_firmware || hold_seconds > 3600))
		return -EINVAL;
	if (hold_until_signal && (!bind_firmware || hold_seconds))
		return -EINVAL;
	if (probe_msi && (!test_refclk || !force_active || pulse_radio || probe_dart))
		return -EINVAL;
	ret = a1625_with_pcie_domains(cycle, force_active,
				       snapshot ? run_domain_observation : NULL, NULL);
	return ret ? ret : -ECANCELED;
}
module_init(a1625_pcie_domains_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("J42d PCIe domain state and bounded genpd cycle");
