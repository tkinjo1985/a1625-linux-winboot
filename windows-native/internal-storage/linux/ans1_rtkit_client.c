// SPDX-License-Identifier: GPL-2.0-only OR MIT
#include <linux/err.h>
#include <linux/soc/apple/rtkit.h>
#include "ans1_read_client.h"
#include "ans1_shmem.h"
#include "ans1_rtkit_client.h"

int ans1_rtkit_client_init(struct ans1_rtkit_client *c, struct ans1_shmem *shmem)
{
	if (!c || IS_ERR_OR_NULL(shmem))
		return -EINVAL;
	mutex_init(&c->lock);
	c->shmem = shmem;
	c->reader = NULL;
	c->crashed = false;
	return 0;
}

int ans1_rtkit_client_attach(struct ans1_rtkit_client *c, struct ans1_read_client *reader)
{
	int ret = 0;
	if (!c || !reader)
		return -EINVAL;
	mutex_lock(&c->lock);
	if (c->crashed)
		ret = -EIO;
	else if (c->reader)
		ret = -EBUSY;
	else
		c->reader = reader;
	mutex_unlock(&c->lock);
	return ret;
}

void ans1_rtkit_client_detach(struct ans1_rtkit_client *c)
{
	mutex_lock(&c->lock);
	c->reader = NULL;
	mutex_unlock(&c->lock);
}

static void ans1_rtkit_crashed(void *cookie, const void *log, size_t size)
{
	struct ans1_rtkit_client *c = cookie;
	(void)log;
	(void)size;
	mutex_lock(&c->lock);
	c->crashed = true;
	if (c->reader)
		ans1_read_client_abort(c->reader);
	mutex_unlock(&c->lock);
}

static void ans1_rtkit_receive(void *cookie, u8 endpoint, u64 message)
{
	struct ans1_rtkit_client *c = cookie;
	mutex_lock(&c->lock);
	if (c->reader && !c->crashed)
		ans1_read_client_receive(c->reader, endpoint, message);
	mutex_unlock(&c->lock);
}

static int ans1_rtkit_shmem_setup(void *cookie, struct apple_rtkit_shmem *bfr)
{
	struct ans1_rtkit_client *c = cookie;
	int ret;
	mutex_lock(&c->lock);
	ret = c->crashed ? -EIO : ans1_shmem_setup(c->shmem, bfr);
	mutex_unlock(&c->lock);
	return ret;
}

static void ans1_rtkit_shmem_destroy(void *cookie, struct apple_rtkit_shmem *bfr)
{
	struct ans1_rtkit_client *c = cookie;
	ans1_shmem_detach(c->shmem, bfr);
}

const struct apple_rtkit_ops ans1_rtkit_client_ops = {
	.crashed = ans1_rtkit_crashed,
	.recv_message = ans1_rtkit_receive,
	.shmem_setup = ans1_rtkit_shmem_setup,
	.shmem_destroy = ans1_rtkit_shmem_destroy,
	.ans1_endpoint5 = true,
};
