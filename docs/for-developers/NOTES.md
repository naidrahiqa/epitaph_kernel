# Catatan Stabilisasi Kernel (Redmi 12 - fire)

> [!NOTE]
> Dokumen ini memuat catatan riwayat perkembangan, aturan emas stabilitas, serta langkah diagnosis pengembangan kernel Epitaph untuk perangkat Redmi 12 (fire) berbasis Generic Kernel Image (GKI) 6.6.

---

## 🚀 Riwayat & Status Pengembangan (Mei 2026)

| Versi Build | Toolchain | Status | Deskripsi & Temuan Masalah |
| :--- | :--- | :--- | :--- |
| **v70** | Bazel (Kleaf) | **BOOTING** ✅ | Berhasil masuk ke sistem Android 15. Ditemukan kendala pada matinya fungsi WiFi/Hotspot, adanya lag pada subsistem GPU (kesalahan limiter), serta konsumsi memori RAM yang tinggi (~3.9GB). |
| **v71** | ZyClang | **BOOTLOOP** ❌ | Perangkat gagal melewati fase inisialisasi bootloader. Diduga kuat akibat ketidakcocokan compiler ZyClang pada fase ini atau akibat dinonaktifkannya informasi debug (`CONFIG_DEBUG_INFO_NONE=y`) yang merusak subsistem jaringan Android 15. |
| **v72** | Bazel (Kleaf) | **BOOTING** ✅ | Mengatasi kegagalan build/injeksi KSU dengan migrasi parser ke file skrip Python mandiri (`workflow_scripts/`). UI Alur Kerja (GKI Control Center) sepenuhnya direvolusi dari checkbox rumit menjadi menu dropdown (`choice`) premium dan rapi. |
| **v73** | Bazel (Kleaf) | **STABIL** 👑 | Menerapkan optimasi keandalan tingkat tinggi: ZRAM ZSTD multi-comp & KSM (untuk menghemat memori), Netfilter NAT lengkap (untuk hotspot IPv4 & IPv6 stabil), dan penyuntikan premium *Epitaph Tuner* post-boot (untuk atasi lag GPU limiter, scheduler CPU, swappiness RAM, dan read-ahead storage). |

---

## ⚠️ Aturan Emas Stabilitas (JANGAN DILANGGAR)

1. **Ukuran Halaman Memori (Page Size)**
   * **Aturan**: Harus disetel ke **4K (`CONFIG_ARM64_4K_PAGES=y`)**.
   * **Rasionalisasi**: Pemuatan modul vendor bawaan Xiaomi Redmi 12 dikompilasi khusus menggunakan ukuran halaman 4K. Memilih ukuran halaman 16K atau 64K dipastikan akan memicu kegagalan pemuatan modul sistem dan berujung pada bootloop instan.

2. **Identitas Kernel (Local Version)**
   * **Aturan**: Gunakan stempel nama `-Epitaph` (`CONFIG_LOCALVERSION="-Epitaph"`).
   * **Rasionalisasi**: Mempermudah identifikasi serta pelacakan versi kernel aktif melalui menu "Tentang Ponsel" pada perangkat Android.

3. **Simbol Debug & Keamanan Android 15**
   * **Aturan**: Jangan sekali-kali mengaktifkan opsi `CONFIG_DEBUG_INFO_NONE=y`.
   * **Rasionalisasi**: Android 15 membutuhkan metadata BTF (BPF Type Format) yang berada di dalam informasi debugging kernel untuk menjalankan fungsi kontrol data jaringan BPF. Tanpa informasi ini, seluruh modul komunikasi radio perangkat (WiFi, Data Seluler, dan Hotspot) akan mati total.

4. **Sistem Kompilasi (Toolchain)**
   * **Aturan**: Gunakan **Bazel/Kleaf bawaan AOSP** sebagai compiler utama produksi.
   * **Rasionalisasi**: Arsitektur GKI 6.6 dirancang secara penuh untuk berjalan di atas ekosistem Kleaf Bazel. Penggunaan compiler eksternal kustom (seperti ZyClang, WeebX, Neutron) hanya diperbolehkan untuk eksperimen minor setelah basis kompilasi Bazel berjalan sempurna.

