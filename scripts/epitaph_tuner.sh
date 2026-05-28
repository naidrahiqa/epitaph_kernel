#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Optimization & Reliability Tuner
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================
# File ini diletakkan di /data/adb/service.d/epitaph_tuner.sh oleh AnyKernel3
# Berjalan setiap boot via KernelSU/Magisk service.d
# ==============================================================================

sleep 5

LOG_FILE="/data/local/tmp/epitaph_tuner.log"
STATUS_FILE="/data/adb/epitaph/status"
mkdir -p /data/local/tmp 2>/dev/null
mkdir -p /data/adb/epitaph 2>/dev/null
chmod 644 "$LOG_FILE" 2>/dev/null

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Helper: menulis ke sysfs/procfs secara aman tanpa warning
write_value() {
  local val="$1"
  local target="$2"
  if [ -e "$target" ]; then
    { echo "$val" > "$target"; } 2>/dev/null
  fi
}

# Helper: menyalin konten berkas secara aman
copy_value() {
  local src="$1"
  local target="$2"
  if [ -f "$src" ] && [ -e "$target" ]; then
    { cat "$src" > "$target"; } 2>/dev/null
  fi
}

log_msg "=== EPITAPH TUNER STARTED ==="

# Inisialisasi folder profil Epitaph Schedutil Performance
MODE_FILE="/data/adb/epitaph/mode"
APPLY_FILE="/data/adb/epitaph/apply"

if [ ! -f "$MODE_FILE" ]; then
  echo "balanced" > "$MODE_FILE"
  chmod 644 "$MODE_FILE" 2>/dev/null
fi

MODE=$(cat "$MODE_FILE" | tr -d ' \r\n')
if [ "$MODE" != "performance" ] && [ "$MODE" != "balanced" ] && [ "$MODE" != "battery" ]; then
  MODE="balanced"
fi

log_msg "Selected Profile: $MODE"

# Membuat skrip trigger untuk apply real-time tanpa reboot
cat << 'EOF' > "$APPLY_FILE"
#!/system/bin/sh
# Trigger re-apply Epitaph Schedutil profile real-time tanpa reboot
/system/bin/sh /data/adb/service.d/epitaph_tuner.sh
EOF
chmod 755 "$APPLY_FILE" 2>/dev/null

# ──────────────────────────────────────────────────────────────────────────────
# 1. COMPREHENSIVE WIFI MODULE LOADER & RECOVERY
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 1: WiFi Module Recovery System starting..."

try_load_module() {
  local mod_path="$1"
  local filename="${mod_path##*/}"
  local mod_name="${filename%.ko}"
  if [ ! -f "$mod_path" ]; then
    log_msg "  [SKIP] $mod_path tidak ditemukan"
    return 1
  fi
  if lsmod | grep -q "^${mod_name}"; then
    log_msg "  [OK] $mod_name sudah termuat"
    return 0
  fi
  local err
  err=$(insmod "$mod_path" 2>&1)
  if [ $? -eq 0 ]; then
    log_msg "  [LOADED] $mod_name dari $mod_path"
    return 0
  else
    log_msg "  [FAIL] $mod_name: $err"
    return 1
  fi
}

CFG_LOADED=false
if lsmod | grep -q cfg80211; then
  log_msg "cfg80211 sudah termuat oleh init"
  CFG_LOADED=true
else
  log_msg "cfg80211 BELUM termuat — mencoba memuat secara manual..."
  for search_dir in \
    /vendor/lib/modules \
    /vendor_dlkm/lib/modules \
    /data/adb/wifi_fix \
    /system_dlkm/lib/modules \
    /lib/modules; do
    if [ -f "$search_dir/cfg80211.ko" ]; then
      try_load_module "$search_dir/rfkill.ko"
      try_load_module "$search_dir/libarc4.ko"
      try_load_module "$search_dir/cfg80211.ko"
      if lsmod | grep -q cfg80211; then
        CFG_LOADED=true
        log_msg "cfg80211 berhasil dimuat dari $search_dir"
        try_load_module "$search_dir/mac80211.ko"
        break
      fi
    fi
  done
fi

WLAN_LOADED=false
if lsmod | grep -qE "wlan_drv_gen4m"; then
  log_msg "Vendor WiFi driver (wlan_drv_gen4m/6768) sudah termuat"
  WLAN_LOADED=true
