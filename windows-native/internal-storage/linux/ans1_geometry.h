/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_GEOMETRY_H
#define A1625_ANS1_GEOMETRY_H
#include "ans1_wire.h"

struct ans1_geometry {
	u64 pages, bytes, preferred_bytes;
	u32 lba_bytes, lba_formatted, util_formatted;
};

static inline u32 ans1_get_le32(const u8 *p)
{
	return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) |
	       ((u32)p[3] << 24);
}

/* AppleTV5,3 16M568 GetNANDGeometry evidence: see tvos-readonly-analysis.md.
 * Input starts AFTER the 0x30-byte command header, not at its opcode.
 * Caller must validate completion and synchronize DMA before calling.
 * Layout validation is not proof of live device identity or firmware version.
 * No output changes on failure; no retry, repair or format command is issued.
 */
static inline bool ans1_decode_geometry(const u8 *body, u64 length,
					struct ans1_geometry *out)
{
	u32 pages, bytes, preferred, formatted, util;

	if (!body || !out || length < 24)
		return false;
	pages = ans1_get_le32(body);
	bytes = ans1_get_le32(body + 4);
	preferred = ans1_get_le32(body + 8);
	formatted = ans1_get_le32(body + 12);
	util = ans1_get_le32(body + 16);
	/* tvOS waits for this word to become zero. Do not guess its meaning
	 * or expose geometry while it remains nonzero.
	 */
	if (!pages || bytes != 4096 || !formatted || ans1_get_le32(body + 20))
		return false;
	out->pages = pages;
	out->bytes = (u64)pages * bytes;
	out->preferred_bytes = (u64)preferred * bytes;
	out->lba_bytes = bytes;
	out->lba_formatted = formatted;
	out->util_formatted = util;
	return true;
}
#endif
