# PRD — Epitaph Kernel
**Product Requirements Document**
> Dokumen ini adalah **source of truth** untuk semua keputusan teknis di project Epitaph Kernel.
> Siapapun (manusia atau AI) yang mau nyentuh repo ini **wajib baca dokumen ini dulu**.
> Kalau ada konflik antara dokumen ini dengan instruksi lain — dokumen ini yang menang.

---

## 1. Gambaran Produk

**Epitaph Kernel** adalah custom GKI 6.6 kernel untuk **Xiaomi Redmi 12 (codename: fire)** yang menjalankan **Android 15 HyperOS 2.0**.

Dibangun dari branch `common-android15-6.6` milik Google, dikompilasi otomatis via GitHub Actions multi-toolchain pipeline, dan di-ship dalam format AnyKernel3 ZIP yang di-flash lewat **KernelFlasher** (bukan TWRP — tidak ada custom recovery untuk device ini).

### Siapa penggunanya?
- **Developer (maintainer):** Faqih Ardian Syah (@naidrahiqa) — satu-satunya maintainer
- **AI pair programmers:** Antigravity, Claude, Gemini, DeepSeek, Qwen — baca PRD ini sebagai konteks wajib
- **End user:** Pemilik Redmi 12 yang mau flash kernel kustom

### Apa value proposition-nya?
Kernel stock HyperOS 2.0 tidak bisa di-root dengan mudah dan tidak ada tuning performa. Epitaph memberikan:
1. Root via KernelSU-Next (kernel-level, lebih aman dari Magisk)
2. Opsional root-hiding via SUSFS (untuk banking apps)
3. Performa lebih baik: TCP BBR, BFQ I/O, schedutil tuned, ZRAM ZSTD
4. WiFi/Hotspot yang stabil (masalah kronis di GKI build untuk device ini)
5. Post-boot tuner (Epitaph Schedutil Performance) dengan 3 profil runtime

---

## 2. Konteks Device — WAJIB DIPAHAMI

| Field | Value |
|---|---|
| Device | Xiaomi Redmi 12 4G |
| Codename | `fire` |
| Chipset | MediaTek Helio G88 (MT6769), 12nm |
| CPU | 2×Cortex-A75 @ 2.0GHz + 6×Cortex-A55 @ 1.8GHz |
| GPU | Mali-G52 MC2 |
| RAM | 4 / 6 / 8 GB LPDDR4x |
| OS Target | Android 15 HyperOS 2.0 **ONLY** |
| Kernel Branch | `common-android15-6.6` (selalu tip of branch) |
| KMI | android15-8 |
| Partisi | A/B seamless, Dynamic (super) |
| Page Size | 4K (wajib, vendor modules compiled untuk 4K) |

### Panel Variant (KRITIKAL)
Device ini punya 4 varian panel LCD:
- **LC0A / LC0B** — kernel source tersedia, didukung ✅
- **LC0C / LC0D** — Xiaomi BELUM release source (GPL violation), tidak didukung ❌

Cek panel user: `adb shell getprop ro.boot.lcm_name`

---

## 3. Arsitektur Sistem

### 3.1 Struktur Repository

```
epitaph_kernel/
├── .github/workflows/
│   ├── _build_kernel_core.yml      ← Resep build utama (per matrix entry)
│   ├── build_manager_gki.yml       ← Dispatcher matrix (toolchain × SUSFS)
│   └── build_debug_bootimg.yml     ← Rescue kernel builder
├── scripts/
│   ├── prepare_kernel_build.sh     ← Disk, deps, repo sync, KSU setup
│   └── epitaph_tuner.sh            ← Post-boot optimizer (shipped di AK3)
├── workflow_scripts/
│   ├── patch_build_system.py       ← Register WiFi modules di BUILD.bazel
│   ├── patch_vermagic.py           ← Bypass vermagic untuk stock Xiaomi modules
│   └── patch_kbuild.py             ← Inject static KSU version ke Kbuild
├── patches/                        ← Custom .patch files (applied via patch -p1)
│   └── epitaph_schedutil.patch     ← Unlock schedutil rate limit minimum ke 100µs
└── guidelines/                     ← Aturan teknis per topik
```

