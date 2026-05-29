"""
Epitaph Governor Integration Script
Copies the custom cpufreq governor source files and boost driver into the kernel tree
and patches Kconfig + Makefile to register them.

Called from prepare_kernel_build.sh or patch_build_system() after repo sync.
Must run from kernel/common/ working directory.
"""

import os
import shutil
import sys

WORKSPACE = os.environ.get("GITHUB_WORKSPACE", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SOURCE_DIR = os.path.join(WORKSPACE, "kernel_sources", "sched")
TARGET_DIR = os.path.join("kernel", "sched")

# Governor and boost source files to copy
GOVERNOR_FILES = [
    "cpufreq_epitaph_common.h",
    "cpufreq_epitaph.c",
    "cpufreq_epitaph_perf.c",
    "cpufreq_epitaph_save.c",
    "epitaph_input.h",
    "epitaph_input.c",
]

# Kconfig entries to inject into drivers/cpufreq/Kconfig
KCONFIG_BLOCK = """
config CPU_FREQ_GOV_EPITAPH
	bool "'epitaph' cpufreq governor (balanced)"
	select CPU_FREQ_GOV_ATTR_SET
	help
	  Epitaph balanced governor for Redmi 12 / Helio G88.
	  Schedutil fork with hispeed boost and separate up/down rate limits.
	  Recommended as the default governor for everyday use.

config CPU_FREQ_GOV_EPITAPH_PERF
	bool "'epitaph_performance' cpufreq governor"
	select CPU_FREQ_GOV_ATTR_SET
	help
	  Epitaph performance governor. Aggressive ramp-up for gaming workloads.
	  Near-instant frequency scaling with extended high-freq hold.

config CPU_FREQ_GOV_EPITAPH_SAVE
	bool "'epitaph_powersave' cpufreq governor"
	select CPU_FREQ_GOV_ATTR_SET
	help
	  Epitaph powersave governor. Conservative scaling to maximize battery.
	  Slow ramp-up, fast ramp-down, high hispeed threshold.

config CPU_FREQ_EPITAPH_INPUT_BOOST
	bool "Epitaph CPU touch & launch boost driver"
	default y
	help
	  Touch boost matching input subsystem device movements,
	  plus sched fork launch boost matching foreground task forks.
"""

# Makefile entries to inject into kernel/sched/Makefile
MAKEFILE_LINES = [
    "obj-$(CONFIG_CPU_FREQ_GOV_EPITAPH)      += cpufreq_epitaph.o",
    "obj-$(CONFIG_CPU_FREQ_GOV_EPITAPH_PERF) += cpufreq_epitaph_perf.o",
    "obj-$(CONFIG_CPU_FREQ_GOV_EPITAPH_SAVE) += cpufreq_epitaph_save.o",
    "obj-$(CONFIG_CPU_FREQ_EPITAPH_INPUT_BOOST) += epitaph_input.o",
]


def copy_sources():
    """Copy governor source files into kernel/sched/."""
    if not os.path.isdir(TARGET_DIR):
        print(f"ERROR: Target directory {TARGET_DIR} not found")
        sys.exit(1)

    for fname in GOVERNOR_FILES:
        src = os.path.join(SOURCE_DIR, fname)
        dst = os.path.join(TARGET_DIR, fname)
        if not os.path.isfile(src):
            print(f"ERROR: Source file missing: {src}")
            sys.exit(1)
        shutil.copy2(src, dst)
        print(f"  ✅ Copied {fname} -> {TARGET_DIR}/")


def patch_kconfig():
    """Inject Kconfig entries into drivers/cpufreq/Kconfig."""
    kconfig_path = os.path.join("drivers", "cpufreq", "Kconfig")
    if not os.path.isfile(kconfig_path):
        print(f"WARNING: {kconfig_path} not found, skipping Kconfig patch")
        return

    with open(kconfig_path, "r") as f:
        content = f.read()

    if "CPU_FREQ_GOV_EPITAPH" in content:
        print("  ℹ️ Kconfig already contains Epitaph entries, skipping")
        return

    # Insert before the final 'endmenu' or at end of file
    idx = content.rfind("endmenu")
    if idx != -1:
        content = content[:idx] + KCONFIG_BLOCK + "\n" + content[idx:]
    else:
        content += KCONFIG_BLOCK

    with open(kconfig_path, "w") as f:
        f.write(content)
    print("  ✅ Patched drivers/cpufreq/Kconfig with governor & boost entries")


def patch_makefile():
    """Inject obj-y lines into kernel/sched/Makefile."""
    makefile_path = os.path.join(TARGET_DIR, "Makefile")
    if not os.path.isfile(makefile_path):
        print(f"WARNING: {makefile_path} not found, skipping Makefile patch")
        return

    with open(makefile_path, "r") as f:
        content = f.read()

    if "cpufreq_epitaph" in content:
        print("  ℹ️ Makefile already contains Epitaph entries, skipping")
        return

    # Find the schedutil line and append after it
    lines = content.split("\n")
    insert_idx = len(lines)
    for i, line in enumerate(lines):
        if "cpufreq_schedutil" in line:
            insert_idx = i + 1
            break

    for ml in reversed(MAKEFILE_LINES):
        lines.insert(insert_idx, ml)

    with open(makefile_path, "w") as f:
        f.write("\n".join(lines))
    print("  ✅ Patched kernel/sched/Makefile with governor & boost build rules")


def main():
    print("🔧 Integrating Epitaph CPU governors & boost coordinator into kernel tree...")
    copy_sources()
    patch_kconfig()
    patch_makefile()
    print("✅ Epitaph governor & boost integration complete")


if __name__ == "__main__":
    main()