---

## 🛠️ Perbaikan Aktif (Build v72+)
* **Pendaftaran Modul WiFi Bazel (cfg80211/mac80211)**: Bermigrasi sepenuhnya ke skrip Python mandiri [patch_build_system.py](file:///d:/Project%20Coding/2026/4%20April/kernel%20redmi%2012/workflow_scripts/patch_build_system.py) untuk mendaftarkan modul WiFi kustom ke `module_outs` di `BUILD.bazel` dan `modules.bzl` secara dinamis dan aman.
* **Perbaikan Versi KernelSU-Next (Kbuild Fallback & IndentationError)**: Menyelesaikan bug `IndentationError: unexpected indent` pada workflow runner secara tuntas dengan memindahkan skrip injeksi versi KSU ke berkas Python mandiri [patch_kbuild.py](file:///d:/Project%20Coding/2026/4%20April/kernel%20redmi%2012/workflow_scripts/patch_kbuild.py).
* **Otomasi Patching SUSFS pada KernelSU-Next**: Menyelesaikan masalah kegagalan build/compile varian SUSFS secara permanen dengan menerapkan otomatisasi penyuntikan `10_enable_susfs_for_ksu.patch` langsung ke sub-direktori `drivers/kernelsu/` beserta pelacakan Git yang presisi agar terdeteksi sempurna oleh Bazel Kleaf sandbox.
* **Revolusi UI Alur Kerja GKI Control Center**: Mengubah alur input alur kerja manual dari tumpukan checkbox (checkboxes) yang tidak sedap dipandang menjadi pilihan dropdown menu (`choice`) yang sangat rapi, premium, dan intuitif untuk varian SUSFS dan opsi Toolchain.
* **Penguncian Nama Kernel & Author**: Menghapus opsi input dinamis pada menu pembuat alur kerja (`build_manager_gki.yml`) dan menguncinya secara mutlak ke `"Epitaph"` dan `"Naidrahiqa"` untuk menghindari modifikasi identitas kernel oleh pengguna luar.
* **Subsistem Hotspot**: Penambahan konfigurasi Netfilter NAT (`CONFIG_NF_NAT`, `CONFIG_IP_NF_NAT`, dan `CONFIG_NETFILTER_XT_TARGET_MASQUERADE`).
* **Branding Identitas**: Penulisan stempel versi lokal secara terpusat pada defconfig.
* **Kebersihan Alur Kerja**: Penghapusan dukungan server kompilasi Azure yang tidak terpakai dari berkas workflow guna mereduksi waktu eksekusi CI/CD.

---

## 🔍 Panduan Praktis Diagnosis & Debugging
Apabila perangkat mengalami masalah ketidakstabilan atau gagal masuk ke sistem (bootloop), ikuti instruksi pengumpulan log berikut:

### 1. Penarikan Log Melalui Recovery (PStore/RAMoops)
Jika HP bootloop dan masuk ke Recovery, gunakan perintah berikut melalui terminal PC Anda:
```bash
adb pull /sys/fs/pstore/console-ramoops-0 ./last_kmsg.log
```
*Berkas `last_kmsg.log` berisi rekaman log konsol tepat sesaat sebelum sistem mengalami crash/panic.*

### 2. Diagnosis Menggunakan Log Live (ADB Dmesg)
Jika HP berhasil booting namun ada komponen yang tidak berjalan, tarik log aktif lewat ADB:
* **Analisis Bug GPU**: `adb shell "su -c dmesg" | grep -i "limiter"`
* **Analisis Jaringan WiFi**: `adb shell "su -c dmesg" | grep -i "WIFI"`
* **Analisis Modul KernelSU**: `adb shell "su -c dmesg" | grep -i "KSU"`

---
*Terakhir Diperbarui: 2026-05-17 19:38 (WIB)*