elif [ "$CFG_LOADED" = "true" ]; then
  log_msg "Memuat vendor WiFi driver..."
  for wlan_dir in \
    /vendor/lib/modules \
    /vendor_dlkm/lib/modules; do
    for wlan_file in wlan_drv_gen4m_6768.ko wlan_drv_gen4m.ko; do
      if [ -f "$wlan_dir/$wlan_file" ]; then
        try_load_module "$wlan_dir/$wlan_file"
        if lsmod | grep -qE "wlan_drv_gen4m"; then
          WLAN_LOADED=true
          log_msg "Vendor WiFi driver ($wlan_file) termuat dari $wlan_dir"
          break 2
        fi
      fi
    done
  done
  if [ "$WLAN_LOADED" = "false" ]; then
    log_msg "insmod gagal, mencoba modprobe wlan_drv_gen4m_6768..."
    modprobe wlan_drv_gen4m_6768 2>/dev/null && WLAN_LOADED=true && log_msg "modprobe wlan_drv_gen4m_6768 berhasil"
  fi
  if [ "$WLAN_LOADED" = "false" ]; then
    log_msg "mencoba modprobe wlan_drv_gen4m..."
    modprobe wlan_drv_gen4m 2>/dev/null && WLAN_LOADED=true && log_msg "modprobe wlan_drv_gen4m berhasil"
  fi
fi

if [ "$CFG_LOADED" = "true" ]; then
  WLAN_IFACE=$(getprop wifi.interface 2>/dev/null)
  WLAN_STATUS=$(getprop wlan.driver.status 2>/dev/null)
  log_msg "WiFi interface: ${WLAN_IFACE:-none}, driver status: ${WLAN_STATUS:-unknown}"

  if [ "$WLAN_STATUS" != "ok" ]; then
    log_msg "WiFi driver status tidak OK, melakukan restart service..."
    svc wifi disable 2>/dev/null
    sleep 1
    svc wifi enable 2>/dev/null
    sleep 2
    WLAN_STATUS_AFTER=$(getprop wlan.driver.status 2>/dev/null)
    log_msg "WiFi status setelah restart: ${WLAN_STATUS_AFTER:-unknown}"
  fi
else
  log_msg "WARNING: cfg80211 GAGAL dimuat! WiFi/Hotspot tidak akan berfungsi."
  lsmod >> "$LOG_FILE" 2>/dev/null
fi

log_msg "WiFi Recovery Summary: cfg80211=$CFG_LOADED, wlan_vendor=$WLAN_LOADED"

# ──────────────────────────────────────────────────────────────────────────────
# 2. CPU SCHEDUTIL GOVERNOR OPTIMIZATIONS
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 2: Tuning CPU Schedutil governors untuk profil: $MODE"

UP_RATE=500
DOWN_RATE=10000

case "$MODE" in
  performance)
    UP_RATE=100
    DOWN_RATE=40000
    ;;
  battery)
    UP_RATE=2000
    DOWN_RATE=1000
    ;;
  balanced|*)
    UP_RATE=500
    DOWN_RATE=10000
    ;;
esac

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  if [ -f "$policy/scaling_governor" ]; then
    gov=$(cat "$policy/scaling_governor")
    if [ "$gov" = "schedutil" ]; then
      write_value "$UP_RATE" "$policy/schedutil/up_rate_limit_us"
      write_value "$DOWN_RATE" "$policy/schedutil/down_rate_limit_us"
      
      # Nilai boost kustom untuk Epitaph Schedutil
      p_num="${policy##*policy}"
      b_factor=0
      b_threshold=95
      
      if [ "$p_num" -eq 6 ]; then
        # Kebijakan 6 (big cores: Cortex-A75)
        case "$MODE" in
          performance)
            b_factor=40
            b_threshold=30
            ;;
          battery)
            b_factor=0
            b_threshold=95
            ;;
          balanced|*)
            b_factor=15
            b_threshold=60
            ;;
        esac
      else
        # Kebijakan 0 (LITTLE cores: Cortex-A55)
        case "$MODE" in
          performance)
            b_factor=15
            b_threshold=60
            ;;
          battery)
            b_factor=0
            b_threshold=95
            ;;
          balanced|*)
            b_factor=5
            b_threshold=80
            ;;
        esac
      fi
      
      write_value "$b_factor" "$policy/schedutil/epitaph_boost_factor"
      write_value "$b_threshold" "$policy/schedutil/epitaph_boost_threshold"
      log_msg "Tuned $policy (schedutil): up=$UP_RATE, down=$DOWN_RATE, boost_factor=$b_factor, boost_threshold=$b_threshold"
    fi
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# 3. DYNAMIC GPU TUNING (GED & MALI CONTROLS)
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 3: Mengoptimalkan GPU secara dinamis untuk profil: $MODE..."

