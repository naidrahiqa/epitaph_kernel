// SPDX-License-Identifier: GPL-2.0
/*
 * cpufreq_epitaph_save.c — Epitaph Powersave Governor
 *
 * Conservative ramp-up governor that prioritizes battery life.
 * Deliberately slow to raise frequency, quick to drop it. Ideal for
 * screen-on idle, reading, and social media browsing on Redmi 12.
 *
 * Tunable defaults:
 *   up_rate_limit_us   = 2000   (2ms delay before ramping — absorbs transients)
 *   down_rate_limit_us = 5000   (quick 5ms drop to save power aggressively)
 *   hispeed_load       = 95     (only boost at near-full saturation)
 *   hispeed_freq       = 0      (disabled by default, user-configurable)
 */

#define GOV_PREFIX           episave
#define GOV_NAME             "epitaph_powersave"
#define DEFAULT_UP_RATE      2000
#define DEFAULT_DOWN_RATE    5000
#define DEFAULT_HISPEED_LOAD 95
#define DEFAULT_HISPEED_FREQ 0

/* Touch & Launch Boost Defaults */
#define DEFAULT_BOOST_DURATION 50
#define DEFAULT_BOOST_USE_MAX  0
#define DEFAULT_LAUNCH_DURATION 0 /* No launch boost */
#define DEFAULT_LAUNCH_USE_MAX  0

/* Governor Type Flag for Thermal Awareness */
#define GOV_IS_POWERSAVE 1

#include "cpufreq_epitaph_common.h"
