// SPDX-License-Identifier: GPL-2.0
/*
 * cpufreq_epitaph.c — Epitaph Balanced Governor
 *
 * Default governor for the Epitaph kernel (Redmi 12 / Helio G88).
 * Designed for everyday use: responsive UI, smooth gaming, efficient battery.
 *
 * Tunable defaults:
 *   up_rate_limit_us   = 500    (fast ramp-up for touch/scroll responsiveness)
 *   down_rate_limit_us = 20000  (hold high freq briefly to absorb burst loads)
 *   hispeed_load       = 85     (boost when >85% util, avoids jank on launches)
 *   hispeed_freq       = 0      (disabled by default, user-configurable)
 */

#define GOV_PREFIX           epibal
#define GOV_NAME             "epitaph"
#define DEFAULT_UP_RATE      500
#define DEFAULT_DOWN_RATE    20000
#define DEFAULT_HISPEED_LOAD 85
#define DEFAULT_HISPEED_FREQ 0

/* Touch & Launch Boost Defaults */
#define DEFAULT_BOOST_DURATION 80
#define DEFAULT_BOOST_USE_MAX  0
#define DEFAULT_LAUNCH_DURATION 300
#define DEFAULT_LAUNCH_USE_MAX  0

#include "cpufreq_epitaph_common.h"