GPU_BOOST=0
BOOST_GPU_ENABLE=0
MALI_POWER_POLICY="dynamic"

case "$MODE" in
  performance)
    GPU_BOOST=1
    BOOST_GPU_ENABLE=1
    MALI_POWER_POLICY="always_on"
    ;;
  battery)
    GPU_BOOST=0
    BOOST_GPU_ENABLE=0
    MALI_POWER_POLICY="coarse_demand"
    ;;
  balanced|*)
    GPU_BOOST=0
    BOOST_GPU_ENABLE=1
    MALI_POWER_POLICY="dynamic"
    ;;
esac

# Terapkan konfigurasi GED (GPU Execution Daemon) MTK
if [ -d /sys/kernel/ged/hal ]; then
  write_value "$GPU_BOOST" /sys/kernel/ged/hal/gpu_boost
  write_value "$BOOST_GPU_ENABLE" /sys/module/ged/parameters/boost_gpu_enable
  log_msg "GED GPU settings applied: gpu_boost=$GPU_BOOST, boost_gpu_enable=$BOOST_GPU_ENABLE"
fi

# Terapkan Mali GPU driver power policy
for mali_dir in /sys/class/misc/mali0/device /sys/devices/platform/*.mali; do
  if [ -d "$mali_dir" ]; then
    write_value "$MALI_POWER_POLICY" "$mali_dir/power_policy"
    
    # Jika di mode performance, buka limit frekuensi GPU ke maksimum
    if [ "$MODE" = "performance" ]; then
      if [ -f "$mali_dir/dvfs_max_freq" ]; then
        if [ -f "$mali_dir/dvfs_max_freq_khz" ]; then
          copy_value "$mali_dir/dvfs_max_freq_khz" "$mali_dir/dvfs_max_freq"
        elif [ -f "$mali_dir/max_clock" ]; then
          copy_value "$mali_dir/max_clock" "$mali_dir/dvfs_max_freq"
        fi
      fi
    fi
    log_msg "Mali GPU power_policy set to $MALI_POWER_POLICY for $mali_dir"
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# 4. CPU UCLAMP DYNAMIC TUNING (MEMPERBAIKI DEEP SLEEP / DRAIN BATRE)
# ──────────────────────────────────────────────────────────────────────────────
# Masalah: uclamp.min di-set ke 1024 (maksimum) memaksa CPU berjalan pada clock tertinggi,
# menghalangi CPU masuk ke mode deep sleep. Kita reset & set nilai uclamp secara dinamis.
log_msg "Section 4: Menyetel CPU Uclamp secara dinamis untuk profil: $MODE"

UCLAMP_MIN_TOP_APP=64
UCLAMP_MIN_FOREGROUND=16
UCLAMP_MIN_BACKGROUND=0
UCLAMP_MIN_SYSTEM_BACKGROUND=0
UCLAMP_MIN_GLOBAL=0

case "$MODE" in
  performance)
    # Memberikan dorongan UI responsif, tetapi batasi maksimal 180 (tidak 1024!) agar deep sleep tidak mati
    UCLAMP_MIN_TOP_APP=180
    UCLAMP_MIN_FOREGROUND=64
    UCLAMP_MIN_BACKGROUND=0
    UCLAMP_MIN_SYSTEM_BACKGROUND=0
    UCLAMP_MIN_GLOBAL=0
    ;;
  battery)
    # Maksimalkan penghematan batre, matikan uclamp min
    UCLAMP_MIN_TOP_APP=0
    UCLAMP_MIN_FOREGROUND=0
    UCLAMP_MIN_BACKGROUND=0
    UCLAMP_MIN_SYSTEM_BACKGROUND=0
    UCLAMP_MIN_GLOBAL=0
    ;;
  balanced|*)
    # Nilai optimal untuk harian, hemat baterai dengan UI tetap mulus
    UCLAMP_MIN_TOP_APP=64
    UCLAMP_MIN_FOREGROUND=16
    UCLAMP_MIN_BACKGROUND=0
    UCLAMP_MIN_SYSTEM_BACKGROUND=0
    UCLAMP_MIN_GLOBAL=0
    ;;
esac

# Terapkan Uclamp ke cgroup scheduler Android
write_value "$UCLAMP_MIN_GLOBAL" /dev/cpuctl/cpu.uclamp.min
write_value "$UCLAMP_MIN_TOP_APP" /dev/cpuctl/top-app/cpu.uclamp.min
write_value "$UCLAMP_MIN_FOREGROUND" /dev/cpuctl/foreground/cpu.uclamp.min
write_value "$UCLAMP_MIN_BACKGROUND" /dev/cpuctl/background/cpu.uclamp.min
write_value "$UCLAMP_MIN_SYSTEM_BACKGROUND" /dev/cpuctl/system-background/cpu.uclamp.min

# Pastikan uclamp max tetap di 1024 agar CPU dapat naik ke frekuensi penuh saat dibutuhkan
write_value 1024 /dev/cpuctl/cpu.uclamp.max
write_value 1024 /dev/cpuctl/top-app/cpu.uclamp.max
write_value 1024 /dev/cpuctl/foreground/cpu.uclamp.max
write_value 1024 /dev/cpuctl/background/cpu.uclamp.max
write_value 1024 /dev/cpuctl/system-background/cpu.uclamp.max

log_msg "Uclamp Min applied: global=$UCLAMP_MIN_GLOBAL, top-app=$UCLAMP_MIN_TOP_APP, foreground=$UCLAMP_MIN_FOREGROUND"

# Matikan logging suspend berlebih untuk mempercepat masuk deep sleep
write_value 0 /sys/module/wakeup/parameters/enable_wakeup_log

# ──────────────────────────────────────────────────────────────────────────────
# 5. ZRAM & VIRTUAL MEMORY TUNING
# ──────────────────────────────────────────────────────────────────────────────
# Konfigurasi: ZRAM 6GB, compressor zstd, swappiness dinamis, dirty ratio 20
log_msg "Section 5: Tuning ZRAM & Virtual Memory..."

ZRAM_TARGET_SIZE=6442450944  # 6GB dalam Bytes
ZRAM_COMPRESSOR="zstd"

# Cek kondisi ZRAM saat ini agar tidak melakukan write lambat jika sudah sesuai
CURR_SIZE=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "0")
CURR_COMP=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')

if [ "$CURR_SIZE" != "$ZRAM_TARGET_SIZE" ] || [ "$CURR_COMP" != "$ZRAM_COMPRESSOR" ]; then
  log_msg "ZRAM tidak cocok (Size: $CURR_SIZE vs $ZRAM_TARGET_SIZE, Comp: $CURR_COMP vs $ZRAM_COMPRESSOR). Membangun ulang ZRAM..."
  swapoff /dev/block/zram0 2>/dev/null || true
  write_value 1 /sys/block/zram0/reset
  
  # Set kompresor zstd
  if grep -q "$ZRAM_COMPRESSOR" /sys/block/zram0/comp_algorithm 2>/dev/null; then
    write_value "$ZRAM_COMPRESSOR" /sys/block/zram0/comp_algorithm
    log_msg "ZRAM compressor set ke $ZRAM_COMPRESSOR"
  else
    # Fallback ke lz4 jika zstd tidak ada di kernel compile config
    write_value "lz4" /sys/block/zram0/comp_algorithm
    log_msg "ZRAM compressor zstd tidak didukung, menggunakan lz4"
  fi
  
  write_value "$ZRAM_TARGET_SIZE" /sys/block/zram0/disksize
  write_value 2 /sys/block/zram0/max_comp_streams
  mkswap /dev/block/zram0 2>/dev/null || true
  swapon /dev/block/zram0 -p 32767 2>/dev/null || true
  log_msg "ZRAM 6GB berhasil dibuat ulang."
else
  log_msg "ZRAM sudah optimal (6GB, $ZRAM_COMPRESSOR). Skip rebuild."
fi

# Terapkan Swappiness dinamis dan parameter Virtual Memory terkalibrasi untuk eMMC 5.1
SWAPPINESS_VAL=180
DIRTY_RATIO=15
DIRTY_BG_RATIO=3
WRITEBACK_CENTI=150
EXPIRE_CENTI=1000

case "$MODE" in
  performance)
    SWAPPINESS_VAL=200
    DIRTY_RATIO=10          # Kurangi batas akumulasi agar proses menulis tidak menghentikan layar (lag)
    DIRTY_BG_RATIO=2
    WRITEBACK_CENTI=100     # Lakukan sinkronisasi data kotor setiap 1 detik untuk menghindari penumpukan antrean
    EXPIRE_CENTI=500        # Waktu usang halaman kotor diatur ke 5 detik
    ;;
  battery)
    SWAPPINESS_VAL=160
    DIRTY_RATIO=20          # Tingkatkan batas akumulasi agar CPU tidak sering terbangun untuk I/O
    DIRTY_BG_RATIO=5
    WRITEBACK_CENTI=300     # Kumpulkan data kotor lebih lama (3 detik) untuk efisiensi baterai
    EXPIRE_CENTI=2000
    ;;
  balanced|*)
    SWAPPINESS_VAL=180
    DIRTY_RATIO=15
    DIRTY_BG_RATIO=3
    WRITEBACK_CENTI=150     # Flush berkala setiap 1.5 detik
    EXPIRE_CENTI=1000       # Waktu usang halaman kotor diatur ke 10 detik
    ;;
esac

write_value "$SWAPPINESS_VAL" /proc/sys/vm/swappiness
write_value 100 /proc/sys/vm/vfs_cache_pressure
write_value "$DIRTY_RATIO" /proc/sys/vm/dirty_ratio
write_value "$DIRTY_BG_RATIO" /proc/sys/vm/dirty_background_ratio
write_value "$WRITEBACK_CENTI" /proc/sys/vm/dirty_writeback_centisecs
write_value "$EXPIRE_CENTI" /proc/sys/vm/dirty_expire_centisecs

log_msg "VM parameters applied: swappiness=$SWAPPINESS_VAL, dirty_ratio=$DIRTY_RATIO, dirty_background_ratio=$DIRTY_BG_RATIO, writeback=$WRITEBACK_CENTI centisecs"

# ──────────────────────────────────────────────────────────────────────────────
# 6. OPTIMASI PENYIMPANAN & PENJADWAL I/O (eMMC 5.1)
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 6: Tuning antrean blok penyimpanan & penjadwal I/O..."
for queue in /sys/block/*/queue; do
  if [ -d "$queue" ]; then
    # 1. Optimasi Antrean Dasar untuk eMMC 5.1
    write_value 512 "$queue/read_ahead_kb"
    write_value 0 "$queue/add_random"           # Matikan kontribusi entropi acak dari aktivitas disk
    write_value 0 "$queue/rotational"           # Pastikan disk dikenali sebagai flash non-rotasional
    write_value 0 "$queue/iostats"              # Matikan pelacakan statistik I/O untuk mengurangi beban CPU
    write_value 2 "$queue/rq_affinity"          # Kembalikan I/O yang selesai ke CPU yang meminta (cache hit)
    write_value 1 "$queue/nomerges"             # Nonaktifkan penggabungan I/O kompleks, izinkan trivial merges untuk efisiensi eMMC 5.1

    # 2. Pemilihan Penjadwal I/O Dinamis untuk Mengurangi Stutter
    if [ -f "$queue/scheduler" ]; then
      available_scheds=$(cat "$queue/scheduler")
      target_sched="mq-deadline"
      
      case "$MODE" in
        performance)
          # Gunakan scheduler kyber dengan latensi sangat rendah jika tersedia
          if echo "$available_scheds" | grep -q "kyber"; then
            target_sched="kyber"
          else
            target_sched="mq-deadline"
          fi
          ;;
        balanced|battery|*)
          target_sched="mq-deadline"
          ;;
      esac
      
      write_value "$target_sched" "$queue/scheduler"
      
      # 3. Kalibrasi Parameter Scheduler secara Dinamis
      if [ "$target_sched" = "mq-deadline" ]; then
        if [ "$MODE" = "performance" ]; then
          write_value 100 "$queue/iosched/read_expire"   # default 500ms -> 100ms untuk respon instan
          write_value 4 "$queue/iosched/writes_starved"  # prioritaskan pembacaan di atas penulisan
        else
          write_value 250 "$queue/iosched/read_expire"
          write_value 2 "$queue/iosched/writes_starved"
        fi
      elif [ "$target_sched" = "kyber" ]; then
        if [ "$MODE" = "performance" ]; then
          write_value 2000000 "$queue/iosched/read_lat_nsec"   # Target latensi baca 2ms
          write_value 10000000 "$queue/iosched/write_lat_nsec" # Target latensi tulis 10ms
        fi
      fi
    fi
  fi
