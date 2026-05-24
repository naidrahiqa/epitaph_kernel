# Panduan Diagnosis & Debugging Kernel Redmi 12 (fire)

> [!NOTE]
> Dokumen ini dirancang sebagai panduan taktis bagi pengembang untuk melakukan penarikan log konsol kernel serta mendiagnosis masalah seperti kegagalan booting (*bootloop*), kegagalan modul driver, atau ketidakstabilan fitur sistem pada perangkat Redmi 12 (fire) tanpa ketergantungan pada pemasangan Custom Recovery (TWRP/OrangeFox).

---

## 1. Pengambilan Log Pasca-Bootloop (PStore / RAMoops)
Generic Kernel Image (GKI) memiliki subsistem penyimpanan log khusus bernama `pstore`. Subsistem ini merekam data keluaran konsol dmesg terakhir ke dalam alokasi memori RAM terisolasi yang tidak akan terhapus saat terjadi kegagalan booting (*Kernel Panic*) atau mati mendadak, selama komponen perangkat keras tidak kehilangan tegangan daya secara total.

### Prosedur Penarikan Log:
1. **Pemicuan Kejadian**: Flash citra kernel kustom Anda. Biarkan perangkat memproses siklus booting hingga terjadi kegagalan (*Kernel Panic* atau *reboot* otomatis kembali ke Fastboot).
2. **Akses Fastboot**: Masuk ke mode Fastboot dengan menekan dan menahan kombinasi tombol `Volume Down + Power`.
3. **Kembalikan Booting Perangkat**: Flash citra kernel bawaan (*Stock Boot*) agar perangkat dapat masuk kembali ke sistem Android utama:
   ```bash
   fastboot flash boot boot_stock.img
   fastboot reboot
   ```
4. **Penarikan Berkas Log PStore**: Segera setelah ponsel masuk ke antarmuka Android utama, hubungkan kabel data PC, buka terminal, lalu jalankan rangkaian perintah berikut:
   **PENTING:** Buka terminal/CMD di PC Anda (jangan masuk ke `adb shell`!), lalu jalankan salah satu dari dua metode di bawah ini secara langsung.
   
   **Metode A: Tarik Langsung via PC (Paling Mudah)**
   Gunakan perintah ini di CMD PC untuk membaca log sebagai root dan menyimpannya ke PC Anda:
   ```cmd
   adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt
   ```
   *(Catatan: Jika file tersebut tidak ditemukan, ganti dengan `dmesg-ramoops-0`)*

   **Metode B: Salin ke Folder Netral Dulu (Paling Aman)**
   Jika Metode A gagal, gunakan 3 baris perintah ini di CMD PC:
   ```cmd
   adb shell "su -c cp /sys/fs/pstore/console-ramoops-0 /data/local/tmp/last_kmsg.txt"
   adb shell "su -c chmod 666 /data/local/tmp/last_kmsg.txt"
   adb pull /data/local/tmp/last_kmsg.txt
   ```
5. **Analisis Diagnosis**: Berkas `last_kmsg.txt` yang kini berada di komputer Anda berisi rekaman kronologis detik-detik krusial tepat sebelum kernel kustom Anda mengalami crash fatal.

---

## 2. Pengambilan Log Aktif secara Real-Time (ADB Dmesg)
Gunakan metode ini apabila perangkat **berhasil masuk ke antarmuka sistem Android utama (booting sukses)**, namun beberapa fitur penting tidak berfungsi dengan baik (seperti WiFi mati, hak akses KernelSU-Next tidak terdeteksi, atau performa melambat).

### Perintah Perekaman Log:
Jalankan perintah berikut **langsung dari terminal CMD PC Anda** (jangan masuk ke mode shell HP) untuk merekam pesan konsol dmesg secara langsung ke dalam berkas teks lokal:
```cmd
adb shell "su -c dmesg" > dmesg_live.log
```

---

## 3. Identifikasi Parameter Masalah pada Berkas Log
Buka berkas log yang berhasil Anda dapatkan (`last_kmsg.log` atau `dmesg_live.log`) menggunakan aplikasi editor teks (seperti VS Code atau Notepad++), lalu lakukan pencarian kata kunci penting berikut:

| Parameter Pencarian | Definisi Masalah | Prosedur Solusi Umum |
| :--- | :--- | :--- |
| `Kernel panic` | Kernel mendeteksi kegagalan fatal pada memori atau perangkat keras dan memutuskan menghentikan sistem. | Telusuri baris log tepat di atas pesan ini untuk melihat driver atau fungsi sistem yang memicu kegagalan pertama kali. |
| `Call Trace` | Rantai eksekusi fungsi pemrograman sebelum terjadinya crash sistem. | Analisis baris teratas fungsi yang dipanggil (biasanya memuat referensi berkas biner `.c` atau `.ko` yang bermasalah). |
| `init: Service '...' killed` | Subsistem inisialisasi Android mematikan proses akibat kegagalan pemuatan driver. | Biasanya dipicu akibat penonaktifan modul `MODVERSIONS` secara ilegal yang menyebabkan kegagalan pemuatan driver vendor Xiaomi. |
| `KSU: ...` | Pesan pelacakan inisialisasi modul KernelSU-Next. | Periksa apakah proses pemasangan kait (*hooks*) sistem berjalan sempurna atau dibatalkan oleh kebijakan keamanan kernel. |
| `uapi/... missing` | Kegagalan kompilasi akibat file antarmuka pengguna kernel yang hilang. | Pastikan seluruh berkas pustaka API telah disalin dengan benar pada direktori `common/drivers/kernelsu/uapi` sebelum proses build. |

---

## 4. Tips Diagnosis Khusus Platform Redmi 12 (MTK Helio G88)

### Kompatibilitas Format Citra Kernel
Chipset MediaTek Helio G88 pada Redmi 12 memiliki sistem kemudi bootloader yang sangat ketat. Bootloader perangkat ini umumnya akan **menolak mentah-mentah** berkas citra kernel mentah uncompressed (`Image`).
* **Kewajiban Pengemasan**: Pastikan AnyKernel3 dikonfigurasi untuk membungkus format citra terkompresi `Image.gz`.
* **Gejala Kegagalan**: Apabila memaksakan biner raw `Image` tanpa kompresi, ponsel biasanya akan langsung menolak melakukan booting dan terlempar kembali ke mode Fastboot (*Bad Image Format*).

### Pengaturan Bendera AVB (VBMeta)
Sebelum memasang kernel kustom pada sistem yang menggunakan pengaman verifikasi ketat, Anda wajib menonaktifkan pemeriksaan integritas Android Verified Boot (AVB) menggunakan perintah berikut melalui Fastboot:
```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system vbmeta_system.img
fastboot --disable-verity --disable-verification flash vbmeta_vendor vbmeta_vendor.img
```
*Gunakan berkas `vbmeta.img` resmi yang diekstraksi dari paket Fastboot ROM HyperOS 2.0 yang sedang berjalan aktif pada perangkat.*

### Sinkronisasi Versi Antarmuka KMI
Pastikan basis kode kernel yang Anda kompilasi memiliki versi KMI (Kernel Module Interface) yang sesuai dengan spesifikasi vendor. 
* Stock ROM HyperOS 2.0 untuk Redmi 12 (fire) menggunakan basis KMI versi **8**.
* Lakukan sinkronisasi stempel versi pada berkas `scripts/setlocalversion` apabila modul vendor mengalami penolakan akibat *symbol mismatch*.
