/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_FWSG_H
#define A1625_ANS1_FWSG_H
#include "ans1_fw.h"

struct ans1_fwsg_layout {
	struct ans1_fw_image_segment segments[2];
	u32 offsets[2];
};

static inline u32 ans1_fwsg_u32(const u8 *p)
{
	return (u32)p[0] | (u32)p[1] << 8 | (u32)p[2] << 16 | (u32)p[3] << 24;
}

/* Exact packed table from the pinned image. No tag search or mutation occurs. */
static inline bool ans1_fwsg_parameters_710(const u8 *data, u32 bytes)
{
	static const u8 tags[16][4] = {
		{'G','K','T','S'}, {'_','C','O','S'}, {'R','C','O','S'},
		{'d','A','p','C'}, {'d','A','r','W'}, {'k','l','C','N'},
		{'S','V','S','D'}, {'L','C','S','D'}, {'Z','S','T','R'},
		{'L','R','S','D'}, {'S','Z','S','D'}, {'L','Z','S','D'},
		{'A','R','c','M'}, {'C','C','N','A'}, {'0','B','H','R'},
		{'0','S','H','R'}};
	static const u8 sizes[16] = {4,4,4,8,8,4,4,4,4,1,8,8,4,4,8,4};
	u32 cursor = 0x48000, i, j;

	if (!data || bytes < 0x480d1)
		return false;
	for (i = 0; i < 16; i++) {
		if (ans1_fwsg_u32(data + cursor + 4) != sizes[i])
			return false;
		for (j = 0; j < 4; j++)
			if (data[cursor + j] != tags[i][j])
				return false;
		cursor += 8 + sizes[i];
	}
	return cursor == 0x480d1;
}

/* Pinned ANS1-710.500.1 fwsg layout only. This is NOT authentication:
 * callers must verify the complete image digest before using its contents.
 * Byte loads support the packed, unaligned format on either host byte order.
 */
static inline bool ans1_fwsg_710(const u8 *data, u32 bytes,
				struct ans1_fwsg_layout *layout)
{
	static const u32 addresses[2] = {0, 0x48000};
	static const u32 file_sizes[2] = {0x47b88, 0x181c4};
	static const u32 memory_sizes[2] = {0x47b88, 0xa8bc4};
	static const u8 names[2][8] = {"__TEXT", "__DATA"};
	struct ans1_fwsg_layout result;
	const u8 *trailer;
	u32 i, j;

	if (!data || !layout || bytes != 0x60240)
		return false;
	if (!ans1_fwsg_parameters_710(data, bytes))
		return false;
	trailer = data + bytes - 32;
	if (trailer[0] != 'f' || trailer[1] != 'w' ||
	    trailer[2] != 's' || trailer[3] != 'g' ||
	    ans1_fwsg_u32(trailer + 4) != 1 ||
	    ans1_fwsg_u32(trailer + 8) != 0x601e0 ||
	    ans1_fwsg_u32(trailer + 12) != 2)
		return false;
	for (i = 0; i < 2; i++) {
		const u8 *entry = data + 0x601e0 + i * 32;
		u32 address = ans1_fwsg_u32(entry);
		u32 offset = ans1_fwsg_u32(entry + 8);
		u32 file_size = ans1_fwsg_u32(entry + 12);
		u32 memory_size = ans1_fwsg_u32(entry + 16);

		if (ans1_fwsg_u32(entry + 4) || ans1_fwsg_u32(entry + 20) ||
		    address != addresses[i] ||
		    offset != addresses[i] || file_size != file_sizes[i] ||
		    memory_size != memory_sizes[i])
			return false;
		for (j = 0; j < 8; j++)
			if (entry[24 + j] != names[i][j])
				return false;
		result.segments[i].address = address;
		result.segments[i].file_bytes = file_size;
		result.segments[i].memory_bytes = memory_size;
		result.offsets[i] = offset;
	}
	*layout = result;
	return true;
}
#endif
