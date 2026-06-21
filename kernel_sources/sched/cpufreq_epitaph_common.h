/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Epitaph Governor Family — Shared Implementation Header
 * Copyright (C) 2026 Naidrahiqa & Antigravity AI
 *
 * Parameterized schedutil fork for Helio G88 (MT6769).
 * Each variant .c file defines GOV_PREFIX, GOV_NAME, and default tunable
 * values before including this header to instantiate a distinct governor.
 */

#ifndef _CPUFREQ_EPITAPH_COMMON_H
#define _CPUFREQ_EPITAPH_COMMON_H

#include <linux/cpufreq.h>
#include <linux/hrtimer.h>
#include <linux/init.h>
#include <linux/kthread.h>
#include <linux/slab.h>
#include <linux/sched/cpufreq.h>
#include <uapi/linux/sched/types.h>
#include <linux/irq_work.h>
#include <linux/tick.h>
#include <linux/units.h>
#include <trace/events/power.h>

#include <linux/sched/signal.h>
#include <linux/sched/cputime.h>

#include "sched.h"
#include "epitaph_input.h"

/* ── Thermal Handoff Telemetry (shared from epitaph_input.c) ────────── */
extern unsigned int epitaph_thermal_state;       /* 0=cool, 1=warm, 2=hot */
extern unsigned int epitaph_thermal_ceiling_pct; /* Dynamic frequency cap, 75 to 100 */

/* ── Token-paste macros ──────────────────────────────────────────────── */
#define _EP_PASTE(a, b) a##b
#define EP_PASTE(a, b)  _EP_PASTE(a, b)
#define EP(name)        EP_PASTE(GOV_PREFIX, name)

/* ── Data structures ─────────────────────────────────────────────────── */

struct EP(_tunables) {
	struct gov_attr_set attr_set;
	unsigned int up_rate_limit_us;
	unsigned int down_rate_limit_us;
	unsigned int hispeed_load;
	unsigned int hispeed_freq;
	/* Touch boost tunables */
	unsigned int touch_boost_duration_ms;
	unsigned int touch_boost_freq;
};

struct EP(_policy) {
	struct cpufreq_policy	*policy;
	struct EP(_tunables)	*tunables;
	struct list_head	tunables_hook;
	raw_spinlock_t		update_lock;
	u64			last_freq_update_time;
	s64			up_rate_delay_ns;
	s64			down_rate_delay_ns;
	unsigned int		next_freq;
	unsigned int		cached_raw_freq;

	struct irq_work		irq_work;
	struct kthread_work	work;
	struct mutex		work_lock;
	struct kthread_worker	worker;
	struct task_struct	*thread;

	bool			work_in_progress;
	bool			limits_changed;
	bool			need_freq_update;

	/* Touch boost state */
	unsigned int		boost_freq_floor;
	struct hrtimer		boost_timer;
	struct epitaph_boost_entry boost_entry;
};

struct EP(_cpu) {
	struct update_util_data	update_util;
	struct EP(_policy)	*ep_policy;
	unsigned int		cpu;

	bool			iowait_boost_pending;
	unsigned int		iowait_boost;
	u64			last_update;

	unsigned long		util;
	unsigned long		bw_min;
	unsigned long		max;
};

static DEFINE_PER_CPU(struct EP(_cpu), EP(_cpu_data));

/* ── Rate limiting ───────────────────────────────────────────────────── */

static inline void EP(_update_rate_limit)(struct EP(_policy) *ep,
					  unsigned int up_us, unsigned int dn_us)
{
	ep->up_rate_delay_ns   = up_us * NSEC_PER_USEC;
	ep->down_rate_delay_ns = dn_us * NSEC_PER_USEC;
}

static bool EP(_should_update)(struct EP(_policy) *ep, u64 time)
{
	s64 delta_ns;

	if (unlikely(ep->limits_changed)) {
		ep->limits_changed = false;
		ep->need_freq_update = true;
		return true;
	}

	delta_ns = time - ep->last_freq_update_time;
	if (ep->next_freq > ep->policy->cur)
		return delta_ns >= ep->up_rate_delay_ns;

	/* HOT Thermal State: double down_rate_limit_us (cut delay in half to drop freq faster) */
	if (READ_ONCE(epitaph_thermal_state) == 2)
		return delta_ns >= (ep->down_rate_delay_ns / 2);

	return delta_ns >= ep->down_rate_delay_ns;
}

