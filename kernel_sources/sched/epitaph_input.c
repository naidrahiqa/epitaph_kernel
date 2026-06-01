// SPDX-License-Identifier: GPL-2.0
/*
 * epitaph_input.c — Input Event Touch, Sched Fork Launch, & Thermal Boost Coordinator
 * Copyright (C) 2026 Naidrahiqa & Antigravity AI
 *
 * Implements interactive touch boost, cold-start app launch boost, and
 * a thermal governor handoff coordinator. Reads thermal pressure and zone
 * telemetry every 500ms, adjusting active boost behaviors and clock caps.
 */

#include <linux/init.h>
#include <linux/input.h>
#include <linux/module.h>
#include <linux/spinlock.h>
#include <linux/hrtimer.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/tracepoint.h>
#include <linux/workqueue.h>
#include <linux/thermal.h>
#include <linux/sched/cputime.h>
#include <trace/events/sched.h>

#include "sched.h"
#include "epitaph_input.h"

/* ── Tunable module parameters ──────────────────────────────────────── */

static bool enabled = true;
module_param(enabled, bool, 0644);
MODULE_PARM_DESC(enabled, "Enable overall touch and launch boost (default: 1)");

static bool launch_boost_enabled = true;
module_param(launch_boost_enabled, bool, 0644);
MODULE_PARM_DESC(launch_boost_enabled, "Enable app launch boost on task forks (default: 1)");

/* ── Thermal Handoff Globals ────────────────────────────────────────── */

unsigned int epitaph_thermal_state = 0;       /* 0=cool, 1=warm, 2=hot */
EXPORT_SYMBOL_GPL(epitaph_thermal_state);

unsigned int epitaph_thermal_ceiling_pct = 100; /* Dynamic cap (75-100%) during cooldown recovery */
EXPORT_SYMBOL_GPL(epitaph_thermal_ceiling_pct);

/* ── Global boost state coordinator ─────────────────────────────────── */

static DEFINE_SPINLOCK(boost_lock);
static LIST_HEAD(boost_list);
static unsigned int active_boost_type = EPITAPH_BOOST_NONE;
static struct hrtimer boost_state_timer;

static enum hrtimer_restart boost_state_timer_expire(struct hrtimer *timer)
{
	unsigned long flags;

	spin_lock_irqsave(&boost_lock, flags);
	active_boost_type = EPITAPH_BOOST_NONE;
	spin_unlock_irqrestore(&boost_lock, flags);

	return HRTIMER_NORESTART;
}

static void epitaph_boost_kick_all(unsigned int type)
{
	struct epitaph_boost_entry *entry;
	unsigned long flags;

	spin_lock_irqsave(&boost_lock, flags);
	list_for_each_entry(entry, &boost_list, node) {
		if (entry->boost_fn)
			entry->boost_fn(entry->data, type);
	}
	spin_unlock_irqrestore(&boost_lock, flags);
}

static void epitaph_trigger_boost(unsigned int type, unsigned int duration_ms)
{
	unsigned long flags;

	if (!enabled)
		return;

	if (type == EPITAPH_BOOST_LAUNCH && !launch_boost_enabled)
		return;

	/* Thermal Overrides: disable all boosts in HOT thermal state */
	if (READ_ONCE(epitaph_thermal_state) == 2)
		return;

	spin_lock_irqsave(&boost_lock, flags);

	/* Boost stacking protection: Touch boost takes priority over launch boost */
	if (active_boost_type == EPITAPH_BOOST_TOUCH && type == EPITAPH_BOOST_LAUNCH) {
		spin_unlock_irqrestore(&boost_lock, flags);
		return;
	}

	active_boost_type = type;
	spin_unlock_irqrestore(&boost_lock, flags);

	/* Propagate trigger to registered governor policies */
	epitaph_boost_kick_all(type);

	/* Arm state expiration timer */
	hrtimer_start(&boost_state_timer, ms_to_ktime(duration_ms),
		      HRTIMER_MODE_REL_PINNED);
}

void epitaph_boost_register(struct epitaph_boost_entry *entry)
{
	unsigned long flags;

	INIT_LIST_HEAD(&entry->node);
	spin_lock_irqsave(&boost_lock, flags);
	list_add_tail(&entry->node, &boost_list);
	spin_unlock_irqrestore(&boost_lock, flags);
}
EXPORT_SYMBOL_GPL(epitaph_boost_register);

void epitaph_boost_unregister(struct epitaph_boost_entry *entry)
{
	unsigned long flags;

	spin_lock_irqsave(&boost_lock, flags);
	list_del_init(&entry->node);
	spin_unlock_irqrestore(&boost_lock, flags);
}
EXPORT_SYMBOL_GPL(epitaph_boost_unregister);

