// SPDX-License-Identifier: GPL-2.0
/*
 * cpufreq_epitaph_perf.c — Epitaph Performance Governor
 *
 * Aggressive ramp-up governor for gaming and benchmark workloads.
 * Designed to eliminate micro-stutter and maximize sustained throughput
 * on the Helio G88 Cortex-A75 cluster.
 *
 * Tunable defaults:
 *   up_rate_limit_us   = 100    (near-instant clock ramp on load spike)
 *   down_rate_limit_us = 50000  (hold peak freq 50ms after load drops)
 *   hispeed_load       = 70     (low threshold triggers early hispeed boost)
 *   hispeed_freq       = 0      (disabled by default, user-configurable)
 */

#define GOV_PREFIX           epiperf
#define GOV_NAME             "epitaph_performance"
#define DEFAULT_UP_RATE      100
#define DEFAULT_DOWN_RATE    50000
#define DEFAULT_HISPEED_LOAD 70
#define DEFAULT_HISPEED_FREQ 0

/* Touch & Launch Boost Defaults */
#define DEFAULT_BOOST_DURATION 100
#define DEFAULT_BOOST_USE_MAX  1
#define DEFAULT_LAUNCH_DURATION 500
#define DEFAULT_LAUNCH_USE_MAX  1

/* Governor Type Flag for Thermal Awareness */
#define GOV_IS_PERFORMANCE 1

#include "cpufreq_epitaph_common.h"
