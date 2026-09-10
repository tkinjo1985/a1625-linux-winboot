// SPDX-License-Identifier: GPL-2.0-only OR MIT
#include <linux/dma-mapping.h>
#include <linux/ktime.h>
#include <linux/soc/apple/rtkit.h>
#include "ans1_read_client.h"
#include "ans1_read.h"
#include "ans1_queue.h"
#include "ans1_dma.h"

int ans1_read_client_init(struct ans1_read_client *c, struct apple_rtkit *rtkit,
	u8 endpoint, u64 capacity, void *command, u64 command_dma,
	void *data, u64 data_dma)
{
	struct ans1_queue_messages messages;
	u8 check[128];

	if (!c || !rtkit || !command || !data || command == data ||
	    (endpoint != 5 && endpoint != 6 && endpoint != 0x20) ||
	    !ans1_queue_messages(command_dma, command_dma, 4096, &messages) ||
	    !ans1_build_read(check, 0, capacity ? capacity : 1, 4096, data_dma, data_dma, 4096) ||
	    command_dma == data_dma)
		return -EINVAL;
	memset(c, 0, sizeof(*c));
	c->rtkit = rtkit; c->endpoint = endpoint; c->capacity = capacity;
	c->command = command; c->data = data; c->data_dma = data_dma;
	c->command_dma = command_dma;
	mutex_init(&c->request_lock);
	spin_lock_init(&c->state_lock);
	init_completion(&c->completion);
	return 0;
}

void ans1_read_client_receive(struct ans1_read_client *c, u8 endpoint, u64 message)
{
	unsigned long flags;

	spin_lock_irqsave(&c->state_lock, flags);
	ans1_transaction_receive(&c->tx, endpoint, message, ktime_get_ns());
	if (c->tx.state != ANS1_TX_WAITING)
		complete(&c->completion);
	spin_unlock_irqrestore(&c->state_lock, flags);
}

void ans1_read_client_abort(struct ans1_read_client *c)
{
	unsigned long flags;

	spin_lock_irqsave(&c->state_lock, flags);
	ans1_transaction_fail(&c->tx);
	complete(&c->completion);
	spin_unlock_irqrestore(&c->state_lock, flags);
}

void ans1_read_client_stop(struct ans1_read_client *c)
{
	ans1_read_client_abort(c);
	/* Do not invoke from the read callback itself. No state lock is held
	 * while waiting for the request owner to finish copying or unwind.
	 */
	mutex_lock(&c->request_lock);
	mutex_unlock(&c->request_lock);
}

int ans1_read_client_start(struct ans1_read_client *c)
{
	unsigned long flags;
	u64 now, deadline;
	int ret = -EIO;

	if (!c)
		return -EINVAL;
	mutex_lock(&c->request_lock);
	if (apple_rtkit_ans1_endpoint(c->rtkit) != c->endpoint) {
		mutex_unlock(&c->request_lock);
		return -EINVAL;
	}
	spin_lock_irqsave(&c->state_lock, flags);
	if (c->ready || c->registered || c->tx.state != ANS1_TX_IDLE)
		goto unlock_state;
	reinit_completion(&c->completion);
	if (!ans1_transaction_begin(&c->tx, c->endpoint, ANS1_WAIT_READY,
				    ktime_get_ns(), 3000000000ULL))
		goto unlock_state;
	deadline = c->tx.deadline;
	spin_unlock_irqrestore(&c->state_lock, flags);
	ret = apple_rtkit_start_ep(c->rtkit, c->endpoint);
	now = ktime_get_ns();
	if (!ret && now < deadline)
		wait_for_completion_timeout(&c->completion,
			max_t(unsigned long, 1, nsecs_to_jiffies(deadline - now)));
	spin_lock_irqsave(&c->state_lock, flags);
	if (ret)
		ans1_transaction_fail(&c->tx);
	ans1_transaction_expire(&c->tx, ktime_get_ns());
	if (!ans1_transaction_retire(&c->tx)) {
		ans1_transaction_fail(&c->tx);
		ret = -EIO;
	} else {
		c->ready = true;
		ret = 0;
	}
unlock_state:
	spin_unlock_irqrestore(&c->state_lock, flags);
	mutex_unlock(&c->request_lock);
	return ret;
}

