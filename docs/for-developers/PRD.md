# PRD — Epitaph Kernel
**Product Requirements Document**
> This document is the **source of truth** for all technical decisions in the Epitaph Kernel project.
> Anyone (human or AI) who wants to touch this repository **must read this document first**.
> If there is a conflict between this document and other instructions, this document wins.

---

## 1. Product Overview

**Epitaph Kernel** is a custom GKI 6.6 kernel designed for the **Xiaomi Redmi 12 (codename: fire)** running **Android 15 HyperOS 2.0**.

Built from Google's `common-android15-6.6` branch, it is automatically compiled via a GitHub Actions multi-toolchain pipeline, and shipped as an AnyKernel3 ZIP package to be flashed via **KernelFlasher** (no custom recovery like TWRP/OrangeFox is available or supported for this device).

### Who are the users?
- **Developer (maintainer):** Faqih Ardian Syah (@naidrahiqa) — the sole maintainer.
- **AI pair programmers:** Antigravity, Claude, Gemini, DeepSeek, Qwen — who must read this PRD as a mandatory context helper.
- **End users:** Redmi 12 owners who wish to install a highly optimized custom kernel.

### What is the value proposition?
The stock HyperOS 2.0 kernel lacks root compatibility and performance tuning. Epitaph delivers:
1. Kernel-level root via KernelSU-Next (safer and cleaner than Magisk).
2. Optional root-hiding capabilities via SUSFS (for banking/corporate apps).
3. Optimized performance: TCP BBR, BFQ I/O scheduling, custom tuned schedutil governor, ZRAM ZSTD.
4. Highly stable WiFi & Hotspot (a historical issue for GKI builds on this device).
5. Post-boot tuner (Epitaph Schedutil Performance) with 3 runtime profiles.

---

## 2. Device Context — MANDATORY TO UNDERSTAND

| Field | Value |
|---|---|
| Device | Xiaomi Redmi 12 4G |
| Codename | `fire` |
| Chipset | MediaTek Helio G88 (MT6769), 12nm |
| CPU | 2×Cortex-A75 @ 2.0GHz + 6×Cortex-A55 @ 1.8GHz |
| GPU | Mali-G52 MC2 |
| RAM | 4 / 6 / 8 GB LPDDR4x |
| Target OS | Android 15 HyperOS 2.0 **ONLY** |
| Kernel Branch | `common-android15-6.6` (always tip of branch) |
| KMI Version | android15-8 |
| Partitions | A/B seamless, Dynamic (super) |
| Page Size | 4K (mandatory, as vendor modules are compiled for 4K page size) |

### Panel Variants (CRITICAL)
This device ships with 4 different LCD panel variants:
- **LC0A / LC0B** — kernel source code is available and fully supported ✅.
- **LC0C / LC0D** — Xiaomi has NOT yet released source code (GPL violation), hence not supported ❌.

Users can identify their panel variant using: `adb shell getprop ro.boot.lcm_name`

---

## 3. System Architecture

### 3.1 Repository Structure

```
epitaph_kernel/
├── .github/workflows/
│   ├── _build_kernel_core.yml      ← Core compilation workflow recipe
│   ├── build_manager_gki.yml       ← Dispatcher matrix workflow
│   └── build_debug_bootimg.yml     ← Rescue kernel builder
├── scripts/
│   ├── prepare_kernel_build.sh     ← CI disk setup, dependencies, sync, and KSU setup
│   └── epitaph_tuner.sh            ← Post-boot performance script packaged in AnyKernel3
├── workflow_scripts/
│   ├── patch_build_system.py       ← Registers WiFi modules inside BUILD.bazel
│   ├── patch_vermagic.py           ← Bypasses vermagic for stock Xiaomi modules
│   └── patch_kbuild.py             ← Injects a static KernelSU-Next version into Kbuild
├── patches/                        ← Custom patch files (applied via patch -p1)
│   └── epitaph_schedutil.patch     ← Unlocks the schedutil rate limit minimum to 100µs
└── guidelines/                     ← Topically organized developer guidelines
```

### 3.2 CI/CD Pipeline

