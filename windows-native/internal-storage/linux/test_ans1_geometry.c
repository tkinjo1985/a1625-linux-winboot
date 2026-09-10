#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ans1_geometry.h"
#include "ans1_read.h"

int main(void)
{
	/* Reconstructed from pinned ANS1-710 capture inputs and producer stores.
	 * NOT a captured mailbox/DMA response. See controller-integration.md.
	 */
	const u8 retained_example[24] = {
		0x94, 0x35, 0x77, 0x00, 0x00, 0x10, 0x00, 0x00,
		0x20, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	};
	u8 body[24] = {0};
	struct ans1_geometry geometry, before;
	assert(ans1_decode_geometry(retained_example, sizeof(retained_example), &geometry));
	assert(geometry.pages == 7812500 && geometry.bytes == 32000000000ULL);
	assert(geometry.preferred_bytes == 131072);
	assert(geometry.lba_formatted == 1 && geometry.util_formatted == 1);
	memset(&geometry, 0xa5, sizeof(geometry));
	memcpy(&before, &geometry, sizeof(before));
	ans1_put_le32(body, 0x12345678);
	ans1_put_le32(body + 4, 4096);
	ans1_put_le32(body + 8, 0xffffffff);
	ans1_put_le32(body + 12, 1);
	for (unsigned int n = 0; n < 24; n++) {
		assert(!ans1_decode_geometry(body, n, &geometry));
		assert(!memcmp(&geometry, &before, sizeof(before)));
	}
	assert(!ans1_decode_geometry(NULL, 24, &geometry));
	assert(!ans1_decode_geometry(body, 24, NULL));
	assert(ans1_decode_geometry(body, 24, &geometry));
	assert(geometry.pages == 0x12345678 && geometry.bytes == 0x12345678000ULL);
	assert(geometry.preferred_bytes == 0xffffffff000ULL);
	assert(geometry.lba_bytes == 4096 && geometry.lba_formatted == 1);
	assert(!geometry.util_formatted); /* Auxiliary state is not UserArea capacity. */
	for (unsigned int n = 0; n < 4; n++) {
		u8 bad[24]; memcpy(bad, body, sizeof(bad));
		if (n == 0) ans1_put_le32(bad, 0);
		if (n == 1) ans1_put_le32(bad + 4, 16384);
		if (n == 2) ans1_put_le32(bad + 12, 0);
		if (n == 3) ans1_put_le32(bad + 20, 1);
		memcpy(&before, &geometry, sizeof(before));
		assert(!ans1_decode_geometry(bad, 24, &geometry));
		assert(!memcmp(&geometry, &before, sizeof(before)));
	}
	ans1_put_le32(body, 0xffffffff);
	ans1_put_le32(body + 12, 2); /* tvOS treats any nonzero u32 as true. */
	assert(ans1_decode_geometry(body, 24, &geometry));
	assert(geometry.pages == 0xffffffffULL && geometry.bytes == 0xffffffff000ULL);
	puts("A1625 geometry decoder bounds and field tests passed");
}
