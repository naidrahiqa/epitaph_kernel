# 🚀 Panduan Flashing & Pemulihan Sistem (Redmi 12 - fire)
> [!IMPORTANT]
> **BACA PANDUAN INI UNTUK MENJAGA MODUL WIFI KONDUSIF DAN MENCEGAH KEPANIKAN SAAT TERJADI BOOTLOOP.**

Redmi 12 (*fire*) berbasis GKI 6.6 Android 15 HyperOS 2.0 memiliki arsitektur modular yang memisahkan **inti kernel (`boot.img`)** dengan **modul driver WiFi/Bluetooth (`/vendor_dlkm`)**. Dokumen ini menjelaskan prosedur flashing aman serta cara memulihkan jaringan WiFi/Hotspot yang mati akibat salah flashing.

---

## 📂 1. Persiapan Sebelum Flashing
Sebelum melakukan flashing kernel kustom (Epitaph), pastikan Anda telah menyiapkan berkas-berkas berikut di PC/Ponsel:
1. **Biner Stock Boot Image (`boot.img`)**: Ekstrak dari Fastboot ROM HyperOS 2.0 resmi yang saat ini sedang aktif di perangkat Anda.
2. **Aplikasi Kernel Flasher**: Pasang aplikasi **Kernel Flasher** atau Franco Kernel Manager (FKM) yang telah diberikan akses Root (KernelSU / Magisk).
3. **Paket AnyKernel3 ZIP**: Berkas zip hasil kompilasi workflow Actions (misalnya `Epitaph-Kernel-v124-bazel-default.zip`).

---

## ⚡ 2. Prosedur Flashing Normal (Main Kernel)
Untuk memasang kernel utama Epitaph:
1. Unduh paket **AnyKernel3 ZIP** hasil build ke memori internal ponsel.
2. Buka aplikasi **Kernel Flasher** (atau FKM).
3. Pilih menu flashing, lalu arahkan ke berkas ZIP kernel Epitaph tersebut.
4. Lakukan proses flash. AnyKernel3 akan secara otomatis:
   * Mengganti citra kernel (`Image` / `Image.gz`) di partisi `/boot`.
   * Menyalin berkas driver modul WiFi (`cfg80211.ko` dan `mac80211.ko`) yang cocok ke partisi `/vendor_dlkm`.
5. Lakukan **Reboot** sistem.

---

## 🚨 3. Mengatasi Bootloop & Memulihkan WiFi yang Mati (CRITICAL)

### Kenapa WiFi & Hotspot Mati Pasca Flash Rescue via Fastboot?
Ketika Anda mem-flash kernel utama yang rusak lalu bootloop, AnyKernel3 sudah terlanjur menyalin modul WiFi main kernel ke `/vendor_dlkm`.

Jika Anda memulihkannya secara terburu-buru dengan melakukan:
`fastboot flash boot Epitaph-Rescue-boot.img`
Anda hanya memperbarui **inti kernel**, tetapi **modul WiFi lama yang rusak/mismatch masih tertinggal di `/vendor_dlkm`**. Karena versinya tidak cocok (*symbol mismatch*), kernel penyelamat menolak memuat WiFi, sehingga WiFi/Hotspot Anda mati total (*matot*).

---

### Prosedur Pemulihan WiFi & Sistem 100% Sukses:

Apabila perangkat Anda mengalami bootloop, ikuti langkah penyelamatan di bawah ini secara berurutan:

#### Langkah A: Kembalikan ke Stock Boot via Fastboot
1. Masuk ke mode **Fastboot** (tekan tombol `Power + Volume Down`).
2. Jalankan perintah berikut dari CMD PC Anda untuk mengembalikan kernel bawaan resmi:
   ```bash
   fastboot flash boot boot_stock.img
   fastboot reboot
   ```
3. Ponsel Anda akan sukses booting masuk ke dalam sistem Android HyperOS bawaan dengan WiFi/Hotspot yang menyala normal kembali.

#### Langkah B: Bersihkan Sisa Modul Kustom (Opsional)
Jika setelah kembali ke Stock Boot WiFi Anda masih terganggu, itu karena partisi `/vendor_dlkm` masih menyimpan modul Epitaph lama. Cara membersihkannya:
1. Buka aplikasi **Kernel Flasher** di Android bawaan Anda.
2. Flash ulang file **Stock Boot Image (`boot.img`)** langsung dari dalam aplikasi Kernel Flasher tersebut.
3. Aplikasi Kernel Flasher akan secara otomatis memulihkan berkas modul asli bawaan Xiaomi ke `/vendor_dlkm` dan menghapus modul kustom yang tersisa.

#### Langkah C: Flash Ulang Build Baru yang Stabil
1. Setelah WiFi dipastikan normal kembali di stock ROM, unduh paket **Epitaph ZIP** versi baru (misalnya v124 yang konfigurasinya sudah diperbaiki).
2. Buka aplikasi **Kernel Flasher** kembali.
3. Flash file ZIP Epitaph yang baru.
4. Reboot, dan nikmati kernel baru dengan WiFi & Hotspot yang berfungsi 100% normal!
