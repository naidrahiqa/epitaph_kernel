<div align="center">

<!--
  EPITAPH KERNEL — README.md
  Banner: SVG inline, renders natively on GitHub
-->

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 860 200" width="860" height="200">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0a0a0f"/>
      <stop offset="50%" style="stop-color:#0d1117"/>
      <stop offset="100%" style="stop-color:#0a0a0f"/>
    </linearGradient>
    <linearGradient id="accent" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#6366f1"/>
      <stop offset="50%" style="stop-color:#8b5cf6"/>
      <stop offset="100%" style="stop-color:#06b6d4"/>
    </linearGradient>
    <linearGradient id="titlegrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#e2e8f0"/>
      <stop offset="60%" style="stop-color:#ffffff"/>
      <stop offset="100%" style="stop-color:#94a3b8"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
      <feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="softglow">
      <feGaussianBlur stdDeviation="8" result="coloredBlur"/>
      <feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <!-- Background -->
  <rect width="860" height="200" fill="url(#bg)" rx="12"/>

  <!-- Subtle grid pattern -->
  <g opacity="0.04" stroke="#6366f1" stroke-width="0.5">
    <line x1="0" y1="40" x2="860" y2="40"/>
    <line x1="0" y1="80" x2="860" y2="80"/>
    <line x1="0" y1="120" x2="860" y2="120"/>
    <line x1="0" y1="160" x2="860" y2="160"/>
    <line x1="100" y1="0" x2="100" y2="200"/>
    <line x1="200" y1="0" x2="200" y2="200"/>
    <line x1="300" y1="0" x2="300" y2="200"/>
    <line x1="400" y1="0" x2="400" y2="200"/>
    <line x1="500" y1="0" x2="500" y2="200"/>
    <line x1="600" y1="0" x2="600" y2="200"/>
    <line x1="700" y1="0" x2="700" y2="200"/>
    <line x1="800" y1="0" x2="800" y2="200"/>
  </g>

  <!-- Decorative orb left -->
  <circle cx="60" cy="100" r="80" fill="#6366f1" opacity="0.06" filter="url(#softglow)"/>
  <!-- Decorative orb right -->
  <circle cx="800" cy="100" r="90" fill="#06b6d4" opacity="0.05" filter="url(#softglow)"/>

  <!-- Top accent line -->
  <rect x="0" y="0" width="860" height="3" fill="url(#accent)" rx="2" filter="url(#glow)"/>
  <!-- Bottom accent line -->
  <rect x="0" y="197" width="860" height="3" fill="url(#accent)" rx="2" opacity="0.5"/>

  <!-- Left vertical accent -->
  <rect x="50" y="40" width="2" height="120" fill="url(#accent)" opacity="0.6" rx="1"/>

  <!-- Kernel icon / monogram -->
  <text x="72" y="115" font-family="monospace" font-size="42" fill="url(#accent)" opacity="0.9" filter="url(#glow)" font-weight="bold">∂</text>

  <!-- Main title -->
  <text x="130" y="95" font-family="Georgia, 'Times New Roman', serif" font-size="52" font-weight="bold" fill="url(#titlegrad)" letter-spacing="3" filter="url(#glow)">EPITAPH</text>
  <text x="131" y="126" font-family="'Courier New', monospace" font-size="14" fill="#64748b" letter-spacing="8">K  E  R  N  E  L</text>

  <!-- Divider -->
  <rect x="130" y="138" width="280" height="1" fill="url(#accent)" opacity="0.4"/>

  <!-- Subtitle -->
  <text x="130" y="158" font-family="'Courier New', monospace" font-size="11" fill="#475569" letter-spacing="2">GKI 6.6  ·  ANDROID 15  ·  REDMI 12 (fire)</text>

  <!-- Right side: specs -->
  <g transform="translate(560, 50)">
    <rect width="250" height="110" rx="8" fill="#ffffff" opacity="0.03" stroke="#334155" stroke-width="0.5"/>
    <text x="16" y="24" font-family="'Courier New', monospace" font-size="10" fill="#6366f1" letter-spacing="1">// SPECS</text>
    <text x="16" y="44" font-family="'Courier New', monospace" font-size="10" fill="#94a3b8">ROOT    <tspan fill="#e2e8f0">KernelSU-Next</tspan></text>
    <text x="16" y="60" font-family="'Courier New', monospace" font-size="10" fill="#94a3b8">GOV     <tspan fill="#e2e8f0">schedutil</tspan></text>
    <text x="16" y="76" font-family="'Courier New', monospace" font-size="10" fill="#94a3b8">TCP     <tspan fill="#e2e8f0">BBR + FQ</tspan></text>
    <text x="16" y="92" font-family="'Courier New', monospace" font-size="10" fill="#94a3b8">ZRAM    <tspan fill="#e2e8f0">ZSTD multi-stream</tspan></text>
  </g>
</svg>

<br/>

