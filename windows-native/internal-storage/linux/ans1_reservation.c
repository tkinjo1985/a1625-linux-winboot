// SPDX-License-Identifier: GPL-2.0-only OR MIT
#include <linux/errno.h>
#include <linux/ioport.h>
#include <linux/mm.h>
#include <linux/of.h>
#include <linux/slab.h>
#include "ans1_reservation.h"

#define ANS1_RESERVED_BASE 0x87f600000ULL
#define ANS1_RESERVED_SIZE 0xa00000
struct ans1_reservation { struct resource *resource; };

int ans1_reservation_claim(struct ans1_reservation **owner)
{
	struct ans1_reservation *result;

	if (!owner || *owner)
		return -EINVAL;
	if (!of_machine_is_compatible("apple,j42d") ||
	    !of_machine_is_compatible("apple,t7000"))
		return -ENODEV;
	if (region_intersects(ANS1_RESERVED_BASE, ANS1_RESERVED_SIZE,
			      IORESOURCE_SYSTEM_RAM, IORES_DESC_NONE) != REGION_DISJOINT)
		return -EBUSY;
	result = kzalloc(sizeof(*result), GFP_KERNEL);
	if (!result)
		return -ENOMEM;
	result->resource = request_mem_region_exclusive(ANS1_RESERVED_BASE,
				ANS1_RESERVED_SIZE, "a1625-ans1-reservation");
	if (!result->resource) {
		kfree(result);
		return -EBUSY;
	}
	*owner = result;
	return 0;
}

void ans1_reservation_release(struct ans1_reservation *owner)
{
	if (!owner)
		return;
	release_mem_region(ANS1_RESERVED_BASE, ANS1_RESERVED_SIZE);
	kfree(owner);
}