done
log_msg "Storage block queue depth & active I/O scheduler calibrated successfully"

# ──────────────────────────────────────────────────────────────────────────────
# 7. TCP SYSCTL NETWORK TUNING
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 7: Menerapkan optimasi TCP sysctl..."
write_value "bbr" /proc/sys/net/ipv4/tcp_congestion_control && log_msg "TCP congestion control set to BBR"
write_value "fq" /proc/sys/net/core/default_qdisc && log_msg "Default qdisc set to FQ"
write_value 3 /proc/sys/net/ipv4/tcp_fastopen && log_msg "TCP Fast Open set to 3"
write_value 0 /proc/sys/net/ipv4/tcp_slow_start_after_idle && log_msg "TCP slow start after idle dinonaktifkan (0)"

# ──────────────────────────────────────────────────────────────────────────────
# 8. HELIO G88 HETEROGENEOUS CPU/GPU EAS OPTIMIZATIONS
# ──────────────────────────────────────────────────────────────────────────────
log_msg "Section 8: Menerapkan cpuset locking & optimasi EAS Helio G88..."

# Optimasi cpuset dinamis berdasarkan profil daya aktif
CPUSET_BG="0-5"
CPUSET_RESTRICTED="0-5"

# Optimasi parameter penjadwal berdasarkan profil daya aktif
LATENCY_NS=16000000
MIN_GRAN_NS=3000000
WAKEUP_GRAN_NS=4000000

