# 🚀 Flashing & Emergency Recovery Guide (Redmi 12 - fire)
> [!IMPORTANT]
> **PLEASE READ THIS GUIDE CAREFULLY TO ENSURE A STABLE WIFI MODULE AND PREVENT PANIC DURING A BOOTLOOP.**

Redmi 12 (*fire*) GKI 6.6 builds running Android 15 HyperOS 2.0 feature a modular architecture separating the **kernel core (`boot.img`)** from the **WiFi/Bluetooth driver modules (`/vendor_dlkm`)**. This document explains the secure flashing procedures and how to restore a broken WiFi/Hotspot connection caused by flashing mismatches.

---

## 📂 1. Pre-Flashing Preparation
Before installing the custom Epitaph kernel, prepare the following on your PC or phone:
1. **Official Stock Boot Image (`boot.img`)**: Extract this from the official Fastboot ROM corresponding to the HyperOS 2.0 version currently running on your device.
2. **Kernel Flashing App**: Install **Kernel Flasher** or Franco Kernel Manager (FKM) and grant them Root access (KernelSU / Magisk).
3. **AnyKernel3 ZIP Package**: The compiled zip file produced by the GitHub Actions workflow (e.g., `Epitaph-Kernel-v124-bazel-default.zip`).

---

## ⚡ 2. Normal Flashing Procedure (Main Kernel)
To install the main Epitaph kernel:
1. Download the compiled **AnyKernel3 ZIP** package to your phone's internal storage.
2. Open the **Kernel Flasher** (or FKM) app.
3. Select the flashing menu, and navigate to the Epitaph ZIP package.
4. Begin the flash process. AnyKernel3 will automatically:
   * Replace the kernel image (`Image` or `Image.gz`) in the `/boot` partition.
   * Copy the matching WiFi module drivers (`cfg80211.ko` and `mac80211.ko`) to the `/vendor_dlkm` partition.
5. **Reboot** your device.

---

## 🚨 3. Troubleshooting Bootloops & Restoring Dead WiFi (CRITICAL)

### Why does WiFi & Hotspot break after flashing the Rescue boot.img via Fastboot?
If you flash a broken main kernel that results in a bootloop, AnyKernel3 has already copied the main kernel's WiFi module drivers to `/vendor_dlkm`.

If you immediately try to recover by running:
`fastboot flash boot Epitaph-Rescue-boot.img`
You are only updating the **kernel core**, while the **old mismatched/incompatible WiFi modules are left behind in `/vendor_dlkm`**. Due to the version and symbol mismatch, the rescue kernel will refuse to load them, leading to a completely dead WiFi/Hotspot.

---

### 100% Successful Recovery & WiFi Restoration Procedure:

If your device bootloops, follow these recovery steps in order:

#### Step A: Restore Stock Boot via Fastboot
1. Reboot the device into **Fastboot** mode (press and hold `Power + Volume Down`).
2. Run the following command from your PC terminal to restore the official stock kernel:
   ```bash
   fastboot flash boot boot_stock.img
   fastboot reboot
   ```
3. Your phone will successfully boot into the stock HyperOS ROM with WiFi/Hotspot fully functional again.

#### Step B: Clean Leftover Custom Modules (Optional)
If your stock ROM WiFi is still not working after restoring the stock boot, it is because `/vendor_dlkm` still holds the custom Epitaph modules. To clean them:
1. Open the **Kernel Flasher** app on your stock ROM.
2. Flash the official **Stock Boot Image (`boot.img`)** directly from within the Kernel Flasher app.
3. The app will automatically restore the original stock Xiaomi vendor modules back to `/vendor_dlkm` and wipe any leftover custom modules.

#### Step C: Flash the New Stable Build
1. Once your WiFi is confirmed working on the stock ROM, download the corrected/newer **Epitaph ZIP** build.
2. Open the **Kernel Flasher** app.
3. Flash the new Epitaph ZIP package.
4. Reboot, and enjoy a stable kernel with 100% working WiFi & Hotspot!
