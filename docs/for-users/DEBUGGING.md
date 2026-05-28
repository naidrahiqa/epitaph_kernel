# Kernel Diagnosis & Debugging Guide (Redmi 12 - fire)

> [!NOTE]
> This document serves as a tactical guide for developers to extract kernel console logs and diagnose issues such as bootloops, driver module failures, or system instability on the Redmi 12 (fire) without relying on a Custom Recovery (TWRP/OrangeFox).

---

## 1. Extracting Crash Logs Post-Bootloop (PStore / RAMoops)
The Generic Kernel Image (GKI) features a dedicated persistent log subsystem called `pstore`. This subsystem records the latest console output (dmesg) into an isolated RAM allocation that survives kernel panics and sudden reboots, as long as the device does not lose hardware power completely.

### Log Extraction Procedure:
1. **Triggering the Issue**: Flash your custom kernel. Let the device boot until the crash occurs (either a Kernel Panic freeze or an automatic reboot back to Fastboot).
2. **Accessing Fastboot**: Enter Fastboot mode by holding down the `Volume Down + Power` buttons.
3. **Restoring Device Boot**: Flash the official stock boot image to allow the device to boot into the main Android system:
   ```bash
   fastboot flash boot boot_stock.img
   fastboot reboot
   ```
4. **Retrieving the PStore Logs**: Immediately after the phone boots into the stock Android interface, connect the USB cable to your PC, open a terminal, and pull the logs:
   **IMPORTANT:** Open the terminal/CMD on your PC directly (do not enter `adb shell`!), then run one of the two methods below:
   
   **Method A: Pull Directly via PC (Easiest)**
   Run this in your PC's CMD/terminal to read the log as root and save it to your computer:
   ```cmd
   adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt
   ```
   *(Note: If the file is not found, replace it with `dmesg-ramoops-0`)*
   ```cmd
   adb shell "su -c cat /sys/fs/pstore/dmesg-ramoops-0" > last_kmsg.txt
   ```

   **Method B: Copy to Neutral Folder First (Safest)**
   If Method A fails, run these three commands in your PC's CMD:
   ```cmd
   adb shell "su -c cp /sys/fs/pstore/console-ramoops-0 /data/local/tmp/last_kmsg.txt"
   adb shell "su -c chmod 666 /data/local/tmp/last_kmsg.txt"
   adb pull /data/local/tmp/last_kmsg.txt
   ```
5. **Diagnostic Analysis**: The `last_kmsg.txt` file now saved on your computer contains the chronological log of the final moments before your custom kernel crashed.

---

## 2. Capturing Live Logs in Real-Time (ADB Dmesg)
Use this method if the device successfully **boots into the main Android system**, but certain key features are broken (e.g., WiFi is dead, KernelSU-Next is undetected, or system performance degrades).

### Logging Command:
Run the following command **directly from your PC CMD/terminal** (do not enter shell mode on the phone) to pipe live dmesg output to a local text file:
```cmd
adb shell "su -c dmesg" > dmesg_live.log
```

---

## 3. Identifying Kernel Errors in Logs
Open the retrieved log file (`last_kmsg.txt` or `dmesg_live.log`) using a text editor (e.g., VS Code or Notepad++), and search for these critical keywords:

| Search Keyword | Problem Definition | General Resolution Step |
| :--- | :--- | :--- |
| `Kernel panic` | The kernel encountered a fatal memory or hardware error and stopped the system. | Read the lines immediately above this message to locate the driver or function that triggered the panic. |
| `Call Trace` | The stack execution history leading to the crash. | Analyze the top lines of the call stack (usually referencing `.c` files or `.ko` modules). |
| `init: Service '...' killed` | The Android initialization process killed a service because of driver loading failures. | Usually triggered by disabling `MODVERSIONS`, causing stock Xiaomi vendor drivers to fail signature checking. |
| `KSU: ...` | Trace messages related to KernelSU-Next initialization. | Verify if system hooks are successfully applied or blocked by kernel-side security policies. |
| `uapi/... missing` | Compilation failure due to missing user-API headers. | Ensure all required API files are correctly copied into `common/drivers/kernelsu/uapi` before compiling. |

---

## 4. Platform-Specific Debugging Tips (Redmi 12 - MTK Helio G88)

### Kernel Image Compression
The MediaTek Helio G88 bootloader on the Redmi 12 is highly strict. The bootloader **will immediately reject** raw, uncompressed kernel images (`Image`).
* **Packaging Requirement**: Ensure AnyKernel3 is configured to compress and bundle the kernel as `Image.gz`.
* **Failure Symptom**: Forcing an uncompressed `Image` binary will result in a bootloop that drops the phone immediately back to Fastboot (*Bad Image Format*).

### Disable Android Verified Boot (AVB)
Before flashing custom kernels on locked stock partitions, you must disable the Android Verified Boot (AVB) integrity verification. Flash the vbmeta partitions with the following disable flags via Fastboot:
```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor vbmeta_vendor.img
```
*Always use official `vbmeta.img` files extracted from the Fastboot ROM version matching your device's current firmware.*

### Kernel Module Interface (KMI) Sync
Ensure the compiled kernel base matches the vendor-specified Kernel Module Interface (KMI) generation.
* Stock HyperOS 2.0 ROMs for the Redmi 12 (fire) expect KMI version **8**.
* Synchronize version stamps in `scripts/setlocalversion` if vendor modules fail to load due to symbol mismatches.
