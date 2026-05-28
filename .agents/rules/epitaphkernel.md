---
trigger: always_on
---

# Epitaph Kernel — Workspace Rule
# Redmi 12 (fire) · Android 15 HyperOS 2.0 · GKI 6.6

## Project Identity
- Kernel name: Epitaph
- Device: Xiaomi Redmi 12, codename `fire`, chipset Helio G88 (MT6769)
- OS: Android 15 HyperOS 2.0
- Build system: Bazel/Kleaf (primary), make-based custom toolchains (experimental)
- Root method: KernelSU-Next only (pershoot/KernelSU-Next branch dev-susfs for SUSFS builds, KernelSU-Next/KernelSU-Next branch dev for No-SUSFS builds)
- CI/CD: GitHub Actions, multi-toolchain matrix

## Key Files — Know These Before Touching Anything
- `scripts/prepare_kernel_build.sh` — disk cleanup, deps, repo sync, KSU setup
- `scripts/epitaph_tuner.sh` — post-boot optimizer shipped in AnyKernel3
- `.github/workflows/_build_kernel_core.yml` — core build recipe
- `.github/workflows/build_manager_gki.yml` — matrix dispatcher
- `.github/workflows/build_debug_bootimg.yml` — rescue kernel builder
- `workflow_scripts/patch_build_system.py` — registers WiFi modules in BUILD.bazel
- `workflow_scripts/patch_vermagic.py` — bypasses vermagic for stock Xiaomi modules
- `workflow_scripts/patch_kbuild.py` — injects static KSU version into Kbuild

## ABSOLUTE RULES — NEVER VIOLATE
1. No custom recovery (TWRP/OrangeFox) exists — never suggest it
2. Never enable `CONFIG_DEBUG_INFO_NONE=y` — kills WiFi/BPF on Android 15
3. Never enable MTK built-in WiFi (`CONFIG_MTK_COMBO_WIFI=y`) — instant bootloop
4. `CONFIG_ZSMALLOC=m` and `CONFIG_ZRAM=m` must stay as modules — Bazel tracks them
5. `CONFIG_KPROBES=y` + `CONFIG_HAVE_KPROBES=y` + `CONFIG_KPROBE_EVENTS=y` — always on, required by KSU
6. `--lto=thin` always in Bazel — ThinLTO is proven stable under GKI 6.6 with 6GB limits
7. `--local_resources=memory=6144` in Bazel — never `--local_ram_resources` (deprecated)
8. AnyKernel3 `supported.versions=15` only — GKI 6.6 incompatible with Android 14
9. Never lock kernel to old commits — always tip of branch `common-android15-6.6`
10. `CONFIG_ARM64_4K_PAGES=y` must stay — vendor modules compiled for 4K only
11. `CONFIG_MODVERSIONS=y` must stay — vendor DLKM compatibility
12. Never remove `patch_vermagic.py` — allows stock Xiaomi modules to load
13. Kernel image priority in AnyKernel3: `Image.gz` → `Image.lz4` → `Image`
14. After any `git add` in SUSFS setup — must `git commit` before Bazel runs

## SUSFS — The Long-Standing Bug
- SUSFS builds have failed from v1 through v129
- Root causes identified:
  1. Wrong KSU source: must use `pershoot/KernelSU-Next` branch `dev-susfs` (pre-patched) for SUSFS builds, and `KernelSU-Next/KernelSU-Next` branch `dev` for No-SUSFS builds
  2. Bazel reads from git HEAD not staging — always commit after `git add`
  3. `SUSFS_INTEGRATED` was always true regardless of patch success — now fixed
- The `50_add_susfs_in_kernel.patch` (kernel side) still needs to be applied manually
- The `10_enable_susfs_for_ksu.patch` (KSU side) is SKIPPED — pershoot handles it
- sidex15/susfs4ksu-module and sidex15/susfs4ksu-binaries are USERSPACE tools — not needed at build time

## Build System Quirks
- Bazel sandbox reads committed git tree only — unstaged/staged changes are invisible
- `patch_vermagic.py` patches `same_magic()` to always return 1
- `patch_build_system.py` injects cfg80211.ko and mac80211.ko into BUILD.bazel module_outs
- KMI enforcement is disabled via `kmi_symbol_list_strict_mode = False`
- WiFi must stay modular: `CONFIG_CFG80211=m`, `CONFIG_MAC80211=m`

## Epitaph Schedutil Performance — 3 Profiles
- Managed at runtime via `/data/adb/epitaph/mode` file
- Profiles: `performance` (gaming), `balanced` (default), `battery` (power saving)
- Apply without reboot: `echo performance > /data/adb/epitaph/mode && sh /data/adb/epitaph/apply`
- Kernel patch: `patches/epitaph_schedutil.patch` — unlocks rate limit minimum to 100µs
- New sysfs nodes: `epitaph_boost_threshold` and `epitaph_boost_factor` per cpufreq policy

## Debugging Workflow
- No custom recovery — use PStore/RAMoops for crash logs
- Pull crash log from PC after flashing stock boot: `adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt`
- Rescue kernel (`build_debug_bootimg.yml`) always boots — use it to pull logs after main kernel bootloops
- Never flash multiple boot images via Fastboot back-to-back — wipes RAMoops

## Inline Comment Language
- Indonesian for comments in shell scripts and workflow YAML (matching existing codebase)
- English for C kernel patches and Python scripts