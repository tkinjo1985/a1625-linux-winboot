/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_RTKIT_CLIENT_H
#define A1625_ANS1_RTKIT_CLIENT_H
#include <linux/mutex.h>
struct ans1_shmem;
struct ans1_read_client;
struct apple_rtkit_ops;
/* Initialize before apple_rtkit_init. Keep alive until apple_rtkit_free has
 * drained callbacks. All callbacks use process context; no early RX hook.
 */
struct ans1_rtkit_client {
	struct mutex lock;
	struct ans1_shmem *shmem;
	struct ans1_read_client *reader;
	bool crashed;
};
int ans1_rtkit_client_init(struct ans1_rtkit_client *c, struct ans1_shmem *shmem);
/* Attach an initialized reader after endpoint discovery and before start. */
int ans1_rtkit_client_attach(struct ans1_rtkit_client *c, struct ans1_read_client *reader);
/* Caller must stop/drain outstanding reads before detaching. */
void ans1_rtkit_client_detach(struct ans1_rtkit_client *c);
extern const struct apple_rtkit_ops ans1_rtkit_client_ops;
#endif
