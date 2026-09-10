/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
#ifndef A1625_ANS1_RESERVATION_H
#define A1625_ANS1_RESERVATION_H
struct ans1_reservation;
/* Host resource claim only. No mapping, memory write, power or DMA operation.
 * Caller serializes ownership and passes an initially NULL output pointer.
 */
int ans1_reservation_claim(struct ans1_reservation **owner);
void ans1_reservation_release(struct ans1_reservation *owner);
#endif
