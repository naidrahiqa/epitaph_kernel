# PRD — Epitaph Kernel (v2.0)
**Product Requirements Document**
> This document is the **source of truth** for all technical decisions in the Epitaph Kernel project.
> Anyone (human or AI) who wants to touch this repository **must read this document first**.
> If there is a conflict between this document and other instructions, this document wins.

---

## 1. Product Overview (Phase 2: Optimization & Diagnostics)

**Epitaph Kernel** is a highly optimized custom GKI 6.6 kernel designed for the **Xiaomi Redmi 12 (codename: fire)** running **Android 15 HyperOS 2.0**. 

Having fully completed its Phase 1 core milestones (delivering stable kernel-level root, robust WiFi/hotspot bypasses, custom schedutil governors, and dynamic CI pipelines), the project has transitioned into **Phase 2: Advanced Platform Optimization, Budget Storage Acceleration, and Automated Recovery Diagnostics**.

Built from Google's `common-android15-6.6` branch, the kernel is compiled via GitHub Actions and shipped as a premium AnyKernel3 ZIP package flashed via **KernelFlasher** (as no custom recovery exists for this device).

### Who are the users?
- **Developer (maintainer):** Faqih Ardian Syah (@naidrahiqa) — the sole maintainer.
- **AI pair programmers:** Antigravity, Claude, Gemini, DeepSeek, Qwen — who must read this PRD to ensure absolute compatibility.
- **End users:** Redmi 12 owners seeking custom root capabilities, gaming enhancements, and extreme battery life.

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

## 3. System Architecture & CI/CD Pipeline

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
               │     │     ├── setup_ksu (pershoot/KernelSU-Next branch dev-susfs)
               │     │     ├── apply_patches
               │     │     └── patch_build_system
               │     ├── Setup SUSFS (if with_susfs=true)
               │     ├── Configure Kernel (defconfig manipulation)
               │     ├── Build (Bazel OR Custom Clang)
               │     ├── Extract Build Output
               │     ├── Verify Build Correctness
               │     ├── Package AnyKernel3
               │     │     └── Inject scripts/epitaph_tuner.sh persistently
               │     ├── Upload Artifacts
               │     ├── Create GitHub Release
               │     │     └── Generate dynamic Git-based Release Changelog
               │     └── Telegram notify (dynamic release status + rescue reference)
               └── summary: final overall build status report
```

### Toolchain Matrix

| Toolchain | Build System | Status | Notes |
|---|---|---|---|
| `bazel-default` | Bazel/Kleaf | ✅ **Production** | The only officially production-tested system |
| `aosp-latest` | make | ⚠️ Experimental | crdroidandroid prebuilt Clang |
| `zyc-latest` | make | ⚠️ Experimental | ZyClang toolchain |
| `weebx-latest` | make | ⚠️ Experimental | WeebX Clang toolchain |
| `neutron-latest` | make | ⚠️ Experimental | Neutron Clang toolchain |

---

## 4. Current Features & Status (Completed Core Baseline)

### 🔐 Root & Security (100% Stable)
* **KernelSU-Next Built-in**: Direct kernel-level root access natively loaded without system partition modifications.
* **SUSFS for KSU**: Successfully integrated pre-patched driver layers (`dev-susfs`) to fully pass banking safety evaluations.
* **Vermagic Bypass**: Custom dynamically patched module loaders (`same_magic()` returning `1`) to safely bypass signature mismatches, allowing stock Xiaomi WiFi modules to load natively.

### 🚀 Performance & Memory (100% Stable)
* **Epitaph Schedutil Governor**: Minimum rate limit unlocked to 100µs to eliminate micro-stutters during heavy system operations.
* **GPU GED Boost**: MediaTek thermal throttle overrides active to stabilize framerates.
* **ZRAM ZSTD Multi-Stream**: Compressed background paging with 25% better RAM savings than LZ4.
* **BBR & FQ Network**: TCP BBR Congestion Control active for gaming latency optimization.
* **Epitaph Tuner post-boot (`epitaph_tuner.sh`)**: Dynamically switches performance/balanced/battery profiles via `/data/adb/epitaph/mode`.

### 📶 Connectivity & Native Fixes (100% Stable)
* **Systemless WiFi Loader**: Bundles framework network modules (`cfg80211`, `mac80211`) and performs automatic boot-time insertion (`insmod`) to guarantee stable Hotspot/WiFi.
* **IPv4/IPv6 Hotspot NAT**: Masquerading active for unrestricted tethering.

---

## 5. The Next Frontier: New Roadmap & Milestones (Phase 2)

```mermaid
graph TD
    A[Phase 2 Roadmap] --> B(Sprint 5: Rescue Desktop integration)
    A --> C(Sprint 6: Helio G88 EAS Optimizations)
    A --> D(Sprint 7: eMMC 5.1 Storage Tweaks)
    A --> E(Sprint 8: LCM Panel Drivers RE)
    A --> F(Sprint 9: Compiler ThinLTO Matrix)
