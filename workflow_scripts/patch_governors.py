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
	bool "'epitaph_perf' cpufreq governor"
	select CPU_FREQ_GOV_ATTR_SET
	help
	  Epitaph performance governor. Aggressive ramp-up for gaming workloads.
	  Near-instant frequency scaling with extended high-freq hold.

config CPU_FREQ_GOV_EPITAPH_SAVE
	bool "'epitaph_save' cpufreq governor"
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

# Default governor choice entry for Kconfig
# This must be injected into the existing "choice" block for "Default CPUFreq governor"
DEFAULT_GOV_CHOICE_ENTRY = """
config CPU_FREQ_DEFAULT_GOV_EPITAPH
    bool "'epitaph' as default governor"
    depends on CPU_FREQ_GOV_EPITAPH
    help
      Use the Epitaph balanced governor as the default CPU frequency governor.
      This is a schedutil fork optimized for Redmi 12 / Helio G88.
"""


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


def patch_default_governor_choice():
    """Inject CONFIG_CPU_FREQ_DEFAULT_GOV_EPITAPH into the existing default governor choice block."""
    kconfig_path = os.path.join("drivers", "cpufreq", "Kconfig")
    if not os.path.isfile(kconfig_path):
        print(f"WARNING: {kconfig_path} not found, skipping default governor choice patch")
        return

    with open(kconfig_path, "r") as f:
        lines = f.readlines()

    if any("CPU_FREQ_DEFAULT_GOV_EPITAPH" in line for line in lines):
        print("  ℹ️ Default governor choice already contains Epitaph entry, skipping")
        return

    # Find the choice block containing default governor options using line-by-line parsing
    # Strategy: find "choice" with "Default CPUFreq governor" prompt, then find the last config before endchoice
    in_choice_block = False
    choice_start_idx = -1
    choice_end_idx = -1
    last_config_idx = -1

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("choice") and i + 1 < len(lines):
            # Check if this choice block has the "Default CPUFreq governor" prompt
            for j in range(i + 1, min(i + 5, len(lines))):
                if "Default CPUFreq governor" in lines[j]:
                    in_choice_block = True
                    choice_start_idx = i
                    break
        if in_choice_block:
            if stripped.startswith("config CPU_FREQ_DEFAULT_GOV_"):
                last_config_idx = i
            if stripped == "endchoice":
                choice_end_idx = i
                break

    if choice_start_idx != -1 and choice_end_idx != -1 and last_config_idx != -1:
        # Find the end of the last config block before endchoice
        insert_idx = last_config_idx + 1
        # Skip past the help text and any blank lines of the last config
        while insert_idx < choice_end_idx:
            if lines[insert_idx].strip().startswith("config ") or lines[insert_idx].strip() == "endchoice":
                break
            insert_idx += 1

        # Insert the Epitaph choice entry
        entry_lines = DEFAULT_GOV_CHOICE_ENTRY.strip().split("\n")
        for k, entry_line in enumerate(reversed(entry_lines)):
            lines.insert(insert_idx, entry_line + "\n")

        with open(kconfig_path, "w") as f:
            f.writelines(lines)
        print("  ✅ Patched drivers/cpufreq/Kconfig with default governor choice entry for Epitaph")
        return

    print("  ⚠️ Could not find default governor choice block in drivers/cpufreq/Kconfig")
    print("     CONFIG_CPU_FREQ_DEFAULT_GOV_EPITAPH may not work as expected")


def main():
    print("🔧 Integrating Epitaph CPU governors & boost coordinator into kernel tree...")
    copy_sources()
    patch_kconfig()
    patch_default_governor_choice()
    patch_makefile()
    print("✅ Epitaph governor & boost integration complete")


if __name__ == "__main__":
    main()
