// SPDX-License-Identifier: GPL-2.0-only OR MIT
#include <linux/dma-mapping.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/soc/apple/rtkit.h>
#include "ans1_shmem.h"

/* Host policy limits, not claims about firmware requirements. Fail closed if
 * firmware requests more. Slots are never recycled without DMA quiescence.
 */
#define ANS1_SHMEM_SLOTS 4
#define ANS1_SHMEM_MAX_SIZE (1024U * 1024U)
struct ans1_shmem_record {
	void *buffer;
	dma_addr_t iova;
	size_t size;
};
struct ans1_shmem {
	struct device *dev;
	struct mutex lock;
	unsigned int count;
	struct ans1_shmem_record records[ANS1_SHMEM_SLOTS];
};

struct ans1_shmem *ans1_shmem_create(struct device *dev)
{
	struct ans1_shmem *owner;
	if (!dev)
		return ERR_PTR(-EINVAL);
	owner = kzalloc(sizeof(*owner), GFP_KERNEL);
	if (!owner)
		return ERR_PTR(-ENOMEM);
	owner->dev = get_device(dev);
	mutex_init(&owner->lock);
	return owner;
}

int ans1_shmem_setup(struct ans1_shmem *owner, struct apple_rtkit_shmem *bfr)
{
	struct ans1_shmem_record *record;
	int ret = 0;

	if (!owner || !bfr || !bfr->size || bfr->size > ANS1_SHMEM_MAX_SIZE)
		return -EINVAL;
	/* Firmware-provided IOVAs need a separately verified mapping plan. */
	if (bfr->iova || bfr->buffer || bfr->iomem || bfr->is_mapped || bfr->private)
		return -EOPNOTSUPP;
	mutex_lock(&owner->lock);
	if (owner->count == ANS1_SHMEM_SLOTS) {
		ret = -ENOSPC;
		goto out;
	}
	record = &owner->records[owner->count];
	record->buffer = dma_alloc_coherent(owner->dev, bfr->size,
					 &record->iova, GFP_KERNEL);
	if (!record->buffer) {
		ret = -ENOMEM;
		goto out;
	}
	record->size = bfr->size;
	memset(record->buffer, 0, record->size);
	bfr->buffer = record->buffer;
	bfr->iova = record->iova;
	bfr->private = record;
	/* Conservative publication boundary: RTKit may send the address as soon
	 * as we return. Even a failed send cannot justify releasing this memory.
	 */
	owner->count++;
out:
	mutex_unlock(&owner->lock);
	return ret;
}

void ans1_shmem_detach(struct ans1_shmem *owner, struct apple_rtkit_shmem *bfr)
{
	/* RTKit clears its descriptor next. Independent records remain pinned.
	 * No dereference of descriptor-private memory and no DMA free here.
	 */
	if (owner && bfr)
		bfr->private = NULL;
}

int ans1_shmem_free_unpublished(struct ans1_shmem *owner)
{
	if (!owner)
		return 0;
	/* Lifecycle owner has already drained callbacks. */
	if (owner->count)
		return -EBUSY;
	put_device(owner->dev);
	kfree(owner);
	return 0;
}