<!-- PROJECT STATUS BADGES -->
[![Build Status](https://img.shields.io/github/actions/workflow/status/naidrahiqa/epitaph_kernel/build_manager_gki.yml?branch=main&style=for-the-badge&logo=github-actions&logoColor=white&color=emerald)](https://github.com/naidrahiqa/epitaph_kernel/actions)
[![Latest Release](https://img.shields.io/github/v/release/naidrahiqa/epitaph_kernel?style=for-the-badge&logo=github&logoColor=white&color=3b82f6)](https://github.com/naidrahiqa/epitaph_kernel/releases)
[![License](https://img.shields.io/github/license/naidrahiqa/epitaph_kernel?style=for-the-badge&logo=git&logoColor=white&color=64748b)](LICENSE)

<br/>

<!-- SYSTEM SPECIFICATION BADGES -->
![Device](https://img.shields.io/badge/Device-Redmi%2012%20(fire)-FF6900?style=for-the-badge&logo=xiaomi&logoColor=white)
![OS](https://img.shields.io/badge/OS-Android%2015%20(HyperOS%202.0)-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![SoC](https://img.shields.io/badge/SoC-Helio%20G88%20(MT6769)-4F46E5?style=for-the-badge&logo=microchip&logoColor=white)
![Kernel](https://img.shields.io/badge/Kernel-GKI%206.6-0ea5e9?style=for-the-badge&logo=linux&logoColor=white)
![Root](https://img.shields.io/badge/Root-KernelSU--Next-7C3AED?style=for-the-badge&logo=superuser&logoColor=white)
![SUSFS](https://img.shields.io/badge/SUSFS-Supported-10B981?style=for-the-badge&logo=shield&logoColor=white)

</div>

---

## 📖 Overview

**Epitaph Kernel** is a high-performance GKI 6.6 custom kernel engineered specifically for the **Xiaomi Redmi 12 (fire)** running **Android 15 HyperOS 2.0**. Built using Google's latest `common-android15-6.6` codebase, it delivers excellent system stability, responsive gaming performance, and advanced kernel-level root integration.

---

## ✨ Core Features

### 🔐 Root & Stealth Recovery
* **Built-in KernelSU-Next**: Access kernel-level root privileges natively. Secure, lightweight, and completely stealthy.
* **SUSFS Support (Optional Build)**: Deep integration of the SUSFS kernel driver to safely hide root status from banking applications.
* **Smart Vermagic & CRC Bypass**: Dynamically bypasses `vermagic` signature checks and CRC version checking (`check_version`) in the Android module loader. This allows stock Xiaomi ROM WiFi/Bluetooth vendor drivers to load flawlessly without system crashes!

### 🚀 Performance & Memory
* **Epitaph Schedutil Governor**: Optimizes the CPU governor runtime by removing the minimum rate limit restriction down to 100µs for an ultra-smooth UI. Supports 3 instant profiles (`performance`, `balanced`, `battery`) switchable on-the-fly via `/data/adb/epitaph/mode`.
* **GPU GED Boost**: Bypasses the MediaTek thermal throttle limiters built into the stock drivers to stabilize frame rates (FPS) during intense gaming sessions.
* **ZRAM ZSTD Multi-Stream**: Fast background memory compression utilizing parallel multi-core processing, achieving 25% better memory savings than standard LZ4.
* **BBR & FQ Network**: Integrates the TCP BBR Congestion Control protocol and FQ Queueing for highly stable network latency, minimum ping, and a stutter-free online gaming experience.

### 📶 Connectivity & Native Fixes
* **Systemless WiFi Fallback Loader**: Systemlessly packages framework network modules (`cfg80211`, `mac80211`) and triggers auto-insmod for the vendor `wlan_drv_gen4m_6768.ko` driver during boot to eliminate hotspot/WiFi failures.
* **IPv4/IPv6 Hotspot NAT**: Full kernel firewall support for IP Masquerading to ensure flawless hotspot tethering without limitations.

---

## 📥 Quick Installation

1. Ensure your device is running **Android 15 (HyperOS 2.0)**.
2. Download the latest AnyKernel3 ZIP build from the [**Releases**](../../releases/latest) tab.
3. Open [**KernelFlasher**](https://github.com/capntrips/KernelFlasher/releases), choose the downloaded ZIP file, and click **Flash**.
4. Restart your device. Done!

---

## 🚨 Emergency Recovery (If Bootlooping)

If your device bootloops after flashing, do not panic. Enter Fastboot mode (`Volume Down + Power`) and run the following commands via your PC:

```bash
# 1. Restore the official stock boot image
fastboot flash boot boot_stock.img
fastboot reboot
```

After your phone successfully boots into the stock ROM, you can extract the previous crash logs using:

```bash
adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt
```

---

## 📂 Key Codebase Files

For developers who wish to contribute or debug issues, these are the primary repository files:

| File / Folder | Description |
|---|---|
| [`scripts/prepare_kernel_build.sh`](scripts/prepare_kernel_build.sh) | CI/CD script setting up dependencies, disk allocation, syncs, and KernelSU. |
| [`scripts/epitaph_tuner.sh`](scripts/epitaph_tuner.sh) | Post-boot tuning script (WiFi recovery, schedutil profile, VM swappiness). |
| [`workflow_scripts/patch_vermagic.py`](workflow_scripts/patch_vermagic.py) | Python patcher to bypass vermagic signatures and CRC modversions. |
| [`docs/`](docs/) | Comprehensive documentation directory (`for-users/`, `for-developers/`, `ROADMAP.md`, etc.). |

---

<div align="center">

*Epitaph Kernel is licensed under GPL-2.0.*

**[⬇️ Download Latest Build](../../releases/latest)** &nbsp;·&nbsp; **[🐛 Open Issue](../../issues/new)**

</div>