static bool EP(_update_next_freq)(struct EP(_policy) *ep,
				  u64 time, unsigned int next_freq)
{
	if (ep->next_freq == next_freq)
		return false;
	ep->next_freq = next_freq;
	ep->last_freq_update_time = time;
	return true;
}

/* ── Touch boost — hrtimer expiry and kick function ──────────────────── */

static enum hrtimer_restart EP(_boost_timer_expire)(struct hrtimer *timer)
{
	struct EP(_policy) *ep =
		container_of(timer, struct EP(_policy), boost_timer);

	WRITE_ONCE(ep->boost_freq_floor, 0);
	ep->need_freq_update = true;

	return HRTIMER_NORESTART;
}

static void EP(_boost_kick)(void *data, unsigned int type)
{
	struct EP(_policy) *ep = data;
	struct EP(_tunables) *t = ep->tunables;
	unsigned int target = 0, dur = 0;
	unsigned int thermal_state = READ_ONCE(epitaph_thermal_state);

	/* HOT Thermal State: Disable all boosts */
	if (thermal_state == 2)
		return;

	if (type == EPITAPH_BOOST_TOUCH) {
		dur = READ_ONCE(t->touch_boost_duration_ms);

		/* WARM Thermal State adjustments */
		if (thermal_state == 1) {
#ifdef GOV_IS_PERFORMANCE
			/* Performance governor acts like balanced governor */
			dur = 80;
#elif defined(GOV_IS_POWERSAVE)
			/* Powersave stays normal (already conservative) */
#else
			/* Balanced reduces touch duration by 50% */
			dur = dur / 2;
#endif
		}

		if (!dur)
			return;

		target = READ_ONCE(t->touch_boost_freq);
		if (!target) {
			target = READ_ONCE(t->hispeed_freq);
#ifdef DEFAULT_BOOST_USE_MAX
			if (thermal_state == 1) {
				/* Performance uses balanced hispeed target when warm */
				if (!target)
					target = ep->policy->cpuinfo.max_freq;
			} else {
				if (!target || DEFAULT_BOOST_USE_MAX)
					target = ep->policy->cpuinfo.max_freq;
			}
#else
			if (!target)
				target = ep->policy->cpuinfo.max_freq;
#endif
		}
	} else if (type == EPITAPH_BOOST_LAUNCH) {
		/* WARM Thermal State: Disable launch boost for balanced & performance */
		if (thermal_state == 1)
			return;

#ifdef DEFAULT_LAUNCH_DURATION
		dur = DEFAULT_LAUNCH_DURATION;
#else
		dur = 0;
#endif
		if (!dur)
			return;

#ifdef DEFAULT_LAUNCH_USE_MAX
		if (DEFAULT_LAUNCH_USE_MAX) {
			target = ep->policy->cpuinfo.max_freq;
		} else {
			target = READ_ONCE(t->hispeed_freq);
			if (!target)
				target = ep->policy->cpuinfo.max_freq;
		}
#else
		target = ep->policy->cpuinfo.max_freq;
#endif
	}

	if (!target || !dur)
		return;

	WRITE_ONCE(ep->boost_freq_floor, target);
	ep->need_freq_update = true;

	hrtimer_start(&ep->boost_timer, ms_to_ktime(dur),
		      HRTIMER_MODE_REL_PINNED);
}

/* ── Frequency calculation with hispeed, touch, & thermal limits ──────── */

static void EP(_get_util)(struct EP(_cpu) *epc)
{
	unsigned long util = cpu_util_cfs_boost(epc->cpu);
	unsigned long max = arch_scale_cpu_capacity(epc->cpu);

	epc->bw_min = 0;
	epc->util = effective_cpu_util(epc->cpu, util, FREQUENCY_UTIL, NULL);
	epc->max = max;
}

