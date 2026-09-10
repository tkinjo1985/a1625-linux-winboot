/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_FIRMWARE_H
#define A1625_ANS1_FIRMWARE_H
#include "ans1_fwsg.h"
struct ans1_firmware_plan {
	struct ans1_fwsg_layout layout;
	struct ans1_fw_segment heap;
};
/* Read-only preflight. Caller owns immutable bytes for the entire call.
 * This does not load firmware, claim RAM, authorize MMIO, or prove safe startup.
 */
int ans1_firmware_validate(const u8 *data, u32 bytes, u64 reserved_base,
			   u64 reserved_size, struct ans1_firmware_plan *plan);
/* Mutates only an exclusive ordinary-RAM copy, never an I/O mapping. The caller
 * must supply measured clock/revision and freshly generated canary bytes with
 * one byte forced to zero. Original digest is verified before any mutation.
 */
int ans1_firmware_parameters(u8 *copy, u32 bytes, u32 revision, u32 clock_hz,
			     u32 canary, struct ans1_firmware_plan *plan);
struct ans1_firmware_staging {
	u8 *data;
	u32 bytes;
	struct ans1_firmware_plan plan;
};
/* Produces private vmalloc RAM, not the physical ANS reservation. Caller must
 * pass an empty output and eventually free it. No device operation is performed.
 */
int ans1_firmware_build(const u8 *data, u32 bytes, u32 revision, u32 clock_hz,
			 u32 canary, struct ans1_firmware_staging *staging);
void ans1_firmware_free(struct ans1_firmware_staging *staging);
#endif