case "$MODE" in
  performance)
    CPUSET_BG="0-7"          # Izinkan background services memakai seluruh core untuk menghilangkan bottleneck game berat
    CPUSET_RESTRICTED="0-7"
    LATENCY_NS=10000000      # 10ms untuk responsivitas tinggi (menghilangkan micro-stutter)
    MIN_GRAN_NS=1500000      # 1.5ms
    WAKEUP_GRAN_NS=2000000   # 2.0ms
    ;;
  battery)
    CPUSET_BG="0-5"          # Batasi background processes ke little cores untuk hemat baterai
    CPUSET_RESTRICTED="0-5"
    LATENCY_NS=24000000      # 24ms untuk meminimalkan siklus bangun CPU (menghemat baterai)
    MIN_GRAN_NS=4000000      # 4.0ms
    WAKEUP_GRAN_NS=6000000   # 6.0ms
    ;;
  balanced|*)
    CPUSET_BG="0-5"          # Keseimbangan optimal untuk penggunaan sehari-hari
    CPUSET_RESTRICTED="0-5"
    LATENCY_NS=16000000      # 16ms untuk penggunaan sehari-hari
    MIN_GRAN_NS=3000000      # 3.0ms
    WAKEUP_GRAN_NS=4000000   # 4.0ms
    ;;
