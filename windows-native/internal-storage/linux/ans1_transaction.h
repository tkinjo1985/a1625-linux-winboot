/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_TRANSACTION_H
#define A1625_ANS1_TRANSACTION_H

#include "ans1_reply.h"

enum ans1_transaction_state {
	ANS1_TX_IDLE,
	ANS1_TX_WAITING,
	ANS1_TX_DONE,
	ANS1_TX_QUARANTINED,
};

/* Caller serializes every operation with one lock. Times are monotonic ns.
 * Zero initialization is allowed only for a fresh, quiescent controller.
 * There is deliberately no reset/retry function for quarantined transactions.
 */
struct ans1_transaction {
	enum ans1_transaction_state state;
	enum ans1_wait_phase phase;
	u32 endpoint;
	u64 deadline;
};

static inline bool ans1_transaction_begin(struct ans1_transaction *tx,
					 u32 endpoint, enum ans1_wait_phase phase,
					 u64 now, u64 timeout)
{
	if (!tx || tx->state != ANS1_TX_IDLE || endpoint > 255 ||
	    (phase != ANS1_WAIT_READY && phase != ANS1_WAIT_COMMAND_BUFFER &&
	     phase != ANS1_WAIT_READ) || !timeout || timeout > 3000000000ULL ||
	    now > ~0ULL - timeout)
		return false;
	tx->endpoint = endpoint;
	tx->phase = phase;
	tx->deadline = now + timeout;
	tx->state = ANS1_TX_WAITING;
	return true;
}

/* Call from a timer even if no replies arrive. */
static inline void ans1_transaction_expire(struct ans1_transaction *tx, u64 now)
{
	if (tx->state == ANS1_TX_WAITING && now >= tx->deadline)
		tx->state = ANS1_TX_QUARANTINED;
}

static inline void ans1_transaction_receive(struct ans1_transaction *tx,
					   u32 endpoint, u64 data, u64 now)
{
	enum ans1_reply_result reply;

	ans1_transaction_expire(tx, now);
	if (tx->state != ANS1_TX_WAITING) {
		tx->state = ANS1_TX_QUARANTINED;
		return;
	}
	reply = ans1_check_reply(tx->endpoint, endpoint, data, tx->phase);
	if (reply == ANS1_REPLY_COMPLETE)
		tx->state = ANS1_TX_DONE;
	else if (reply != ANS1_REPLY_NOTIFICATION)
		tx->state = ANS1_TX_QUARANTINED;
}

/* Transport failure can leave a command in flight: do not reuse its DMA. */
static inline void ans1_transaction_fail(struct ans1_transaction *tx)
{
	tx->state = ANS1_TX_QUARANTINED;
}

/* Caller must finish DMA synchronization/data consumption before retiring. */
static inline bool ans1_transaction_retire(struct ans1_transaction *tx)
{
	if (tx->state != ANS1_TX_DONE)
		return false;
	tx->state = ANS1_TX_IDLE;
	return true;
}

#endif
