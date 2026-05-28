# Kernel Stabilization Notes (Redmi 12 - fire)

> [!NOTE]
> This document details development logs, gold standards of stability, and diagnostic procedures for the Epitaph kernel tailored for the Redmi 12 (fire) utilizing the GKI 6.6 base.

---

## 🚀 Development History & Status (May 2026)

| Build Version | Toolchain | Status | Description & Issues Identified |
| :--- | :--- | :--- | :--- |
| **v70** | Bazel (Kleaf) | **BOOTING** ✅ | Successfully boots into Android 15. Known issues include broken WiFi/Hotspot functionality, GPU driver lags (limiter issues), and elevated RAM consumption (~3.9GB). |
| **v71** | ZyClang | **BOOTLOOP** ❌ | Fails to initialize bootloader. Diagnosed as either a compiler mismatch in the boot stage or due to the disabling of debug info (`CONFIG_DEBUG_INFO_NONE=y`), which breaks Android 15 networking. |
| **v72** | Bazel (Kleaf) | **BOOTING** ✅ | Resolved KSU injection/build failures by migrating parsers to dedicated Python scripts (`workflow_scripts/`). Refactored the GKI Control Center workflow interface from tedious checkboxes into elegant, clean dropdowns. |
| **v73** | Bazel (Kleaf) | **STABLE** 👑 | High-level reliability tuning: implemented ZRAM ZSTD multi-comp & KSM (for RAM optimization), full Netfilter NAT (for stable hotspot connectivity on IPv4 & IPv6), and the premium *Epitaph Tuner* post-boot (resolving GPU limiters, CPU scheduler latency, swappiness, and read-ahead). |

---

## ⚠️ Gold Standards of Stability (DO NOT VIOLATE)

1. **Memory Page Size**
   * **Rule**: Must be set to **4K (`CONFIG_ARM64_4K_PAGES=y`)**.
   * **Rationale**: The vendor driver modules loaded by Xiaomi on the Redmi 12 are pre-compiled for 4K page sizes. Compiling with 16K or 64K page sizes will result in system driver symbol mismatches and trigger instant bootloops.

2. **Kernel Identity (Local Version)**
   * **Rule**: Pinned to `-Epitaph` (`CONFIG_LOCALVERSION="-Epitaph"`).
   * **Rationale**: Simplifies validation and tracking of the running kernel build directly from the Android "About Phone" settings interface.

3. **Android 15 Security & Debug Symbols**
   * **Rule**: NEVER enable `CONFIG_DEBUG_INFO_NONE=y`.
   * **Rationale**: Android 15 networking requires BTF (BPF Type Format) metadata enclosed within kernel debugging structures to control network packets. Disabling debugging symbols completely breaks all wireless systems (WiFi, Mobile Data, Hotspot).

4. **Kleaf Build System (Toolchain)**
   * **Rule**: Utilize **AOSP Bazel/Kleaf** as the production release compiler.
   * **Rationale**: The GKI 6.6 architecture is fully designed to compile using the Kleaf environment. Custom toolchains (ZyClang, WeebX, Neutron) are experimental and should only be tested once Bazel compiles successfully.

---

## 🛠️ Active Fixes (Build v72+)
* **WiFi Module Registration (cfg80211/mac80211)**: Migrated to a modular Python patcher [patch_build_system.py](file:///d:/Project%20Coding/2026/4%20April/kernel%20redmi%2012/workflow_scripts/patch_build_system.py) to dynamically register custom WiFi modules in `module_outs` inside `BUILD.bazel` and `modules.bzl`.
* **KernelSU-Next Version Fixes**: Solved workflow runner `IndentationError` by delegating KSU version injection to a dedicated Python script [patch_kbuild.py](file:///d:/Project%20Coding/2026/4%20April/kernel%20redmi%2012/workflow_scripts/patch_kbuild.py).
* **SUSFS Integration Automation**: Resolved compiler issues for SUSFS variants by automating the application of `10_enable_susfs_for_ksu.patch` directly under `drivers/kernelsu/` along with precise git tracking to satisfy the Bazel Kleaf sandbox.
* **GKI Control Center UI Redesign**: Transformed workflow runner inputs from basic checkboxes to clean, premium dropdown selections (`choice`) for SUSFS and Clang toolchain matrices.
* **Branding Lock**: Pinned naming options under `build_manager_gki.yml` permanently to `"Epitaph"` and `"Naidrahiqa"` to prevent identity spoofing.
* **Hotspot Networking Subsystem**: Incorporated Netfilter NAT configs (`CONFIG_NF_NAT`, `CONFIG_IP_NF_NAT`, and `CONFIG_NETFILTER_XT_TARGET_MASQUERADE`).
* **Workflow Cleanups**: Deprecated obsolete Azure compilation configurations to reduce runner CI/CD runtimes.

---

## 🔍 Diagnostic & Debugging Quick Guide
In the event of system instability or bootloops, follow these log extraction instructions:

### 1. Extract Crash Logs (PStore/RAMoops)
If the device bootloops and triggers a rescue, pull the panic buffers via PC:
```bash
adb pull /sys/fs/pstore/console-ramoops-0 ./last_kmsg.log
```
*The `last_kmsg.log` contains detailed crash logs captured at the exact moment of the Kernel Panic.*

### 2. Live Debug Diagnostics (ADB Dmesg)
If the device successfully boots but some components are malfunctioning, pull active live logs:
* **GPU Limiter logs**: `adb shell "su -c dmesg" | grep -i "limiter"`
* **WiFi Subsystem logs**: `adb shell "su -c dmesg" | grep -i "WIFI"`
* **KernelSU-Next logs**: `adb shell "su -c dmesg" | grep -i "KSU"`

---
*Last Updated: 2026-05-17 19:38 (WIB)*