// SPDX-License-Identifier: GPL-2.0-only
#include "a1625_radio_pulse.h"

static bool pulse;
module_param(pulse, bool, 0400);
MODULE_PARM_DESC(pulse, "Explicitly enable one 100 ms WL_REG_ON pulse; default validates only");

static int __init a1625_power_probe_init(void)
{
	int ret = a1625_radio_pulse(pulse, NULL, NULL);
	return ret ? ret : -ECANCELED;
}
module_init(a1625_power_probe_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("J42d bounded Wi-Fi power pulse with reset hold and rollback");
