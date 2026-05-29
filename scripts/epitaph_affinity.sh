#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Per-App CPU Affinity Daemon
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================
# File ini berfungsi memantau aplikasi aktif di foreground.
# Menjadwalkan utas (threads) game berat pada cluster core besar (A75) secara dinamis.
# ==============================================================================

sleep 10

LOG_FILE="/data/local/tmp/epitaph_affinity.log"
GAME_LIST="/data/epitaph/game_list.txt"

mkdir -p /data/local/tmp 2>/dev/null
mkdir -p /data/epitaph 2>/dev/null

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 1. Konfigurasi default game list jika belum ada
if [ ! -f "$GAME_LIST" ]; then
  cat << 'EOF' > "$GAME_LIST"
# Epitaph CPU Affinity Game List
# Tambahkan nama paket aplikasi/game di bawah ini (satu per baris)
# Baris yang dimulai dengan '#' akan diabaikan

com.mobile.legends
com.tencent.ig
com.dts.freefireth
com.miHoYo.GenshinImpact
com.HoYoverse.hkrpg
com.garena.game.codm
com.kurogame.wutheringwaves
EOF
  chmod 644 "$GAME_LIST" 2>/dev/null
fi

# Konfigurasi Cluster Core Besar Helio G88 (Default: 6-7 untuk Cortex-A75)
# Core 0-5 adalah LITTLE (Cortex-A55), Core 6-7 adalah BIG (Cortex-A75)
BIG_CORES="6-7"
ALL_CORES="0-7"

log_msg "=== EPITAPH AFFINITY DAEMON STARTED ==="
log_msg "BIG core cluster target: $BIG_CORES"

LAST_BOOSTED_APP=""

# Fungsi pembantu untuk mem-parsing nama paket aktif di foreground secara efisien
get_foreground_app() {
  local focus=""
  # Metode 1: Mencari via dumpsys window displays (Sangat kompatibel untuk Android 11-15)
  focus=$(dumpsys window displays 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -n1)
  
  if [ -z "$focus" ]; then
    # Metode 2: Fallback ke dumpsys activity activities (Android 10/11)
    focus=$(dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity' | head -n1)
  fi
  
  if [ -n "$focus" ]; then
    # Ekstrak nama paket dari string dumpsys
    echo "$focus" | grep -oE '(?<= {)[^/]+|(?<= )[a-zA-Z0-9._]+(?=/)' | head -n1
  else
    echo ""
  fi
}

# Cek apakah suatu paket ada di dalam whitelist game_list.txt
is_whitelisted() {
  local pkg="$1"
  [ -z "$pkg" ] && return 1
  # Cari kecocokan eksak tanpa menghiraukan spasi dan komentar
  grep -v '^#' "$GAME_LIST" | grep -v '^$' | grep -xF "$pkg" >/dev/null 2>&1
}

# Terapkan CPU affinity (taskset) untuk seluruh utas (threads) proses
apply_affinity() {
  local pkg="$1"
  local cores="$2"
  local pids=$(pidof "$pkg")
  
  [ -z "$pids" ] && return 1
  
  local count=0
  for pid in $pids; do
    if [ -d "/proc/$pid/task" ]; then
      for tid_dir in /proc/$pid/task/*; do
        if [ -d "$tid_dir" ]; then
          local tid=$(basename "$tid_dir")
          taskset -p "$cores" "$tid" >/dev/null 2>&1
          count=$((count + 1))
        fi
      done
    fi
  done
  return 0
}

# Loop pemantauan efisien (Polling setiap 2 detik)
while true; do
  CURRENT_APP=$(get_foreground_app)
  
  if [ -n "$CURRENT_APP" ]; then
    # Jika game terdaftar masuk ke foreground
    if is_whitelisted "$CURRENT_APP"; then
      if [ "$CURRENT_APP" != "$LAST_BOOSTED_APP" ]; then
        # Kembalikan aplikasi sebelumnya ke core normal jika ada perubahan fokus
        if [ -n "$LAST_BOOSTED_APP" ]; then
          log_msg "🔄 Reverting affinity: $LAST_BOOSTED_APP ke ALL CORES ($ALL_CORES)"
          apply_affinity "$LAST_BOOSTED_APP" "$ALL_CORES"
        fi
        
        log_msg "⚡ Game Terdeteksi: $CURRENT_APP. Memindahkan semua utas ke core besar ($BIG_CORES)!"
        apply_affinity "$CURRENT_APP" "$BIG_CORES"
        LAST_BOOSTED_APP="$CURRENT_APP"
      else
        # Tetap terapkan afinitas secara periodik untuk menangani thread baru yang baru saja di-spawn
        apply_affinity "$CURRENT_APP" "$BIG_CORES"
      fi
    else
      # Jika aplikasi aktif bukan game terdaftar, kembalikan game sebelumnya ke core normal
      if [ -n "$LAST_BOOSTED_APP" ]; then
        log_msg "🔄 Game Ditutup/Background: $LAST_BOOSTED_APP. Mengembalikan ke ALL CORES ($ALL_CORES)"
        apply_affinity "$LAST_BOOSTED_APP" "$ALL_CORES"
        LAST_BOOSTED_APP=""
      fi
    fi
  fi
  
  sleep 2
done