/* ── Sched Fork App Launch Boost Hook ──────────────────────────────── */

static void epitaph_sched_fork_probe(void *data, struct task_struct *parent,
				     struct task_struct *child)
{
	unsigned int cpu = smp_processor_id();
	unsigned long util = cpu_util_cfs_boost(cpu);
	unsigned long max = arch_scale_cpu_capacity(cpu);

	/* Only trigger launch boost if cpu capacity indicates active foreground load (>40%) */
	if (max > 0 && (util * 100 / max) > 40) {
		/* Kick launch boost: up to 500ms maximum duration */
		epitaph_trigger_boost(EPITAPH_BOOST_LAUNCH, 500);
	}
}

/* ── Input Event Touch Boost Handler ────────────────────────────────── */

static void epitaph_input_event(struct input_handle *handle,
				unsigned int type, unsigned int code,
				int value)
{
	if (!enabled || value <= 0)
		return;

	/* Touch press or movement ABS coordinates trigger interactive boost */
	if (type == EV_ABS &&
	    (code == ABS_MT_TRACKING_ID || code == ABS_MT_POSITION_X))
		epitaph_trigger_boost(EPITAPH_BOOST_TOUCH, 100);
	else if (type == EV_KEY && code == BTN_TOUCH)
		epitaph_trigger_boost(EPITAPH_BOOST_TOUCH, 100);
}

static bool epitaph_input_match(struct input_handler *handler,
				struct input_dev *dev)
{
	if (test_bit(EV_ABS, dev->evbit) &&
	    (test_bit(ABS_MT_POSITION_X, dev->absbit) ||
	     test_bit(ABS_MT_TOUCH_MAJOR, dev->absbit)))
		return true;
	return false;
}

static int epitaph_input_connect(struct input_handler *handler,
				 struct input_dev *dev,
				 const struct input_device_id *id)
{
	struct input_handle *handle;
	int ret;

	handle = kzalloc(sizeof(*handle), GFP_KERNEL);
	if (!handle)
		return -ENOMEM;

	handle->dev = dev;
	handle->handler = handler;
	handle->name = "epitaph_touch";

	ret = input_register_handle(handle);
	if (ret)
		goto free_handle;

	ret = input_open_device(handle);
	if (ret)
		goto unreg_handle;

	return 0;

unreg_handle:
	input_unregister_handle(handle);
free_handle:
	kfree(handle);
	return ret;
}

static void epitaph_input_disconnect(struct input_handle *handle)
{
	input_close_device(handle);
	input_unregister_handle(handle);
	kfree(handle);
}

static const struct input_device_id epitaph_input_ids[] = {
	{ .driver_info = 1 },
	{ },
};

static struct input_handler epitaph_input_handler = {
	.event      = epitaph_input_event,
	.match      = epitaph_input_match,
	.connect    = epitaph_input_connect,
	.disconnect = epitaph_input_disconnect,
	.name       = "epitaph_touch_boost",
	.id_table   = epitaph_input_ids,
};

/* ── Asynchronous Thermal Handoff Worker ────────────────────────────── */

static struct delayed_work epitaph_thermal_work;

static void epitaph_thermal_work_fn(struct work_struct *work)
{
	unsigned long pressure = arch_scale_thermal_pressure(0);
	unsigned int pressure_pct = (pressure * 100) >> 10;
	int temp_c = 0;
	struct thermal_zone_device *tz;
	unsigned int target_state = 0; /* COOL */

	/* Fallback: Query standard MediaTek/GKI CPU thermal zone nodes */
	tz = thermal_zone_get_zone_by_name("cpu-thermal");
	if (!tz)
		tz = thermal_zone_get_zone_by_name("soc-thermal");
	if (!tz)
		tz = thermal_zone_get_zone_by_name("mtktsAP");

	if (tz) {
		int temp_raw = 0;
		if (thermal_zone_get_temp(tz, &temp_raw) == 0)
			temp_c = temp_raw / 1000;
	}

	/* Evaluate unified thermal states */
	if (pressure_pct > 60 || temp_c > 52) {
		target_state = 2; /* HOT */
	} else if (pressure_pct > 20 || temp_c > 42) {
		target_state = 1; /* WARM */
	}

	/* State and Cap Transition Management */
	if (target_state == 2) {
		/* HOT: Hard throttle cap (75% limit) instantly */
		WRITE_ONCE(epitaph_thermal_state, 2);
		WRITE_ONCE(epitaph_thermal_ceiling_pct, 75);
	} else if (target_state == 1) {
		WRITE_ONCE(epitaph_thermal_state, 1);
		/* Cooldown recovery: increase ceiling by 5% every 500ms */
		if (READ_ONCE(epitaph_thermal_ceiling_pct) < 100) {
			unsigned int next_ceiling = min(100U, READ_ONCE(epitaph_thermal_ceiling_pct) + 5);
			WRITE_ONCE(epitaph_thermal_ceiling_pct, next_ceiling);
		}
	} else {
		/* COOL */
		WRITE_ONCE(epitaph_thermal_state, 0);
		/* Cooldown recovery: increase ceiling by 5% every 500ms */
		if (READ_ONCE(epitaph_thermal_ceiling_pct) < 100) {
			unsigned int next_ceiling = min(100U, READ_ONCE(epitaph_thermal_ceiling_pct) + 5);
			WRITE_ONCE(epitaph_thermal_ceiling_pct, next_ceiling);
		}
	}

	schedule_delayed_work(&epitaph_thermal_work, msecs_to_jiffies(500));
}

