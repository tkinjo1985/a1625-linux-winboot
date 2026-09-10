/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ans1_fwsg.h"

static u8 image[0x60240];
static void put(u32 offset, u32 value)
{
	for (u32 i = 0; i < 4; i++) image[offset+i] = value >> (i*8);
}
int main(int argc, char **argv)
{
	struct ans1_fwsg_layout layout, sentinel;
	struct ans1_fw_segment heap;
	memcpy(image+0x60220, "fwsg", 4);
	put(0x60224, 1); put(0x60228, 0x601e0); put(0x6022c, 2);
	put(0x601ec, 0x47b88); put(0x601f0, 0x47b88);
	memcpy(image+0x601f8, "__TEXT", 6);
	put(0x60200, 0x48000); put(0x60208, 0x48000);
	put(0x6020c, 0x181c4); put(0x60210, 0xa8bc4);
	memcpy(image+0x60218, "__DATA", 6);
	const char *tags[] = {"GKTS","_COS","RCOS","dApC","dArW","klCN",
		"SVSD","LCSD","ZSTR","LRSD","SZSD","LZSD","ARcM","CCNA","0BHR","0SHR"};
	const u32 sizes[] = {4,4,4,8,8,4,4,4,4,1,8,8,4,4,8,4};
	u32 cursor = 0x48000;
	for (u32 i=0; i<16; i++) {
		memcpy(image+cursor, tags[i], 4); put(cursor+4,sizes[i]);
		cursor += 8+sizes[i];
	}
	assert(cursor == 0x480d1);
	if (argc == 2) {
		FILE *f = fopen(argv[1], "rb"); assert(f);
		assert(fread(image, 1, sizeof(image), f) == sizeof(image));
		assert(fgetc(f) == EOF); assert(!ferror(f)); fclose(f);
	}
	assert(ans1_fwsg_710(image, sizeof(image), &layout));
	assert(ans1_fw_heap(layout.segments, 2, 0x87f600000ULL, 0xa00000,
			    0xf1000, 0xe00000, &heap));
	assert(heap.phys == 0x87f6f1000ULL && heap.size == 0x90f000);
	assert(!ans1_fwsg_parameters_710(image,0x480d0));
	cursor=0x48000;
	for (u32 i=0;i<16;i++) {
		image[cursor] ^= 1;
		assert(!ans1_fwsg_parameters_710(image,sizeof(image)));
		image[cursor] ^= 1;
		put(cursor+4,0xffffffff);
		assert(!ans1_fwsg_parameters_710(image,sizeof(image)));
		put(cursor+4,sizes[i]); cursor += 8+sizes[i];
	}
	memset(&sentinel, 0xa5, sizeof(sentinel));
	for (u32 n=0; n<sizeof(image); n+=4096) {
		layout=sentinel;
		assert(!ans1_fwsg_710(image,n,&layout));
		assert(!memcmp(&layout,&sentinel,sizeof(layout)));
	}
	const u32 corrupt[] = {0x60220,0x60224,0x60228,0x6022c,
		0x601e4,0x601e8,0x601ec,0x601f0,0x601f4,0x601f8,
		0x60200,0x60208,0x6020c,0x60210,0x60214,0x60218};
	for (u32 i=0;i<sizeof(corrupt)/sizeof(corrupt[0]);i++) {
		image[corrupt[i]] ^= 1; layout=sentinel;
		assert(!ans1_fwsg_710(image,sizeof(image),&layout));
		assert(!memcmp(&layout,&sentinel,sizeof(layout)));
		image[corrupt[i]] ^= 1;
	}
	puts("ANS1 pinned fwsg parser and heap integration tests passed");
}