### 3.2 Pipeline CI/CD

```
Trigger: workflow_dispatch (manual)
         └── build_manager_gki.yml
               ├── prepare: generate matrix (toolchain × SUSFS variant)
               ├── notify_start: Telegram notification
               ├── trigger: _build_kernel_core.yml (parallel, max 4)
               │     ├── prepare_kernel_build.sh
               │     │     ├── maximize_disk
               │     │     ├── setup_swap (16GB)
               │     │     ├── install_deps
               │     │     ├── install_repo
               │     │     ├── download_toolchain (jika bukan bazel-default)
               │     │     ├── sync_kernel (repo sync common-android15-6.6)
               │     │     ├── set_kmi
               │     │     ├── setup_ksu (pershoot/KernelSU-Next branch next-susfs)
               │     │     ├── apply_patches
               │     │     └── patch_build_system
               │     ├── Setup SUSFS (jika with_susfs=true)
               │     ├── Configure Kernel (defconfig)
               │     ├── Build (Bazel ATAU custom toolchain)
               │     ├── Extract Build Output
               │     ├── Verify Build
               │     ├── Package AnyKernel3
               │     ├── Upload Artifacts
               │     ├── Create GitHub Release
               │     └── Telegram notify (success/failure)
               └── summary: final status + Telegram
```

### 3.3 Toolchain Matrix

| Toolchain | Build System | Status | Notes |
|---|---|---|---|
| `bazel-default` | Bazel/Kleaf | ✅ **Production** | Satu-satunya yang production-tested |
| `aosp-latest` | make | ⚠️ Experimental | crdroidandroid prebuilt |
| `zyc-latest` | make | ⚠️ Experimental | ZyClang |
| `weebx-latest` | make | ⚠️ Experimental | WeebX Clang |
| `neutron-latest` | make | ⚠️ Experimental | Neutron Clang |

**Penting:** Bazel dan custom toolchain harus 100% terpisah. Jangan pernah symlink atau inject custom compiler ke Bazel prebuilt paths.

---

## 4. Fitur & Status

### 4.1 Root & Security

| Fitur | Status | Implementasi |
|---|---|---|
| KernelSU-Next | ✅ Selalu ada | `pershoot/KernelSU-Next` branch `next-susfs` |
| SUSFS 4 KSU | ✅ Optional build | `simonpunk/susfs4ksu` branch `gki-android15-6.6` |
| Vermagic bypass | ✅ Selalu aktif | `workflow_scripts/patch_vermagic.py` |

**SUSFS source yang benar:**
- KSU side: `pershoot/KernelSU-Next` branch `next-susfs` (sudah pre-patched, SKIP `10_enable_susfs_for_ksu.patch`)
- Kernel side: `simonpunk/susfs4ksu` — tetap apply `50_add_susfs_in_kernel.patch`
- Setelah semua `git add` di SUSFS step — WAJIB `git commit` sebelum Bazel build

### 4.2 Performa Kernel

| Fitur | Config | Status |
|---|---|---|
| CPU Governor | `CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y` | ✅ |
| TCP BBR | `CONFIG_TCP_CONG_BBR=y` + `CONFIG_NET_SCH_FQ=y` | ✅ |
| I/O BFQ | `CONFIG_IOSCHED_BFQ=y` | ✅ |
| I/O Kyber | `CONFIG_MQ_IOSCHED_KYBER=y` | ✅ |
| Timer HZ=300 | `CONFIG_HZ_300=y` | ✅ |
| WireGuard | `CONFIG_WIREGUARD=y` | ✅ |
| MGLRU | `CONFIG_LRU_GEN=y` | ✅ |
| ZRAM ZSTD | `CONFIG_CRYPTO_ZSTD=y` + `CONFIG_ZRAM_MULTI_COMP=y` | ✅ |
| PStore/RAMoops | `CONFIG_PSTORE_RAM=y` @ `0x4d010000` | ✅ |