/* ── Sysfs State Interface ──────────────────────────────────────────── */

static struct kobject *epitaph_kobj;

static ssize_t boost_state_show(struct kobject *kobj,
				struct kobj_attribute *attr, char *buf)
{
	const char *state_str = "none";
	unsigned long flags;

	spin_lock_irqsave(&boost_lock, flags);
	if (active_boost_type == EPITAPH_BOOST_TOUCH)
		state_str = "touch";
	else if (active_boost_type == EPITAPH_BOOST_LAUNCH)
		state_str = "launch";
	spin_unlock_irqrestore(&boost_lock, flags);

	return sprintf(buf, "%s\n", state_str);
}

static ssize_t thermal_state_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	const char *state_str = "cool";
	unsigned int state = READ_ONCE(epitaph_thermal_state);

	if (state == 1)
		state_str = "warm";
	else if (state == 2)
		state_str = "hot";

	return sprintf(buf, "%s\n", state_str);
}

static struct kobj_attribute boost_state_attr = __ATTR_RO(boost_state);
static struct kobj_attribute thermal_state_attr = __ATTR_RO(thermal_state);

/* ── Module lifecycle ───────────────────────────────────────────────── */

static int __init epitaph_boost_init(void)
{
	int ret;

	/* Setup global state expiry timer */
	hrtimer_init(&boost_state_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	boost_state_timer.function = boost_state_timer_expire;

	/* Register input event touchscreen interceptor */
	ret = input_register_handler(&epitaph_input_handler);
	if (ret)
		return ret;

	/* Register sched process fork tracepoint probe */
	ret = register_trace_sched_process_fork(epitaph_sched_fork_probe, NULL);
	if (ret) {
		input_unregister_handler(&epitaph_input_handler);
		return ret;
	}

	/* Initialize and run asynchronous thermal monitor */
	INIT_DELAYED_WORK(&epitaph_thermal_work, epitaph_thermal_work_fn);
	schedule_delayed_work(&epitaph_thermal_work, msecs_to_jiffies(500));

	/* Expose global status nodes under /sys/kernel/epitaph/ */
	epitaph_kobj = kobject_create_and_add("epitaph", kernel_kobj);
	if (epitaph_kobj) {
		ret = sysfs_create_file(epitaph_kobj, &boost_state_attr.attr);
		if (ret == 0) {
			ret = sysfs_create_file(epitaph_kobj, &thermal_state_attr.attr);
			if (ret)
				sysfs_remove_file(epitaph_kobj, &boost_state_attr.attr);
		}
		if (ret) {
			kobject_put(epitaph_kobj);
			epitaph_kobj = NULL;
		}
	}

	return 0;
}

static void __exit epitaph_boost_exit(void)
{
	/* Cancel thermal monitor loop */
	cancel_delayed_work_sync(&epitaph_thermal_work);

	/* Deregister tracepoints */
	unregister_trace_sched_process_fork(epitaph_sched_fork_probe, NULL);
	
	/* Unregister input device intercepts */
	input_unregister_handler(&epitaph_input_handler);

	/* Clean up state timers */
	hrtimer_cancel(&boost_state_timer);

	/* Remove telemetry nodes */
	if (epitaph_kobj) {
		sysfs_remove_file(epitaph_kobj, &thermal_state_attr.attr);
		sysfs_remove_file(epitaph_kobj, &boost_state_attr.attr);
		kobject_put(epitaph_kobj);
	}
}

module_init(epitaph_boost_init);
module_exit(epitaph_boost_exit);

MODULE_AUTHOR("Naidrahiqa");
MODULE_DESCRIPTION("Epitaph Kernel Boost & Thermal Handoff Coordinator");
MODULE_LICENSE("GPL");
