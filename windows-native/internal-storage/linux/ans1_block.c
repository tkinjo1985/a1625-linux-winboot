// SPDX-License-Identifier: GPL-2.0-only OR MIT
/* Unbound read-only block frontend. No init/probe function or hardware access. */
#include <linux/blk-mq.h>
#include <linux/blkdev.h>
#include <linux/bvec.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include "ans1_block.h"

struct ans1_block {
	struct blk_mq_tag_set tags;
	struct gendisk *disk;
	struct mutex lock;
	bool failed;
	u64 pages;
	int major;
	int (*read_page)(void *, u32, void *);
	void *cookie;
	char *buffer;
};

static blk_status_t ans1_block_request(struct blk_mq_hw_ctx *hctx,
				     const struct blk_mq_queue_data *bd)
{
	struct ans1_block *b = hctx->queue->queuedata;
	struct request *rq = bd->rq;
	struct req_iterator iter;
	struct bio_vec vec;
	unsigned int offset = 0;
	u64 sector = blk_rq_pos(rq);
	int ret;

	if (req_op(rq) != REQ_OP_READ)
		return BLK_STS_NOTSUPP;
	if ((sector & 7) || blk_rq_bytes(rq) != 4096 || sector / 8 >= b->pages)
		return BLK_STS_IOERR;
	/* Check the complete destination before invoking the controller. */
	rq_for_each_segment(vec, rq, iter) {
		if (vec.bv_len > 4096 - offset)
			return BLK_STS_IOERR;
		offset += vec.bv_len;
	}
	if (offset != 4096)
		return BLK_STS_IOERR;
	blk_mq_start_request(rq);
	mutex_lock(&b->lock);
	memset(b->buffer, 0, 4096);
	if (b->failed)
		ret = -EIO;
	else
		ret = b->read_page(b->cookie, sector / 8, b->buffer);
	if (ret)
		b->failed = true;
	if (!ret) {
		offset = 0;
		rq_for_each_segment(vec, rq, iter) {
			memcpy_to_bvec(&vec, b->buffer + offset);
			offset += vec.bv_len;
		}
	}
	mutex_unlock(&b->lock);
	blk_mq_end_request(rq, ret ? BLK_STS_IOERR : BLK_STS_OK);
	return BLK_STS_OK;
}

static const struct blk_mq_ops ans1_mq_ops = { .queue_rq = ans1_block_request };
static int ans1_block_set_read_only(struct block_device *bdev, bool ro)
{
	return ro ? 0 : -EROFS;
}

static const struct block_device_operations ans1_disk_ops = {
	.owner = THIS_MODULE,
	.set_read_only = ans1_block_set_read_only,
};

struct ans1_block *ans1_block_create(struct device *parent, u64 pages,
	int (*read_page)(void *, u32, void *), void *cookie)
{
	struct queue_limits limits = {
		.logical_block_size = 4096, .physical_block_size = 4096,
		.max_hw_sectors = 8,
	};
	struct ans1_block *b;
	int ret;

	if (!parent || !read_page || !pages || pages > (1ULL << 32))
		return ERR_PTR(-EINVAL);
	b = kzalloc(sizeof(*b), GFP_KERNEL);
	if (!b)
		return ERR_PTR(-ENOMEM);
	b->buffer = kmalloc(4096, GFP_KERNEL);
	if (!b->buffer) { ret = -ENOMEM; goto free_block; }
	b->pages = pages; b->read_page = read_page; b->cookie = cookie;
	mutex_init(&b->lock);
	b->tags.ops = &ans1_mq_ops;
	b->tags.nr_hw_queues = 1; b->tags.queue_depth = 1;
	b->tags.numa_node = NUMA_NO_NODE;
	b->tags.flags = BLK_MQ_F_BLOCKING;
	b->tags.timeout = 30 * HZ;
	ret = blk_mq_alloc_tag_set(&b->tags);
	if (ret) goto free_buffer;
	b->disk = blk_mq_alloc_disk(&b->tags, &limits, b);
	if (IS_ERR(b->disk)) { ret = PTR_ERR(b->disk); goto free_tags; }
	b->major = register_blkdev(0, "a1625ans");
	if (b->major < 0) { ret = b->major; goto put_disk; }
	b->disk->major = b->major; b->disk->minors = 1;
	b->disk->flags |= GENHD_FL_NO_PART;
	b->disk->fops = &ans1_disk_ops;
	strscpy(b->disk->disk_name, "a1625ans0");
	set_capacity(b->disk, pages * 8);
	set_disk_ro(b->disk, true);
	ret = device_add_disk(parent, b->disk, NULL);
	if (!ret) return b;
	unregister_blkdev(b->major, "a1625ans");
put_disk:
	put_disk(b->disk);
free_tags:
	blk_mq_free_tag_set(&b->tags);
free_buffer:
	kfree(b->buffer);
free_block:
	kfree(b);
	return ERR_PTR(ret);
}

void ans1_block_destroy(struct ans1_block *b)
{
	/* Baseline del_gendisk drains requests and cancels queue work. The
	 * controller cookie must remain alive until this function returns.
	 * This drains host requests only, not firmware DMA after a timeout.
	 */
	del_gendisk(b->disk);
	put_disk(b->disk);
	blk_mq_free_tag_set(&b->tags);
	unregister_blkdev(b->major, "a1625ans");
	kfree(b->buffer);
	kfree(b);
}