static unsigned int EP(_calc_next_freq)(struct EP(_policy) *ep,
					unsigned long util, unsigned long max)
{
	struct cpufreq_policy *policy = ep->policy;
	struct EP(_tunables) *t = ep->tunables;
	unsigned int freq, hs, floor;
	unsigned int thermal_state = READ_ONCE(epitaph_thermal_state);
	unsigned int ceiling_pct;

	freq = map_util_freq(util, policy->cpuinfo.max_freq, max);

	/* Hispeed boost: jump to hispeed_freq when load exceeds threshold */
	hs = READ_ONCE(t->hispeed_freq);
	if (hs && max) {
		unsigned int load = (unsigned int)(util * 100 / max);
		if (load >= READ_ONCE(t->hispeed_load) && hs > freq)
			freq = hs;
	}

	/* Touch boost floor: enforce minimum until hrtimer expires (disabled in HOT state) */
	if (thermal_state != 2) {
		floor = READ_ONCE(ep->boost_freq_floor);
		if (floor && freq < floor)
			freq = floor;
	}

	/* Thermal ceiling handoff (HOT or gradual cooldown recovery) */
	ceiling_pct = READ_ONCE(epitaph_thermal_ceiling_pct);
	if (ceiling_pct < 100) {
		unsigned int ceiling_freq = (policy->cpuinfo.max_freq * ceiling_pct) / 100;
		if (freq > ceiling_freq)
			freq = ceiling_freq;
	}

	if (freq == ep->cached_raw_freq && ep->next_freq != UINT_MAX)
		return ep->next_freq;

	ep->cached_raw_freq = freq;
	return cpufreq_driver_resolve_freq(policy, freq);
}

/* ── IO wait boost ───────────────────────────────────────────────────── */

static void EP(_iowait_apply)(struct EP(_cpu) *epc, u64 time,
			      unsigned int flags)
{
	unsigned int boost_max = epc->ep_policy->policy->cpuinfo.max_freq;

	if (flags & SCHED_CPUFREQ_IOWAIT) {
		if (epc->iowait_boost_pending)
			return;
		epc->iowait_boost_pending = true;
		if (epc->iowait_boost) {
			epc->iowait_boost =
				min(epc->iowait_boost << 1, boost_max);
		} else {
			epc->iowait_boost =
				epc->ep_policy->policy->cpuinfo.min_freq;
		}
		return;
	}
	epc->iowait_boost_pending = false;
}

static unsigned int EP(_iowait_boost_freq)(struct EP(_cpu) *epc,
					   unsigned int freq)
{
	if (!epc->iowait_boost)
		return freq;
	if (epc->iowait_boost_pending) {
		epc->iowait_boost_pending = false;
	} else {
		epc->iowait_boost >>= 1;
		if (epc->iowait_boost < epc->ep_policy->policy->cpuinfo.min_freq) {
			epc->iowait_boost = 0;
			return freq;
		}
	}
	return max(freq, epc->iowait_boost);
}

/* ── Frequency switching ─────────────────────────────────────────────── */

static void EP(_fast_switch)(struct EP(_policy) *ep, u64 time,
			     unsigned int next_freq)
{
	cpufreq_driver_fast_switch(ep->policy, next_freq);
}

static void EP(_work)(struct kthread_work *work)
{
	struct EP(_policy) *ep =
		container_of(work, struct EP(_policy), work);
	unsigned int freq;

	mutex_lock(&ep->work_lock);
	freq = ep->next_freq;
	ep->work_in_progress = false;
	mutex_unlock(&ep->work_lock);

	__cpufreq_driver_target(ep->policy, freq, CPUFREQ_RELATION_L);
}

static void __maybe_unused EP(_irq_work)(struct irq_work *irq)
{
	struct EP(_policy) *ep =
		container_of(irq, struct EP(_policy), irq_work);

	kthread_queue_work(&ep->worker, &ep->work);
}

static void EP(_deferred_update)(struct EP(_policy) *ep)
{
	if (!ep->work_in_progress) {
		ep->work_in_progress = true;
		irq_work_queue(&ep->irq_work);
	}
}

/* ── Update callback ─────────────────────────────────────────────────── */

static void EP(_update_shared)(struct update_util_data *hook, u64 time,
			       unsigned int flags)
{
	struct EP(_cpu) *epc = container_of(hook, struct EP(_cpu), update_util);
	struct EP(_policy) *ep = epc->ep_policy;
	unsigned long util = 0, max_cap = 1;
	unsigned int next_f, j;

	raw_spin_lock(&ep->update_lock);

	EP(_iowait_apply)(epc, time, flags);
	epc->last_update = time;

	if (!EP(_should_update)(ep, time))
		goto unlock;

	/* Aggregate utilization across all CPUs in this policy */
	for_each_cpu(j, ep->policy->cpus) {
		struct EP(_cpu) *j_epc = &per_cpu(EP(_cpu_data), j);

		EP(_get_util)(j_epc);
		if (j_epc->util * max_cap >= j_epc->max * util) {
			util    = j_epc->util;
			max_cap = j_epc->max;
		}
	}

	next_f = EP(_calc_next_freq)(ep, util, max_cap);
	next_f = EP(_iowait_boost_freq)(epc, next_f);

	if (!EP(_update_next_freq)(ep, time, next_f) && !ep->need_freq_update)
		goto unlock;

	ep->need_freq_update = false;

	if (!ep->policy->fast_switch_enabled)
		EP(_deferred_update)(ep);
	else
		EP(_fast_switch)(ep, time, next_f);

unlock:
	raw_spin_unlock(&ep->update_lock);
}

