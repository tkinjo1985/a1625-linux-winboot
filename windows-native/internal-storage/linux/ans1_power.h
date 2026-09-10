/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef A1625_ANS1_POWER_H
#define A1625_ANS1_POWER_H
/* Read-only instantaneous check. This does not hold power off or certify DMA
 * quiescence. Caller must separately prevent other owners from changing power.
 */
int ans1_power_require_off(void);
#endif