```

### 🛠️ Sprint 5 — Epitaph Rescue Desktop GUI Integration
* [x] Integrate the desktop Go/Fyne-based **Epitaph Rescue Tool** with the build repository.
* [x] Automate dynamic recovery flashing for bootlooping devices.
* [x] Build a **visual PStore log parser** in the Rescue Tool that directly analyzes `console-ramoops-0` and outputs human-readable debugging guidance.

### ⚡ Sprint 6 — Helio G88 Heterogeneous CPU/GPU EAS Optimizations
* [x] Optimize Energy Aware Scheduling (EAS) task placement on the Helio G88 core layout (2× Cortex-A75 big cores + 6× Cortex-A55 LITTLE cores).
* [x] Lock lightweight background processes exclusively to Cortex-A55 LITTLE cores to achieve extreme battery lifespan.
* [x] Map real-world energy profiles in place of generic GKI common templates to prevent power waste.

### 💾 Sprint 7 — eMMC 5.1 Storage & I/O Latency Tweaks
* [x] Mitigate micro-stutters during disk-heavy tasks (e.g. background installations) on slower budget storage (eMMC 5.1).
* [x] Calibrate virtual memory (VM) page settings (`dirty_ratio`, `dirty_background_ratio`, and `dirty_writeback_centisecs`) specifically for budget hardware.
* [x] Implement smart dynamic I/O scheduler switching: switch to low-latency rules automatically when foreground gaming is active.

### 📱 Sprint 8 — Reverse-Engineering Display Panel Drivers (LCM Variant Expansion)
* [~] **N/A (Obsolete on GKI 6.6)**: GKI-compliant Android 15 HyperOS 2.0 uses modular loading. Display drivers (`LCM LC0C/LC0D`) are managed dynamically via Xiaomi vendor modules (`/vendor_dlkm/lib/modules/`) and DTBO overlays, eliminating the need for monolithic static kernel porting that was mandatory on legacy 4.19 kernels.

### 🧪 Sprint 9 — Compiler Flags & Kleaf Optimization Matrix
* [ ] Transition from `--lto=none` to safe **ThinLTO** to reduce kernel binary footprints and speed up execution.
* [ ] Fine-tune Clang optimization flags specifically targeting the Cortex-A75/A55 architectures.

---

## 6. Non-Negotiable Technical Constraints

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
- Commit all staged patch files to Git prior to running Bazel (Bazel sandbox reads HEAD only).
- Keep Bazel and custom Clang make-based compilations 100% isolated.
- Do not remove `patch_vermagic.py` — bypasses vermagic for stock Xiaomi modules.

### 6.3 AnyKernel3 Rules
- `supported.versions=15` only — GKI 6.6 is incompatible with Android 14.
- Image priority: `Image.gz` → `Image.lz4` → `Image` — MTK bootloader often rejects raw `Image`.
- `cfg80211.ko` and `mac80211.ko` must be packaged in the ZIP.

### 6.4 Recovery Rules
- No custom recovery (TWRP/OrangeFox) exists — never suggest it.
- Pull logs via PStore: `adb shell "su -c cat /sys/fs/pstore/console-ramoops-0"`.
- Rescue kernel (`build_debug_bootimg.yml`) — always boots, PStore enabled.
- Never flash multiple boot images sequentially via Fastboot — wipes RAMoops.

---

## 7. Diagnosis & Debugging Guide

### 7.1 Decision Tree Bootloop

```
Phone bootloops after flashing Epitaph
│
├── Reboots immediately to Fastboot?
│   └── Flash stock boot → boot Android → pull last_kmsg.txt
│       └── Search for: "Kernel panic", "Call Trace", "init: Service killed"
│
├── Stuck on logo (infinite loop)?
│   └── Likely cause: display panel driver (LC0C/LC0D) or KSU init crash.
│
└── Boots but reboots immediately?
    └── Likely cause: incomplete SUSFS patching or BPF crash.
```

### 7.2 How to Pull Crash Logs
```bash
# From PC (NOT from within adb shell):
adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt

# If the file does not exist, try:
adb shell "su -c cat /sys/fs/pstore/dmesg-ramoops-0" > last_kmsg.txt
```

---

## 8. Changelog of Technical Decisions

| Date | Technical Decision | Rationale |
|---|---|---|
| v70 | Use schedutil instead of performance/powersave | Most stable for daily drivers, fully EAS-aware |
| v71 | Remove CONFIG_DEBUG_INFO_NONE | Fixed ZyClang v71 bootloops — debug info is required by Android 15 BPF |
| v72 | Migrate parsers to python scripts | Fixed heredoc inline indentation errors in YAML files |
| v72 | Drop Azure compiler toolchain | Incompatible with GKI 6.6 Android 15 toolchain specs |
| v73 | Integrate full Netfilter NAT support | Restores stable hotspot sharing functionality |
| v73 | Add Epitaph Tuner script | Fixes stock MediaTek GPU throttles and CPU frequency transitions |
| v129 | Identify root cause of SUSFS failures | Pinpointed incorrect KSU branch, untracked sandbox files, and false validation flags |
| v148 | Release body & Telegram notifications refactored | Replaced static notes with dynamic Git auto-changelogs and recovery tool reminders |
| v148 | KMI Environment Sanitization | Added static defaults to KMI variables in workflow setups to silence parser issues |

---

## 9. Quick Reference

### Triggering Builds
```
GitHub Actions → 🎛️ GKI Control Center → Run workflow
- release_tag: v1.x
- susfs_variant: no-susfs | susfs | both
- toolchain: bazel-default | all
```

### Output File ZIP Name
```
Epitaph-{Toolchain}-kernelsu-next[-SUSFS]-{DDMMYYYY}-AnyKernel3.zip
```

### Changing Tuner Profile at Runtime (No Reboots)
```bash
echo "performance" > /data/adb/epitaph/mode
sh /data/adb/epitaph/apply
cat /data/adb/epitaph/tuner.log  # Verify status
```

---

*This document is dynamically updated as new technical decisions are made.*
*Last updated: May 2026 — Phase 2 Launch*