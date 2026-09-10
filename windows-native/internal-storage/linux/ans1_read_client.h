/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_READ_CLIENT_H
#define A1625_ANS1_READ_CLIENT_H
#include <linux/completion.h>
#include <linux/mutex.h>
#include <linux/spinlock.h>
#include "ans1_transaction.h"
#include "ans1_geometry.h"
struct apple_rtkit;
struct ans1_dma;

/* Controller must verify any nonzero supplied capacity before init and READY
 * before register. Supply zero capacity to obtain geometry through identify.
 * Reads are rejected until this client's registration succeeds.
 * Both buffers are coherent DMA allocations owned by that controller.
 * Attach receive only after init. Detach/drain callbacks before releasing this
 * object. Failure never grants permission to release either DMA allocation.
 */
struct ans1_read_client {
	struct apple_rtkit *rtkit;
	struct mutex request_lock;
	spinlock_t state_lock;
	struct completion completion;
	struct ans1_transaction tx;
	u8 *command;
	void *data;
	u64 command_dma, data_dma, capacity;
	bool ready, registered;
	u8 endpoint;
};
int ans1_read_client_init(struct ans1_read_client *c, struct apple_rtkit *rtkit,
	u8 endpoint, u64 capacity, void *command, u64 command_dma,
	void *data, u64 data_dma);
void ans1_read_client_receive(struct ans1_read_client *c, u8 endpoint, u64 message);
/* After RTKit boot/endpoint discovery, with receive callback attached:
 * arm READY before starting the selected endpoint, then wait at most 3 s.
 */
int ans1_read_client_start(struct ans1_read_client *c);
/* Call only after controller READY was verified. Receive must already route
 * here. The DMA owner must match init's buffers; publication is irreversible.
 * Success means buffer ACK received and tag registration sent (no tag ACK).
 */
int ans1_read_client_register(struct ans1_read_client *c, struct ans1_dma *dma);
int ans1_read_client_read(void *cookie, u32 lba, void *destination);
/* Zero capacity at init permits registration/identify, but no reads.
 * Single attempt: pending/invalid geometry quarantines, never loops.
 */
int ans1_read_client_identify(struct ans1_read_client *c, struct ans1_geometry *out);
/* abort is suitable for a crash callback; stop waits in process context.
 * Neither stops firmware DMA. Detach callbacks before freeing this context.
 */
void ans1_read_client_abort(struct ans1_read_client *c);
void ans1_read_client_stop(struct ans1_read_client *c);
#endif
