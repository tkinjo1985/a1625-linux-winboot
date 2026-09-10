// SPDX-License-Identifier: GPL-2.0-only OR MIT
#include <linux/slab.h>
#include "ans1_dma.h"
#include "ans1_queue.h"
#include "ans1_read.h"

struct ans1_dma {
	struct device *dev;
	void *command, *data;
	dma_addr_t command_dma, data_dma;
	bool published;
};

struct ans1_dma *ans1_dma_alloc(struct device *dev)
{
	struct ans1_dma *dma;
	struct ans1_queue_messages messages;
	u8 check[128];
	int ret = -ENOMEM;

	if (!dev)
		return ERR_PTR(-EINVAL);
	dma = kzalloc(sizeof(*dma), GFP_KERNEL);
	if (!dma)
		return ERR_PTR(-ENOMEM);
	dma->dev = get_device(dev);
	dma->command = dma_alloc_coherent(dev, 4096, &dma->command_dma, GFP_KERNEL);
	if (!dma->command)
		goto fail;
	dma->data = dma_alloc_coherent(dev, 4096, &dma->data_dma, GFP_KERNEL);
	if (!dma->data)
		goto fail;
	if (dma->command_dma == dma->data_dma ||
	    !ans1_queue_messages(dma->command_dma, dma->command_dma, 4096, &messages) ||
	    !ans1_build_read(check, 0, 1, 4096, dma->data_dma, dma->data_dma, 4096)) {
		ret = -ERANGE;
		goto fail;
	}
	memset(dma->command, 0, 4096);
	memset(dma->data, 0, 4096);
	return dma;
fail:
	ans1_dma_free_unpublished(dma);
	return ERR_PTR(ret);
}

void *ans1_dma_command(struct ans1_dma *dma, dma_addr_t *address)
{
	*address = dma->command_dma;
	return dma->command;
}

void *ans1_dma_data(struct ans1_dma *dma, dma_addr_t *address)
{
	*address = dma->data_dma;
	return dma->data;
}

void ans1_dma_publish(struct ans1_dma *dma)
{
	dma->published = true;
}

int ans1_dma_free_unpublished(struct ans1_dma *dma)
{
	if (dma->published)
		return -EBUSY;
	if (dma->data)
		dma_free_coherent(dma->dev, 4096, dma->data, dma->data_dma);
	if (dma->command)
		dma_free_coherent(dma->dev, 4096, dma->command, dma->command_dma);
	put_device(dma->dev);
	kfree(dma);
	return 0;
}