```
Trigger: workflow_dispatch (manual)
         └── build_manager_gki.yml
               ├── prepare: generate matrix (toolchain × SUSFS variant)
               ├── notify_start: Telegram start notification
               ├── trigger: _build_kernel_core.yml (parallel execution, max 4 runs)
               │     ├── prepare_kernel_build.sh
               │     │     ├── maximize_disk
               │     │     ├── setup_swap (16GB)
               │     │     ├── install_deps
               │     │     ├── install_repo
               │     │     ├── download_toolchain (if custom compiler is active)
               │     │     ├── sync_kernel (repo sync common-android15-6.6)
               │     │     ├── set_kmi
               │     │     ├── setup_ksu (pershoot/KernelSU-Next branch next-susfs)
               │     │     ├── apply_patches
               │     │     └── patch_build_system
               │     ├── Setup SUSFS (if with_susfs=true)
               │     ├── Configure Kernel (defconfig manipulation)
               │     ├── Build (Bazel OR Custom Clang)
               │     ├── Extract Build Output
               │     ├── Verify Build Correctness
               │     ├── Package AnyKernel3
               │     ├── Upload Artifacts
               │     ├── Create GitHub Release
               │     └── Telegram notify (success/failure)
               └── summary: final overall build status report
```

### 3.3 Toolchain Matrix

| Toolchain | Build System | Status | Notes |
|---|---|---|---|
| `bazel-default` | Bazel/Kleaf | ✅ **Production** | The only officially production-tested system |
| `aosp-latest` | make | ⚠️ Experimental | crdroidandroid prebuilt Clang |
| `zyc-latest` | make | ⚠️ Experimental | ZyClang toolchain |
| `weebx-latest` | make | ⚠️ Experimental | WeebX Clang toolchain |
| `neutron-latest` | make | ⚠️ Experimental | Neutron Clang toolchain |

**Crucial:** Bazel and custom Clang make-based compilations must be kept isolated. Do not symlink or inject custom compilers into Bazel prebuilt compiler paths.

---

## 4. Features & Project Status

### 4.1 Root & Security

| Feature | Status | Implementation Details |
|---|---|---|
| KernelSU-Next | ✅ Always Included | `pershoot/KernelSU-Next` branch `next-susfs` |
| SUSFS for KSU | ✅ Optional Variant | `simonpunk/susfs4ksu` branch `gki-android15-6.6` |
| Vermagic bypass | ✅ Always Active | `workflow_scripts/patch_vermagic.py` |

**Correct SUSFS Integration Setup:**
- KSU side: `pershoot/KernelSU-Next` branch `next-susfs` is pre-patched; `10_enable_susfs_for_ksu.patch` must be SKIPPED.
- Kernel side: `simonpunk/susfs4ksu` — manually apply `50_add_susfs_in_kernel.patch`.
- Staged commits: Always run `git commit` after adding SUSFS changes, as the Bazel sandbox only tracks files committed in HEAD.

### 4.2 Performance Tuning

| Feature | Kernel Config | Status |
|---|---|---|
| CPU Governor | `CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y` | ✅ Enabled |
| TCP BBR | `CONFIG_TCP_CONG_BBR=y` + `CONFIG_NET_SCH_FQ=y` | ✅ Enabled |
| I/O BFQ | `CONFIG_IOSCHED_BFQ=y` | ✅ Enabled |
| I/O Kyber | `CONFIG_MQ_IOSCHED_KYBER=y` | ✅ Enabled |
| Timer HZ=300 | `CONFIG_HZ_300=y` | ✅ Enabled |
| WireGuard | `CONFIG_WIREGUARD=y` | ✅ Enabled |
| MGLRU | `CONFIG_LRU_GEN=y` | ✅ Enabled |
| ZRAM ZSTD | `CONFIG_CRYPTO_ZSTD=y` + `CONFIG_ZRAM_MULTI_COMP=y` | ✅ Enabled |
| PStore/RAMoops | `CONFIG_PSTORE_RAM=y` @ `0x4d010000` | ✅ Enabled |

### 4.3 Epitaph Schedutil Performance Profiles

Managed runtime options via `/data/adb/epitaph/mode`:

| Profile | up_rate | down_rate | GPU Tuning | Swappiness | Uclamp.min | Ideal Use Case |
|---|---|---|---|---|---|---|
| `performance` | 100µs | 40ms | always_on + GED boost | 200 | 180 (aggressive) | High-end Gaming |
| `balanced` | 500µs | 10ms | dynamic + GED boost | 180 | 64 (smooth UI) | Daily Driver (Default) |
| `battery` | 2ms | 1ms | coarse_demand | 160 | 0 (battery save) | Standby / Long battery life |

Apply profiles at runtime without reboots:
```sh
echo "performance" > /data/adb/epitaph/mode && sh /data/adb/epitaph/apply
```

### 4.4 WiFi & Network Fixes

