/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_SHMEM_H
#define A1625_ANS1_SHMEM_H
#include <linux/types.h>
struct device;
struct apple_rtkit_shmem;
struct ans1_shmem;
/* Controller must retain this owner and its DMA device/mappings after any
 * successful setup. No verified post-publication teardown is available yet.
 * Stop/drain RTKit callbacks before attempting owner destruction.
 */
struct ans1_shmem *ans1_shmem_create(struct device *dev);
int ans1_shmem_setup(struct ans1_shmem *owner, struct apple_rtkit_shmem *bfr);
void ans1_shmem_detach(struct ans1_shmem *owner, struct apple_rtkit_shmem *bfr);
int ans1_shmem_free_unpublished(struct ans1_shmem *owner);
#endif