/* ── Sysfs tunables ──────────────────────────────────────────────────── */

static inline struct EP(_tunables) *EP(_to_tunables)(struct gov_attr_set *s)
{
	return container_of(s, struct EP(_tunables), attr_set);
}

#define EPITAPH_TUNABLE_SHOW(attr)					\
static ssize_t EP(_##attr##_show)(struct gov_attr_set *attr_set,	\
				  char *buf)				\
{									\
	return sprintf(buf, "%u\n", EP(_to_tunables)(attr_set)->attr);	\
}

#define EPITAPH_TUNABLE_STORE(attr, min_val, max_val)			\
static ssize_t EP(_##attr##_store)(struct gov_attr_set *attr_set,	\
				   const char *buf, size_t count)	\
{									\
	struct EP(_tunables) *t = EP(_to_tunables)(attr_set);		\
	unsigned int val;						\
	if (kstrtouint(buf, 10, &val))					\
		return -EINVAL;						\
	if (val < (min_val) || val > (max_val))				\
		return -EINVAL;						\
	WRITE_ONCE(t->attr, val);					\
	return count;							\
}

static ssize_t EP(_up_rate_store)(struct gov_attr_set *attr_set,
				  const char *buf, size_t count)
{
	struct EP(_tunables) *t = EP(_to_tunables)(attr_set);
	struct EP(_policy) *ep;
	unsigned int val;

	if (kstrtouint(buf, 10, &val))
		return -EINVAL;

	WRITE_ONCE(t->up_rate_limit_us, val);
	list_for_each_entry(ep, &attr_set->policy_list, tunables_hook)
		EP(_update_rate_limit)(ep, val, t->down_rate_limit_us);
	return count;
}

static ssize_t EP(_down_rate_store)(struct gov_attr_set *attr_set,
				    const char *buf, size_t count)
{
	struct EP(_tunables) *t = EP(_to_tunables)(attr_set);
	struct EP(_policy) *ep;
	unsigned int val;

	if (kstrtouint(buf, 10, &val))
		return -EINVAL;

	WRITE_ONCE(t->down_rate_limit_us, val);
	list_for_each_entry(ep, &attr_set->policy_list, tunables_hook)
		EP(_update_rate_limit)(ep, t->up_rate_limit_us, val);
	return count;
}

EPITAPH_TUNABLE_SHOW(up_rate_limit_us)
EPITAPH_TUNABLE_SHOW(down_rate_limit_us)
EPITAPH_TUNABLE_SHOW(hispeed_load)
EPITAPH_TUNABLE_SHOW(hispeed_freq)
EPITAPH_TUNABLE_SHOW(touch_boost_duration_ms)
EPITAPH_TUNABLE_SHOW(touch_boost_freq)

EPITAPH_TUNABLE_STORE(hispeed_load, 0, 100)
EPITAPH_TUNABLE_STORE(hispeed_freq, 0, UINT_MAX)
EPITAPH_TUNABLE_STORE(touch_boost_duration_ms, 0, 500)
EPITAPH_TUNABLE_STORE(touch_boost_freq, 0, UINT_MAX)

static struct governor_attr EP(_attr_up_rate) = {
	.attr = { .name = "up_rate_limit_us", .mode = 0644 },
	.show  = EP(_up_rate_limit_us_show),
	.store = EP(_up_rate_store),
};

static struct governor_attr EP(_attr_down_rate) = {
	.attr = { .name = "down_rate_limit_us", .mode = 0644 },
	.show  = EP(_down_rate_limit_us_show),
	.store = EP(_down_rate_store),
};

static struct governor_attr EP(_attr_hispeed_load) = {
	.attr = { .name = "hispeed_load", .mode = 0644 },
	.show  = EP(_hispeed_load_show),
	.store = EP(_hispeed_load_store),
};

static struct governor_attr EP(_attr_hispeed_freq) = {
	.attr = { .name = "hispeed_freq", .mode = 0644 },
	.show  = EP(_hispeed_freq_show),
	.store = EP(_hispeed_freq_store),
};

