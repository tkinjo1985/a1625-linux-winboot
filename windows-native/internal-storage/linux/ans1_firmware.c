/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <crypto/sha2.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include "ans1_firmware.h"

int ans1_firmware_validate(const u8 *data, u32 bytes, u64 reserved_base,
			   u64 reserved_size, struct ans1_firmware_plan *plan)
{
	static const u8 expected[SHA256_DIGEST_SIZE] = {
		0x9e,0xa7,0x97,0x54,0xc6,0x77,0x79,0x0f,
		0x0a,0x0f,0x8c,0xb5,0x22,0x6d,0x3e,0xf3,
		0x36,0xa3,0x91,0x67,0x3d,0x74,0x46,0xee,
		0x2e,0x9d,0xce,0x95,0x77,0xc6,0xec,0xbe};
	struct ans1_firmware_plan result;
	u8 digest[SHA256_DIGEST_SIZE];
	u32 extent, requested_heap;

	if (!data || !plan || bytes != 0x60240 ||
	    reserved_base != 0x87f600000ULL || reserved_size != 0xa00000)
		return -EINVAL;
	sha256(data, bytes, digest);
	if (memcmp(digest, expected, sizeof(digest)))
		return -EBADMSG;
	if (!ans1_fwsg_710(data, bytes, &result.layout))
		return -EINVAL;
	extent = ans1_fwsg_u32(data + 0x48070);
	requested_heap = ans1_fwsg_u32(data + 0x480cd);
	if (!ans1_fw_heap(result.layout.segments, 2, reserved_base, reserved_size,
			  extent, requested_heap, &result.heap))
		return -EINVAL;
	*plan = result;
	return 0;
}

static void ans1_firmware_put(u8 *p, u64 value, u32 bytes)
{
	u32 i;
	for (i = 0; i < bytes; i++)
		p[i] = value >> (i * 8);
}

int ans1_firmware_parameters(u8 *copy, u32 bytes, u32 revision, u32 clock_hz,
			     u32 canary, struct ans1_firmware_plan *plan)
{
	struct ans1_firmware_plan result;
	u32 i;
	bool zero_byte = false;
	int ret;

	/* Revision has two 3-bit fields; clock fits its firmware 32-bit field. */
	if (!plan || (revision & ~0x77U) || !clock_hz)
		return -EINVAL;
	for (i = 0; i < 4; i++)
		zero_byte |= ((canary >> (i * 8)) & 255) == 0;
	if (!zero_byte)
		return -EINVAL;
	ret = ans1_firmware_validate(copy, bytes, 0x87f600000ULL, 0xa00000, &result);
	if (ret)
		return ret;
	/* All validation precedes these bounded writes. Offsets refer to payloads. */
	ans1_firmware_put(copy + 0x48008, canary, 4);
	ans1_firmware_put(copy + 0x48014, 0x7000, 4);
	ans1_firmware_put(copy + 0x48020, revision, 4);
	ans1_firmware_put(copy + 0x4802c, 0, 8);
	ans1_firmware_put(copy + 0x4803c, 0x208040000ULL, 8);
	ans1_firmware_put(copy + 0x480a5, 0x1000, 4);
	ans1_firmware_put(copy + 0x480b1, clock_hz, 4);
	ans1_firmware_put(copy + 0x480bd, result.heap.phys, 8);
	ans1_firmware_put(copy + 0x480cd, result.heap.size, 4);
	*plan = result;
	return 0;
}

int ans1_firmware_build(const u8 *data, u32 bytes, u32 revision, u32 clock_hz,
			 u32 canary, struct ans1_firmware_staging *staging)
{
	struct ans1_firmware_plan plan;
	u8 *copy, *image;
	u32 i;
	int ret;

	if (!data || bytes != 0x60240 || !staging || staging->data)
		return -EINVAL;
	copy = kmemdup(data, bytes, GFP_KERNEL);
	if (!copy)
		return -ENOMEM;
	ret = ans1_firmware_parameters(copy, bytes, revision, clock_hz, canary, &plan);
	if (ret)
		goto free_copy;
	image = vzalloc(0xa00000);
	if (!image) {
		ret = -ENOMEM;
		goto free_copy;
	}
	/* The validated layout bounds all copies. BSS, gaps and heap stay zero. */
	for (i = 0; i < 2; i++)
		memcpy(image + plan.layout.segments[i].address,
		       copy + plan.layout.offsets[i], plan.layout.segments[i].file_bytes);
	staging->data = image;
	staging->bytes = 0xa00000;
	staging->plan = plan;
free_copy:
	kfree(copy);
	return ret;
}

void ans1_firmware_free(struct ans1_firmware_staging *staging)
{
	if (!staging)
		return;
	vfree(staging->data);
	memset(staging, 0, sizeof(*staging));
}