| Feature | Status | Notes |
|---|---|---|
| cfg80211 + mac80211 | ✅ Modular (`=m`) | Must remain modular; registered inside BUILD.bazel |
| Netfilter NAT IPv4 | ✅ Enabled | `CONFIG_NF_NAT=y`, `CONFIG_IP_NF_TARGET_MASQUERADE=y` |
| Netfilter NAT IPv6 | ✅ Enabled | `CONFIG_IP6_NF_NAT=y`, `CONFIG_IP6_NF_TARGET_MASQUERADE=y` |
| WiFi fallback loader | ✅ Enabled | Loaded via `epitaph_tuner.sh` if systemless loader fails |

---

## 5. Known Issues & Troubleshooting

### 5.1 SUSFS Build Failures (v1–v129)

**Status:** Resolved and implemented.

**Root causes:**
1. **Incorrect KSU source** — standard KernelSU dev branch lacked SUSFS hooks. Fixed by switching to `pershoot/KernelSU-Next` branch `next-susfs`.
2. **Bazel sandboxing limits** — Bazel built from HEAD, ignoring unstaged SUSFS patches. Fixed by executing `git commit` directly after staging files.
3. **Falsified `SUSFS_INTEGRATED` flag** — flag was set via self-written configuration checks rather than actual patch success. Fixed by verifying files directly (e.g., `fs/susfs.c`).

### 5.2 Flash-induced Bootloops

**Primary Causes:**
1. Unsupported LCD panels (LC0C/LC0D) lacking kernel-side display drivers.
2. Disabling debugging symbols (`CONFIG_DEBUG_INFO_NONE=y`), which crashes the BPF subsystem on Android 15.
3. Activating MediaTek combo WiFi config (`CONFIG_MTK_COMBO_WIFI=y`), leading to system crashes.
4. Using raw `Image` formatting (MediaTek bootloaders require compressed `Image.gz`).

**Emergency Recovery Procedure:**
```bash
# Step 1: Flash official stock boot image via PC CMD
fastboot flash boot boot_stock.img && fastboot reboot

# Step 2: Extract crash log
adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt
```

*Note: Never flash multiple boots sequentially in Fastboot as it wipes out the volatile RAMoops cache.*

---

## 6. Technical Constraints — NON-NEGOTIABLE

Absolute constraints that must never be broken by any developer (human or AI).

### 6.1 Defconfig Configuration

| Config Parameter | Constraint | Rationale |
|---|---|---|
| `CONFIG_DEBUG_INFO_NONE` | ❌ MUST BE `=n` | Prevents BPF/BTF symbol losses which breaks WiFi on Android 15 |
| `CONFIG_MTK_COMBO_WIFI` | ❌ MUST BE `=n` | Prevents hardware combo clashes resulting in instant bootloops |
| `CONFIG_MTK_COMBO_BT` | ❌ MUST BE `=n` | Same as above |
| `CONFIG_ZSMALLOC` | ✅ MUST BE `=m` | Bazel expects it as a compiled module |
| `CONFIG_ZRAM` | ✅ MUST BE `=m` | Bazel expects it as a compiled module |
| `CONFIG_CFG80211` | ✅ MUST BE `=m` | Kept modular for systemless integration |
| `CONFIG_MAC80211` | ✅ MUST BE `=m` | Kept modular for systemless integration |
| `CONFIG_KPROBES` | ✅ MUST BE `=y` | Prerequisite for KernelSU-Next hooks |
| `CONFIG_HAVE_KPROBES` | ✅ MUST BE `=y` | Prerequisite for KernelSU-Next hooks |
| `CONFIG_KPROBE_EVENTS` | ✅ MUST BE `=y` | Prerequisite for KernelSU-Next hooks |
| `CONFIG_ARM64_4K_PAGES` | ✅ MUST BE `=y` | Mandatory as vendor drivers are compiled with 4K alignment |
| `CONFIG_MODVERSIONS` | ✅ MUST BE `=y` | Ensures Xiaomi proprietary modules load successfully |

### 6.2 Compilation Pipelines
- Always use `--lto=none` in Bazel to prevent Out-Of-Memory errors on restricted runners.
- Set `--local_resources=memory=6144` (never use deprecated `--local_ram_resources`).
- Limit parallel compilation steps to `--jobs=2`.
- Target the top of `common-android15-6.6` branch rather than pinning older commits.
- Commit all staged patch files to Git prior to running Bazel.

---

*This document is dynamically updated as new technical decisions are made.*
*Last updated: May 2026 — v129*