### 4.3 Epitaph Schedutil Performance

Sistem profil runtime via `/data/adb/epitaph/mode`:

| Profil | up_rate | down_rate | GPU | Swappiness | Uclamp.min | Use Case |
|---|---|---|---|---|---|---|
| `performance` | 100µs | 40ms | always_on + GED boost | 200 | 180 (responsive) | Gaming / Max Performance |
| `balanced` | 500µs | 10ms | dynamic + GED boost | 180 | 64 (smooth UI) | Daily driver (default) |
| `battery` | 2ms | 1ms | coarse_demand | 160 | 0 (battery save) | Hemat baterai / Standby |

Ganti profil tanpa reflash:
```sh
echo "performance" > /data/adb/epitaph/mode && sh /data/adb/epitaph/apply
```

### 4.4 WiFi & Connectivity

| Fitur | Status | Notes |
|---|---|---|
| cfg80211 + mac80211 | ✅ Modular (`=m`) | Wajib modular, Bazel tracks sebagai module_outs |
| Netfilter NAT IPv4 | ✅ | `CONFIG_NF_NAT=y`, `CONFIG_IP_NF_TARGET_MASQUERADE=y` |
| Netfilter NAT IPv6 | ✅ | `CONFIG_IP6_NF_NAT=y`, `CONFIG_IP6_NF_TARGET_MASQUERADE=y` |
| WiFi fallback loader | ✅ Post-boot | `epitaph_tuner.sh` auto-insmod jika systemless gagal |

---

## 5. Known Issues & Root Causes

### 5.1 SUSFS Selalu Gagal Build (v1–v129)

**Status:** 🔴 Belum resolved sepenuhnya, fix sudah diidentifikasi

**Root causes:**
1. **KSU source salah** — pakai `KernelSU-Next/KernelSU-Next` branch `dev` yang tidak punya SUSFS hooks. Fix: pakai `pershoot/KernelSU-Next` branch `next-susfs`
2. **Bazel baca dari HEAD bukan staging** — `git add` tanpa `git commit` membuat Bazel tidak melihat perubahan SUSFS. Fix: tambah `git commit` setelah semua `git add` di SUSFS step
3. **`SUSFS_INTEGRATED` selalu true** — flag di-set berdasarkan Kconfig yang ditulis sendiri oleh script, bukan hasil patch yang berhasil. Fix: cek dari `fs/susfs.c` + `hooks.c` grep

**Fix yang perlu diimplementasi (belum masuk ke workflow):**
```bash
# Fix 1: Di prepare_kernel_build.sh
# GANTI: git clone https://github.com/KernelSU-Next/KernelSU-Next.git -b dev
# JADI:  git clone https://github.com/pershoot/KernelSU-Next -b next-susfs

# Fix 2: Di akhir Setup SUSFS step di _build_kernel_core.yml
git -c user.email="ci@epitaph" -c user.name="Epitaph CI" \
  commit -m "ci: integrate SUSFS" --allow-empty 2>/dev/null || true

# Fix 3: Ganti logika SUSFS_INTEGRATED
SUSFS_INTEGRATED=false
if [ "$SUSFS_PATCH_APPLIED" = "true" ] \
  && [ -f "fs/susfs.c" ] \
  && [ -f "include/linux/susfs.h" ] \
  && (grep -q "susfs" drivers/kernelsu/core_hook.c 2>/dev/null || grep -q "susfs" drivers/kernelsu/hooks.c 2>/dev/null); then
  SUSFS_INTEGRATED=true
fi
```

### 5.2 Bootloop Setelah Flash

**Penyebab paling umum (urutan frekuensi):**
1. Panel variant LC0C/LC0D — kernel tidak punya driver panel-nya
2. `CONFIG_DEBUG_INFO_NONE=y` aktif — membunuh BPF/BTF, WiFi mati, sistem crash
3. MTK built-in WiFi config (`CONFIG_MTK_COMBO_WIFI=y`) — konflik hardware
4. Kernel image format salah — bootloader MTK tolak raw `Image`, butuh `Image.gz`
5. KMI mismatch — vendor modules tidak bisa load
6. SUSFS compile setengah-setengah — `CONFIG_KSU_SUSFS=y` tapi source tidak ter-patch