static struct governor_attr EP(_attr_touch_boost_duration) = {
	.attr = { .name = "touch_boost_duration_ms", .mode = 0644 },
	.show  = EP(_touch_boost_duration_ms_show),
	.store = EP(_touch_boost_duration_ms_store),
};

static struct governor_attr EP(_attr_touch_boost_freq) = {
	.attr = { .name = "touch_boost_freq", .mode = 0644 },
	.show  = EP(_touch_boost_freq_show),
	.store = EP(_touch_boost_freq_store),
};

static struct attribute *EP(_attrs)[] = {
	&EP(_attr_up_rate).attr,
	&EP(_attr_down_rate).attr,
	&EP(_attr_hispeed_load).attr,
	&EP(_attr_hispeed_freq).attr,
	&EP(_attr_touch_boost_duration).attr,
	&EP(_attr_touch_boost_freq).attr,
	NULL
};

static const struct attribute_group EP(_attr_group) = {
	.attrs = EP(_attrs),
	.name  = GOV_NAME,
};

static const struct attribute_group *EP(_attr_groups)[] = {
	&EP(_attr_group),
	NULL,
};

static struct kobj_type EP(_kobj_type) = {
	.default_groups = EP(_attr_groups),
	.sysfs_ops      = &governor_sysfs_ops,
};

/* ── Governor lifecycle ──────────────────────────────────────────────── */

static struct EP(_policy) *EP(_policy_alloc)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep;

	ep = kzalloc(sizeof(*ep), GFP_KERNEL);
	if (!ep)
		return NULL;

	ep->policy = policy;
	raw_spin_lock_init(&ep->update_lock);

	hrtimer_init(&ep->boost_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	ep->boost_timer.function = EP(_boost_timer_expire);
	ep->boost_freq_floor = 0;

	return ep;
}

static void EP(_policy_free)(struct EP(_policy) *ep)
{
	hrtimer_cancel(&ep->boost_timer);
	kfree(ep);
}

static int EP(_kthread_create)(struct EP(_policy) *ep)
{
	struct task_struct *thread;
	struct sched_attr attr = { .size = sizeof(struct sched_attr) };
	struct cpufreq_policy *policy = ep->policy;

	kthread_init_work(&ep->work, EP(_work));
	kthread_init_worker(&ep->worker);
	thread = kthread_create(kthread_worker_fn, &ep->worker,
				"epitaph:%d", cpumask_first(policy->related_cpus));
	if (IS_ERR(thread))
		return PTR_ERR(thread);

	attr.sched_policy = SCHED_DEADLINE;
	attr.sched_flags  = SCHED_FLAG_SUGOV;
	attr.sched_runtime = attr.sched_deadline = attr.sched_period =
		1000000; /* 1ms */
	sched_setattr_nocheck(thread, &attr);

	ep->thread = thread;
	kthread_bind_mask(thread, policy->related_cpus);
	wake_up_process(thread);
	return 0;
}

static void EP(_kthread_stop)(struct EP(_policy) *ep)
{
	if (ep->thread) {
		kthread_flush_worker(&ep->worker);
		kthread_stop(ep->thread);
		ep->thread = NULL;
	}
}

static struct EP(_tunables) *EP(_tunables_alloc)(struct EP(_policy) *ep)
{
	struct EP(_tunables) *tunables;

	tunables = kzalloc(sizeof(*tunables), GFP_KERNEL);
	if (!tunables)
		return NULL;

	tunables->up_rate_limit_us        = DEFAULT_UP_RATE;
	tunables->down_rate_limit_us      = DEFAULT_DOWN_RATE;
	tunables->hispeed_load            = DEFAULT_HISPEED_LOAD;
	tunables->hispeed_freq            = DEFAULT_HISPEED_FREQ;
	tunables->touch_boost_duration_ms = DEFAULT_BOOST_DURATION;
	tunables->touch_boost_freq        = 0;

	gov_attr_set_init(&tunables->attr_set, &ep->tunables_hook);

	return tunables;
}

static void *global_tunables;

static void EP(_tunables_free)(struct EP(_tunables) *tunables)
{
	if (!have_governor_per_policy())
		global_tunables = NULL;
	kfree(tunables);
}