int ans1_read_client_register(struct ans1_read_client *c, struct ans1_dma *dma)
{
	struct ans1_queue_messages messages;
	dma_addr_t address;
	unsigned long flags;
	u64 now, deadline;
	int ret = -EINVAL;

	if (!c || !dma)
		return -EINVAL;
	mutex_lock(&c->request_lock);
	if (ans1_dma_command(dma, &address) != c->command || address != c->command_dma ||
	    ans1_dma_data(dma, &address) != c->data || address != c->data_dma ||
	    !ans1_queue_messages(c->command_dma, c->command_dma, 4096, &messages))
		goto unlock_request;
	spin_lock_irqsave(&c->state_lock, flags);
	ret = -EIO;
	if (!c->ready || c->registered || c->tx.state != ANS1_TX_IDLE)
		goto unlock_state;
	reinit_completion(&c->completion);
	if (!ans1_transaction_begin(&c->tx, c->endpoint, ANS1_WAIT_COMMAND_BUFFER,
				    ktime_get_ns(), 3000000000ULL))
		goto unlock_state;
	deadline = c->tx.deadline;
	spin_unlock_irqrestore(&c->state_lock, flags);
	/* Even a send error cannot prove that the device missed this address. */
	ans1_dma_publish(dma);
	dma_wmb();
	ret = apple_rtkit_send_message(c->rtkit, c->endpoint,
				       messages.register_buffer, NULL, false);
	now = ktime_get_ns();
	if (!ret && now < deadline)
		wait_for_completion_timeout(&c->completion,
			max_t(unsigned long, 1, nsecs_to_jiffies(deadline - now)));
	spin_lock_irqsave(&c->state_lock, flags);
	if (ret)
		ans1_transaction_fail(&c->tx);
	ans1_transaction_expire(&c->tx, ktime_get_ns());
	if (c->tx.state != ANS1_TX_DONE) {
		ans1_transaction_fail(&c->tx);
		ret = -EIO;
		goto unlock_state;
	}
	/* Keep DONE until tag send finishes so concurrent aborts remain latched. */
	spin_unlock_irqrestore(&c->state_lock, flags);
	ret = apple_rtkit_send_message(c->rtkit, c->endpoint,
				       messages.register_tag, NULL, false);
	spin_lock_irqsave(&c->state_lock, flags);
	if (ret || !ans1_transaction_retire(&c->tx)) {
		ans1_transaction_fail(&c->tx);
		ret = -EIO;
	} else {
		c->registered = true;
	}
unlock_state:
	spin_unlock_irqrestore(&c->state_lock, flags);
unlock_request:
	mutex_unlock(&c->request_lock);
	return ret;
}

static int ans1_read_client_transfer(struct ans1_read_client *c, u32 lba,
				    void *destination, bool identify)
{
	struct ans1_geometry geometry;
	unsigned long flags;
	u64 now, deadline;
	int ret = -EIO;

	if (!c || !destination)
		return -EINVAL;
	mutex_lock(&c->request_lock);
	spin_lock_irqsave(&c->state_lock, flags);
	if (!c->registered || c->tx.state != ANS1_TX_IDLE)
		goto unlock_state;
	if (identify && c->capacity)
		goto unlock_state;
	if (identify) {
		/* A1625 GetNANDGeometry uses a cleared 128-byte command, opcode
		 * zero and the submission tag. Our only tag is zero. Response
		 * is inline at +0x30, not in the separate read-data buffer.
		 */
		memset(c->command, 0, 128);
	} else if (!ans1_build_read(c->command, lba, c->capacity, 4096,
			    c->data_dma, c->data_dma, 4096)) {
		ret = -EINVAL;
		goto unlock_state;
	}
	reinit_completion(&c->completion);
	if (!ans1_transaction_begin(&c->tx, c->endpoint, ANS1_WAIT_READ,
				    ktime_get_ns(), 3000000000ULL))
		goto unlock_state;
	deadline = c->tx.deadline;
	spin_unlock_irqrestore(&c->state_lock, flags);
	dma_wmb();
	ret = apple_rtkit_send_message(c->rtkit, c->endpoint, 0xff003, NULL, false);
	now = ktime_get_ns();
	if (!ret && now < deadline)
		wait_for_completion_timeout(&c->completion,
			max_t(unsigned long, 1, nsecs_to_jiffies(deadline - now)));
	spin_lock_irqsave(&c->state_lock, flags);
	if (ret)
		ans1_transaction_fail(&c->tx);
	ans1_transaction_expire(&c->tx, ktime_get_ns());
	if (c->tx.state == ANS1_TX_DONE) {
		dma_rmb();
		if (identify) {
			if (!ans1_decode_geometry(c->command + 0x30, 128 - 0x30, &geometry)) {
				ans1_transaction_fail(&c->tx);
				ret = -EIO;
				goto unlock_state;
			}
			c->capacity = geometry.pages;
			*(struct ans1_geometry *)destination = geometry;
		} else {
			memcpy(destination, c->data, 4096);
		}
		ans1_transaction_retire(&c->tx);
		ret = 0;
	} else {
		ans1_transaction_fail(&c->tx);
		ret = -EIO;
	}
unlock_state:
	spin_unlock_irqrestore(&c->state_lock, flags);
	mutex_unlock(&c->request_lock);
	return ret;
}

int ans1_read_client_read(void *cookie, u32 lba, void *destination)
{
	return ans1_read_client_transfer(cookie, lba, destination, false);
}

int ans1_read_client_identify(struct ans1_read_client *c, struct ans1_geometry *out)
{
	return ans1_read_client_transfer(c, 0, out, true);
}