**Recovery procedure:**
```bash
# Step 1: Flash stock boot
fastboot flash boot boot_stock.img && fastboot reboot

# Step 2: Pull crash log (dari PC, setelah masuk Android)
adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt
```

**PENTING:** Jangan flash multiple boot images via Fastboot berturut-turut — ini wipe RAMoops log.

### 5.3 WiFi/Hotspot Mati

**Penyebab:**
1. `CONFIG_DEBUG_INFO_NONE=y` — BTF metadata hilang, BPF untuk network management mati
2. WiFi modules tidak masuk `module_outs` di `BUILD.bazel` — tidak ikut di-ship
3. Modul dari kernel lama masih di `/vendor_dlkm` setelah flash rescue via Fastboot
4. `patch_build_system.py` gagal inject `cfg80211.ko`/`mac80211.ko`

**Fix WiFi modules tertinggal di `/vendor_dlkm`:**
```
1. Flash stock boot via Fastboot
2. Flash stock boot SEKALI LAGI via KernelFlasher (bukan Fastboot)
   → KernelFlasher restore modul asli Xiaomi ke /vendor_dlkm
3. Flash Epitaph ZIP yang baru via KernelFlasher
```

### 5.4 Build Gagal di CI/CD

**Penyebab umum:**
1. Bazel OOM — runner cuma 7GB RAM, butuh `--lto=none` + `--local_resources=memory=6144`
2. repo sync timeout — ada retry 3x, tapi koneksi ke googlesource kadang putus
3. SUSFS branch tidak exist — `gki-android15-6.6` belum tentu ada di setiap versi susfs4ksu
4. Bazel cache stale — clear manual via GitHub Actions UI jika dicurigai

---

## 6. Aturan Teknis — NON-NEGOTIABLE

Ini aturan yang tidak boleh dilanggar oleh siapapun, termasuk AI. Melanggar salah satu ini = bootloop atau build failure yang susah di-debug.

### 6.1 Defconfig Rules

| Config | Rule | Alasan |
|---|---|---|
| `CONFIG_DEBUG_INFO_NONE` | ❌ JANGAN AKTIFKAN | Membunuh BTF/BPF → WiFi mati di Android 15 |
| `CONFIG_MTK_COMBO_WIFI` | ❌ JANGAN AKTIFKAN | MTK built-in conflict → bootloop |
| `CONFIG_MTK_COMBO_BT` | ❌ JANGAN AKTIFKAN | Sama seperti di atas |
| `CONFIG_ZSMALLOC` | ✅ Harus `=m` | Bazel tracks sebagai module_out |
| `CONFIG_ZRAM` | ✅ Harus `=m` | Bazel tracks sebagai module_out |
| `CONFIG_CFG80211` | ✅ Harus `=m` | Modular, jangan `=y` |
| `CONFIG_MAC80211` | ✅ Harus `=m` | Modular, jangan `=y` |
| `CONFIG_KPROBES` | ✅ Harus `=y` | Required by KernelSU-Next |
| `CONFIG_HAVE_KPROBES` | ✅ Harus `=y` | Required by KernelSU-Next |
| `CONFIG_KPROBE_EVENTS` | ✅ Harus `=y` | Required by KernelSU-Next |
| `CONFIG_ARM64_4K_PAGES` | ✅ Harus `=y` | Vendor modules compiled untuk 4K |
| `CONFIG_MODVERSIONS` | ✅ Harus `=y` | Vendor DLKM compatibility |
| `CONFIG_EXT4_FS` | ✅ Harus `=y` | Required by KernelSU-Next |

### 6.2 Build System Rules

