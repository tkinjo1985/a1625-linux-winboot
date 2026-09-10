/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#include <assert.h>
#include <stdio.h>
#include "ans1_transaction.h"

int main(void)
{
	struct ans1_transaction tx = {0};
	unsigned int t;
	assert(ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 100, 100));
	assert(!ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 101, 100));
	for (t = 100; t < 200; t++) {
		ans1_transaction_receive(&tx, 5, 4, t);
		assert(tx.state == ANS1_TX_WAITING && tx.deadline == 200);
	}
	ans1_transaction_receive(&tx, 5, 2, 200);
	assert(tx.state == ANS1_TX_QUARANTINED);
	assert(!ans1_transaction_retire(&tx));
	assert(!ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 201, 100));
	ans1_transaction_receive(&tx, 5, 2, 202);
	assert(tx.state == ANS1_TX_QUARANTINED);

	tx = (struct ans1_transaction){0}; /* Separate simulated controller. */
	assert(!ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, ~0ULL, 1));
	assert(!ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 0, 3000000001ULL));
	assert(!ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 0, 0));
	assert(ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 0, 100));
	ans1_transaction_receive(&tx, 5, 2, 99);
	assert(tx.state == ANS1_TX_DONE);
	assert(ans1_transaction_retire(&tx));
	assert(ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 100, 100));
	ans1_transaction_expire(&tx, 200);
	assert(tx.state == ANS1_TX_QUARANTINED);

	tx = (struct ans1_transaction){0};
	ans1_transaction_receive(&tx, 5, 2, 0); /* Unsolicited completion. */
	assert(tx.state == ANS1_TX_QUARANTINED);
	tx = (struct ans1_transaction){0};
	assert(ans1_transaction_begin(&tx, 5, ANS1_WAIT_READ, 0, 100));
	ans1_transaction_fail(&tx);
	assert(!ans1_transaction_retire(&tx));
	puts("ANS1 transaction timeout/quarantine tests passed");
	return 0;
}