static int EP(_init)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep;
	struct EP(_tunables) *tunables;
	int ret;

	if (policy->governor_data)
		return -EBUSY;

	cpufreq_enable_fast_switch(policy);

	ep = EP(_policy_alloc)(policy);
	if (!ep) {
		ret = -ENOMEM;
		goto disable_fast_switch;
	}

	mutex_init(&ep->work_lock);
	init_irq_work(&ep->irq_work, EP(_irq_work));

	ret = EP(_kthread_create)(ep);
	if (ret)
		goto free_ep;

	if (global_tunables) {
		tunables = global_tunables;
		gov_attr_set_get(&tunables->attr_set, &ep->tunables_hook);
	} else {
		tunables = EP(_tunables_alloc)(ep);
		if (!tunables) {
			ret = -ENOMEM;
			goto stop_kthread;
		}
		if (!have_governor_per_policy())
			global_tunables = tunables;
	}

	ep->tunables = tunables;
	EP(_update_rate_limit)(ep, tunables->up_rate_limit_us,
			       tunables->down_rate_limit_us);

	policy->governor_data = ep;

	ret = kobject_init_and_add(&tunables->attr_set.kobj,
				   &EP(_kobj_type), get_governor_parent_kobj(policy),
				   "%s", GOV_NAME);
	if (ret)
		goto free_tunables;

	return 0;

free_tunables:
	EP(_tunables_free)(tunables);
stop_kthread:
	EP(_kthread_stop)(ep);
free_ep:
	EP(_policy_free)(ep);
disable_fast_switch:
	cpufreq_disable_fast_switch(policy);
	return ret;
}

static void EP(_exit)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep = policy->governor_data;
	struct EP(_tunables) *tunables = ep->tunables;
	unsigned int count;

	policy->governor_data = NULL;

	count = gov_attr_set_put(&tunables->attr_set, &ep->tunables_hook);
	if (!count)
		EP(_tunables_free)(tunables);

	EP(_kthread_stop)(ep);
	EP(_policy_free)(ep);
	cpufreq_disable_fast_switch(policy);
}

static int EP(_start)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep = policy->governor_data;
	unsigned int cpu;

	ep->next_freq          = 0;
	ep->last_freq_update_time = 0;
	ep->cached_raw_freq    = 0;
	ep->limits_changed     = false;
	ep->need_freq_update   = false;
	ep->work_in_progress   = false;
	ep->boost_freq_floor   = 0;

	for_each_cpu(cpu, policy->cpus) {
		struct EP(_cpu) *epc = &per_cpu(EP(_cpu_data), cpu);

		memset(epc, 0, sizeof(*epc));
		epc->cpu       = cpu;
		epc->ep_policy = ep;
		cpufreq_add_update_util_hook(cpu, &epc->update_util,
					     EP(_update_shared));
	}

	ep->boost_entry.boost_fn = EP(_boost_kick);
	ep->boost_entry.data     = ep;
	epitaph_boost_register(&ep->boost_entry);

	return 0;
}

static void EP(_stop)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep = policy->governor_data;
	unsigned int cpu;

	epitaph_boost_unregister(&ep->boost_entry);
	hrtimer_cancel(&ep->boost_timer);
	WRITE_ONCE(ep->boost_freq_floor, 0);

	for_each_cpu(cpu, policy->cpus)
		cpufreq_remove_update_util_hook(cpu);

	synchronize_rcu();

	if (!policy->fast_switch_enabled) {
		irq_work_sync(&ep->irq_work);
		kthread_cancel_work_sync(&ep->work);
	}
}

static void EP(_limits)(struct cpufreq_policy *policy)
{
	struct EP(_policy) *ep = policy->governor_data;

	if (!policy->fast_switch_enabled) {
		mutex_lock(&ep->work_lock);
		cpufreq_policy_apply_limits(policy);
		mutex_unlock(&ep->work_lock);
	}

	ep->limits_changed = true;
}

/* ── Governor registration ───────────────────────────────────────────── */

static struct cpufreq_governor EP(_governor) = {
	.name   = GOV_NAME,
	.owner  = THIS_MODULE,
	.flags  = CPUFREQ_GOV_DYNAMIC_SWITCHING,
	.init   = EP(_init),
	.exit   = EP(_exit),
	.start  = EP(_start),
	.stop   = EP(_stop),
	.limits = EP(_limits),
};

static int __init EP(_register)(void)
{
	return cpufreq_register_governor(&EP(_governor));
}
fs_initcall(EP(_register));

static void __exit EP(_unregister)(void)
{
	cpufreq_unregister_governor(&EP(_governor));
}
module_exit(EP(_unregister));

#endif /* _CPUFREQ_EPITAPH_COMMON_H */