| Rule | Detail |
|---|---|
| Bazel flag `--lto` | Selalu `--lto=none` — OOM di 7GB runner |
| Bazel flag resources | Selalu `--local_resources=memory=6144` — bukan `--local_ram_resources` (deprecated) |
| Bazel jobs | `--jobs=2` untuk stabilitas runner |
| Kernel branch | Selalu tip of `common-android15-6.6` — jangan lock ke commit lama |
| KSU source | `pershoot/KernelSU-Next` branch `next-susfs` (SUSFS builds) |
| SUSFS patch | `50_add_susfs_in_kernel.patch` tetap apply; `10_enable_susfs_for_ksu.patch` SKIP |
| git commit | Wajib commit sebelum Bazel build — Bazel baca dari HEAD bukan staging |
| Toolchain isolation | Bazel dan custom toolchain 100% terpisah, jangan symlink |
| `patch_vermagic.py` | Jangan dihapus — bypass vermagic untuk stock Xiaomi modules |

### 6.3 AnyKernel3 Rules

| Rule | Detail |
|---|---|
| `supported.versions` | `=15` only — GKI 6.6 tidak kompatibel dengan Android 14 |
| Image priority | `Image.gz` → `Image.lz4` → `Image` — MTK bootloader sering tolak raw `Image` |
| Modules | `cfg80211.ko` dan `mac80211.ko` wajib di-ship dalam ZIP |

### 6.4 Recovery Rules

| Rule | Detail |
|---|---|
| Custom recovery | Tidak ada TWRP/OrangeFox untuk device ini — jangan pernah sarankan |
| Log retrieval | Via PStore: `adb shell "su -c cat /sys/fs/pstore/console-ramoops-0"` |
| Rescue kernel | `build_debug_bootimg.yml` — selalu bisa boot, PStore enabled |
| Fastboot sequencing | Jangan flash multiple images berturut-turut — wipe RAMoops |

---

## 7. Debugging Guide

### 7.1 Decision Tree Bootloop

```
HP bootloop setelah flash Epitaph
│
├── Langsung balik ke Fastboot?
│   └── Flash stock boot → boot Android → pull last_kmsg.txt
│       └── Cari: "Kernel panic", "Call Trace", "init: Service killed"
│
├── Stuck di logo (lama)?
│   └── Kemungkinan: driver panel (LC0C/LC0D) atau KSU init crash
│
└── Boot tapi langsung reboot?
    └── Kemungkinan: SUSFS setengah-setengah atau BPF crash
```

### 7.2 Cara Pull Crash Log

```bash
# Dari PC (BUKAN dari dalam adb shell):
adb shell "su -c cat /sys/fs/pstore/console-ramoops-0" > last_kmsg.txt

# Jika file tidak ada, coba:
adb shell "su -c cat /sys/fs/pstore/dmesg-ramoops-0" > last_kmsg.txt
```

### 7.3 Keyword Penting di Log

| Keyword | Artinya | Langkah |
|---|---|---|
| `Kernel panic` | Fatal crash | Lihat baris di atas — cari driver/fungsi pertama yang error |
| `Call Trace` | Stack trace sebelum crash | Baris teratas = sumber masalah |
| `BUG: scheduling while atomic` | Race condition di driver | Biasanya SUSFS hook conflict |
| `init: Service '...' killed` | Proses Android mati | Cek `dmesg \| grep avc` untuk SELinux |
| `module verification failed` | KMI/vermagic mismatch | Cek patch_vermagic.py berhasil jalan |
| `KSU: ` | KernelSU init log | Pastikan hooks terpasang benar |
| `cfg80211:` | WiFi subsystem | Cek module loading |

### 7.4 Debug Build CI/CD

Tambahkan di akhir Setup SUSFS step untuk debug:
```bash
echo "=== SUSFS DEBUG ==="
echo "SUSFS_PATCH_APPLIED: $SUSFS_PATCH_APPLIED"
echo "SUSFS_INTEGRATED: $SUSFS_INTEGRATED"
echo "fs/susfs.c: $([ -f fs/susfs.c ] && echo EXISTS || echo MISSING)"
echo "core_hook.c susfs lines: $(grep -c susfs drivers/kernelsu/core_hook.c 2>/dev/null || echo 0)"
echo "hooks.c susfs lines: $(grep -c susfs drivers/kernelsu/hooks.c 2>/dev/null || echo 0)"
git log --oneline -3
git status --short | head -20
```

