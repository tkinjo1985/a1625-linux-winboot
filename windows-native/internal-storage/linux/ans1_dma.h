/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_DMA_H
#define A1625_ANS1_DMA_H
#include <linux/dma-mapping.h>
struct ans1_dma;
/* Dedicated controller device must already have correct DMA/IOMMU setup.
 * All operations are serialized by the controller lifecycle owner.
 */
struct ans1_dma *ans1_dma_alloc(struct device *dev);
void *ans1_dma_command(struct ans1_dma *dma, dma_addr_t *address);
void *ans1_dma_data(struct ans1_dma *dma, dma_addr_t *address);
/* Call BEFORE the first buffer-registration send, including failed sends. */
void ans1_dma_publish(struct ans1_dma *dma);
/* Returns EBUSY after publication; no unverified quiescence override exists. */
int ans1_dma_free_unpublished(struct ans1_dma *dma);
#endif
