# Pedoman 3: Optimasi & Batasan Modifikasi (Lightweight)

> [!NOTE]
> Pedoman ini dirancang untuk menjaga efisiensi penggunaan memori RAM, memperpanjang daya tahan baterai, serta memastikan kernel kustom tidak memicu panas berlebih (lagging) pada perangkat berspesifikasi menengah seperti Redmi 12.

---

## 1. Penanganan Debugging & Batasan Android 15 (BTF Info)
* **Aturan Utama**: Jangan pernah menonaktifkan informasi debug secara total menggunakan flag `CONFIG_DEBUG_INFO_NONE=y` pada Android 15.
* **Rasionalisasi**: Sistem operasi Android 15 mengandalkan subsistem BPF (Berkeley Packet Filter) secara mendalam untuk mengatur manajemen lalu lintas jaringan (WiFi, Tethering, dan data seluler). Subsistem ini membutuhkan metadata BTF (BPF Type Format) yang dihasilkan dari simbol debugging kernel. Menonaktifkan informasi debug akan memutus pembuatan metadata BTF, yang berujung pada **matinya seluruh fungsi konektivitas jaringan** pada perangkat.
* **Implementasi yang Aman untuk Android 15**:
  ```ini
  # JANGAN AKTIFKAN opsi ini di Android 15:
  # CONFIG_DEBUG_INFO_NONE=y  ← Menyebabkan kegagalan BTF dan WiFi mati total

  # Opsi pembersihan log debug yang aman:
  CONFIG_SLUB_DEBUG=n
  CONFIG_FUNCTION_TRACER=n
  ```

---

## 2. Pemeliharaan KPROBES untuk Subsistem Root
* **Aturan Utama**: Pastikan konfigurasi KPROBES tetap aktif secara mutlak (`CONFIG_KPROBES=y`).
* **Rasionalisasi**: KernelSU-Next membutuhkan mekanisme Kprobes secara utuh untuk melakukan penyadapan (intercept) sistem panggilan inti (syscalls) pada ruang kernel. Jika fitur ini dinonaktifkan, subsistem KernelSU-Next tidak akan terkompilasi dengan sempurna atau gagal memberikan hak akses root ke perangkat.
* **Implementasi**: Jangan pernah menghapus atau menonaktifkan konfigurasi pelacakan kernel berikut:
  ```ini
  CONFIG_KPROBES=y
  CONFIG_HAVE_KPROBES=y
  CONFIG_KPROBE_EVENTS=y
  ```

---

## 3. Kebijakan Link-Time Optimization (LTO)
* **Aturan Utama**: Gunakan opsi `--lto=thin` saat menjalankan kompilasi melalui sistem Bazel.
* **Rasionalisasi**: Pengoptimalan LTO tingkat lanjut (`--lto=full`) mampu menghasilkan kompresi biner kernel yang lebih efisien, namun kompilasi tersebut membutuhkan konsumsi RAM yang sangat besar dan dipastikan akan mengalami kegagalan **OOM (Out Of Memory)** pada runner GitHub Actions (7GB RAM). Penggunaan opsi `--lto=thin` (ThinLTO) menawarkan kompromi terbaik dengan memberikan kompresi performa tingkat tinggi namun dengan konsumsi memori yang jauh lebih rendah, sehingga aman dan stabil untuk dijalankan di lingkungan runner terbatas.
* **Implementasi**: Opsi kompilasi terbaik yang terbukti aman dan stabil adalah menerapkan bendera `--lto=thin` dalam workflow kompilasi Bazel Anda dengan pembatasan memori `--local_resources=memory=6144` dan pembatasan thread paralel `--jobs=2`.

---

## 4. Efisiensi Baterai & Manajemen Memori
* **Implementasi Konfigurasi**:
  * **Frekuensi Detak Jam (HZ)**: Gunakan `CONFIG_HZ=300` sebagai standar optimal perangkat Android guna menyeimbangkan performa responsif dan efisiensi baterai.
  * **Manajemen Memori (MGLRU)**: Aktifkan generator LRU multi-generasi (`CONFIG_LRU_GEN=y`) yang terbukti jauh lebih cerdas dan hemat daya dalam mengelola proses pembersihan RAM di latar belakang.
  * **Halaman Memori Besar (THP)**: Nonaktifkan dukungan Transparent Hugepages (`CONFIG_TRANSPARENT_HUGEPAGE=n`). Fitur ini sangat boros RAM dan seringkali memicu degradasi performa (micro-stuttering) pada ponsel kelas menengah yang memiliki kapasitas memori terbatas.

---

## 5. Standarisasi Format Tag Rilis
* **Aturan Utama**: Penulisan tag rilis pada repositori GitHub harus unik dan mencerminkan konfigurasi build guna menghindari bentrokan artefak.
* **Format Standar**: `{tag}-{toolchain}-{governor}-{susfs}`
* **Contoh Implementasi**: `v1.0-bazel-default-schedutil-false`
