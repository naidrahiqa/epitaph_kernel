/* SPDX-License-Identifier: GPL-2.0 */
/*
 * epitaph_input.h — Touch & Launch Boost API for Epitaph Governors
 * Copyright (C) 2026 Naidrahiqa & Antigravity AI
 *
 * Provides a dynamic registration interface between cpufreq governors
 * and the input/scheduler event hook manager.
 */

#ifndef _EPITAPH_INPUT_H
#define _EPITAPH_INPUT_H

#include <linux/list.h>

#define EPITAPH_BOOST_NONE   0
#define EPITAPH_BOOST_TOUCH  1
#define EPITAPH_BOOST_LAUNCH 2

struct epitaph_boost_entry {
	struct list_head node;
	void (*boost_fn)(void *data, unsigned int type);
	void *data;
};

#ifdef CONFIG_CPU_FREQ_EPITAPH_INPUT_BOOST
void epitaph_boost_register(struct epitaph_boost_entry *entry);
void epitaph_boost_unregister(struct epitaph_boost_entry *entry);
#else
static inline void epitaph_boost_register(struct epitaph_boost_entry *e) {}
static inline void epitaph_boost_unregister(struct epitaph_boost_entry *e) {}
#endif

#endif /* _EPITAPH_INPUT_H */