esac

# Terapkan cpuset yang telah ditentukan secara dinamis
write_value "$CPUSET_BG" /dev/cpuset/background/cpus
write_value "$CPUSET_BG" /dev/cpuset/system-background/cpus
write_value "$CPUSET_RESTRICTED" /dev/cpuset/restricted/cpus

# Menjamin foreground dan aplikasi utama (top-app) mendapat alokasi core optimal (0-7)
write_value "0-7" /dev/cpuset/top-app/cpus
write_value "0-7" /dev/cpuset/foreground/cpus

# Terapkan parameter scheduler EAS
write_value "$LATENCY_NS" /proc/sys/kernel/sched_latency_ns
write_value "$MIN_GRAN_NS" /proc/sys/kernel/sched_min_granularity_ns
write_value "$WAKEUP_GRAN_NS" /proc/sys/kernel/sched_wakeup_granularity_ns

log_msg "EAS scheduler parameters applied: latency=$LATENCY_NS ns, min_granularity=$MIN_GRAN_NS ns, cpuset_bg=$CPUSET_BG"

# Tulis status akhir untuk dibaca user/KSU
echo "active_profile: $MODE" > "$STATUS_FILE"
echo "wifi_status: cfg=$CFG_LOADED, vendor=$WLAN_LOADED" >> "$STATUS_FILE"
echo "zram_status: size=6GB, comp=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')" >> "$STATUS_FILE"
echo "uclamp_status: top-app-min=$UCLAMP_MIN_TOP_APP" >> "$STATUS_FILE"
echo "last_applied: $(date)" >> "$STATUS_FILE"

log_msg "=== EPITAPH TUNER COMPLETED SUCCESSFULLY ==="
