/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_FW_H
#define A1625_ANS1_FW_H
#include "ans1_wire.h"

struct ans1_fw_segment { u64 phys, iova, size; };

/* Validated fwsg memory extents, not ADT mapping segments. */
struct ans1_fw_image_segment { u64 address, file_bytes, memory_bytes; };

/* Calculate the finite, IOVA-zero heap tail observed in the pinned ANS loader.
 * No memory is copied or patched. Caller must authenticate the image and parse
 * file offsets independently. Deliberately excludes alternate allocation modes.
 */
static inline bool ans1_fw_heap(const struct ans1_fw_image_segment *segments,
			       u32 count, u64 reserved_base, u64 reserved_size,
			       u32 image_extent, u32 requested_heap,
			       struct ans1_fw_segment *heap)
{
	u64 end = 0, rounded, available;
	u32 i;

	if (!segments || !heap || !count || count > 32 || !reserved_size ||
	    reserved_base > ~0ULL - reserved_size ||
	    ((reserved_base | reserved_size | image_extent) & 0xfff) ||
	    !image_extent || !requested_heap || segments[0].address)
		return false;
	for (i = 0; i < count; i++) {
		u64 address = segments[i].address, size = segments[i].memory_bytes;

		if (!size || segments[i].file_bytes > size || address < end ||
		    address > reserved_size || size > reserved_size - address)
			return false;
		end = address + size;
	}
	if (end > ~0ULL - 0xfff)
		return false;
	rounded = (end + 0xfff) & ~0xfffULL;
	if (image_extent < rounded || image_extent >= reserved_size)
		return false;
	available = reserved_size - image_extent;
	heap->phys = reserved_base + image_extent;
	heap->iova = image_extent;
	heap->size = available < requested_heap ? available : requested_heap;
	return true;
}

/* Metadata arithmetic only. The caller must independently establish ownership
 * of the entire reservation (including gaps), firmware integrity and quiescence.
 * Segments must be sorted by physical address; overlap is rejected.
 */
static inline bool ans1_fw_region(const struct ans1_fw_segment *segments,
				 u32 count, u64 reserved_base, u64 reserved_size,
				 struct ans1_fw_segment *region)
{
	u64 first, first_iova, end = 0;
	u32 i;

	if (!segments || !region || !count || count > 32 || !reserved_size ||
	    reserved_base > ~0ULL - reserved_size)
		return false;
	first = segments[0].phys;
	first_iova = segments[0].iova;
	for (i = 0; i < count; i++) {
		u64 phys = segments[i].phys, iova = segments[i].iova;
		u64 size = segments[i].size;

		if (!size || phys > ~0ULL - size || iova > ~0ULL - size ||
		    phys < first || iova < first_iova ||
		    phys - first != iova - first_iova || (i && phys < end) ||
		    phys < reserved_base || size > reserved_size ||
		    phys - reserved_base > reserved_size - size)
			return false;
		end = phys + size;
	}
	region->phys = first;
	region->iova = first_iova;
	region->size = end - first;
	return true;
}
#endif