---

## 8. Roadmap

### Sprint 1 — Fix SUSFS (URGENT, ready for verification)
- [x] Ganti KSU source ke `pershoot/KernelSU-Next` branch `next-susfs` di `prepare_kernel_build.sh`
- [x] Tambah `git commit` setelah SUSFS `git add` di `_build_kernel_core.yml`
- [x] Fix logika `SUSFS_INTEGRATED` — check dari source, bukan dari Kconfig yang ditulis sendiri (diperluas ke core_hook.c & hooks.c)
- [ ] Verifikasi: build SUSFS variant berhasil untuk pertama kalinya

### Sprint 2 — Defconfig Completeness (sebagian sudah done)
- [x] TCP BBR + FQ
- [x] HZ=300
- [x] BFQ + Kyber
- [x] WireGuard
- [x] MGLRU
- [x] ZRAM ZSTD multi-comp
- [ ] Verifikasi semua config benar-benar masuk di actual defconfig (bukan cuma di docs)

### Sprint 3 — Epitaph Schedutil Performance
- [x] Kernel patch (`patches/epitaph_schedutil.patch`) — unlock rate limit ke 100µs
- [x] Tuner script (`scripts/epitaph_tuner.sh`) — 3 profil dengan logging
- [ ] Apply script di AnyKernel3 (`_build_kernel_core.yml`)
- [ ] Test profil performance/balanced/battery di device

### Sprint 4 — Polish
- [ ] AnyKernel3 fork ke repo sendiri (pin commit, jangan pakai upstream langsung)
- [ ] Auto-changelog di release body
- [ ] LOCALVERSION dinamis dengan build number

---

## 9. Changelog Keputusan Teknis

Ini catatan keputusan penting yang pernah dibuat dan alasannya, supaya tidak diulang lagi.

| Tanggal | Keputusan | Alasan |
|---|---|---|
| v70 | Pakai schedutil, bukan performance/powersave | Paling stabil untuk daily driver, EAS-aware |
| v71 | Hapus CONFIG_DEBUG_INFO_NONE | ZyClang v71 bootloop — debug info dibutuhkan Android 15 BPF |
| v72 | Migrasi parser ke Python script | Heredoc inline di YAML sering IndentationError |
| v72 | Hapus Azure toolchain | Tidak kompatibel dengan Android 15 |
| v73 | Tambah Netfilter NAT lengkap | Hotspot IPv4/IPv6 tidak bisa share internet tanpa ini |
| v73 | Tambah Epitaph Tuner | GPU thermal bug MTK, CPU schedutil terlalu lambat naik |
| v129 | Identifikasi root cause SUSFS | 3 penyebab: KSU source salah, Bazel baca HEAD, SUSFS_INTEGRATED flag palsu |
| 2026-05 | Ganti KSU source ke pershoot/next-susfs | Pre-patched SUSFS, skip 10_enable_susfs patch manual |

---

## 10. Quick Reference

### Trigger Build
```
GitHub Actions → 🎛️ GKI Control Center → Run workflow
- release_tag: v1.x
- susfs_variant: no-susfs | susfs | both
- toolchain: bazel-default | all
```

### File ZIP Output
```
Epitaph-{Toolchain}-kernelsu-next[-SUSFS]-{DDMMYYYY}-AnyKernel3.zip
```

### Ganti Profil Tuner (tanpa reflash)
```bash
echo "performance" > /data/adb/epitaph/mode
sh /data/adb/epitaph/apply
cat /data/adb/epitaph/tuner.log  # cek status
```

### Cek Log Tuner
```bash
adb shell "cat /data/adb/epitaph/tuner.log"
adb shell "cat /data/adb/epitaph/status"
```

### Cek Panel Variant
```bash
adb shell getprop ro.boot.lcm_name
```

---

*Dokumen ini diupdate setiap ada keputusan teknis baru atau bug baru yang ditemukan.*
*Last updated: Mei 2026 — v129*