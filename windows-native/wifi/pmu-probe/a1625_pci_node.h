// SPDX-License-Identifier: GPL-2.0-only
#ifndef A1625_PCI_NODE_H
#define A1625_PCI_NODE_H

struct a1625_pci_node {
	struct of_changeset changes;
	struct device_node *node;
	bool applied;
};

static int a1625_pci_node_remove(struct a1625_pci_node *state)
{
	int ret = 0, cleanup;

	/* All PCI devices and their parent must be gone before this call. */
	if (state->applied)
		ret = of_changeset_revert(&state->changes);
	if (state->node) {
		if (!of_node_check_flag(state->node, OF_DETACHED)) {
			cleanup = of_detach_node(state->node);
			if (cleanup)
				ret = cleanup;
		}
		of_node_clear_flag(state->node, OF_POPULATED);
	}
	of_changeset_destroy(&state->changes);
	of_node_put(state->node);
	state->node = NULL;
	return ret;
}

static int a1625_pci_node_create(struct a1625_pci_node *state, struct device *dart)
{
	struct device_node *existing;
	u32 map[] = { 0x100, 0xa1625001, 0, 1 };
	u32 buses[] = { 0, 1 };
	int ret;

	of_changeset_init(&state->changes);
	if (!dart->of_node || dart->of_node->phandle != map[1])
		return -EINVAL;
	existing = of_find_node_by_path("/soc/pcie@610000000");
	if (existing) {
		of_node_put(existing);
		return -EBUSY;
	}
	state->node = of_changeset_create_node(&state->changes, dart->of_node->parent,
					       "pcie@610000000");
	if (!state->node)
		return -ENOMEM;
	/* This node supplies PCI DMA routing, not a binding to an M1 controller.
	 * Only RID 01:00.0 maps to the ADT-verified Wi-Fi stream 0. The root
	 * port is not a DMA client. Resource assignment is a later stage.
	 */
	ret = of_changeset_add_prop_string(&state->changes, state->node, "device_type", "pci");
	if (!ret)
		ret = of_changeset_add_prop_u32(&state->changes, state->node, "#address-cells", 3);
	if (!ret)
		ret = of_changeset_add_prop_u32(&state->changes, state->node, "#size-cells", 2);
	if (!ret)
		ret = of_changeset_add_prop_u32_array(&state->changes, state->node, "bus-range", buses, 2);
	if (!ret)
		ret = of_changeset_add_prop_u32_array(&state->changes, state->node, "iommu-map", map, 4);
	if (!ret)
		ret = of_changeset_add_prop_u32(&state->changes, state->node, "iommu-map-mask", 0xffff);
	if (ret)
		return ret;
	of_node_set_flag(state->node, OF_POPULATED);
	ret = of_changeset_apply(&state->changes);
	if (!ret)
		state->applied = true;
	return ret;
}
#endif
