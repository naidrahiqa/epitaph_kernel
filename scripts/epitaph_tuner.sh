#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Optimization & Reliability Tuner (Thermal & Charging Aware)
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================
# File ini diletakkan di /data/adb/service.d/epitaph_tuner.sh oleh AnyKernel3
# Berjalan setiap boot via KernelSU/Magisk service.d atau runtime secara manual
# ==============================================================================

sleep 5

LOG_FILE="/data/local/tmp/epitaph_tuner.log"
STATUS_FILE="/data/adb/epitaph/status"
MODE_FILE="/data/adb/epitaph/mode"
APPLY_FILE="/data/adb/epitaph/apply"
GOV_LOG="/data/epitaph/governor.log"

# Direktori logging terdedikasi
mkdir -p /data/local/tmp 2>/dev/null
mkdir -p /data/adb/epitaph 2>/dev/null
mkdir -p /data/epitaph 2>/dev/null

chmod 644 "$LOG_FILE" 2>/dev/null

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_thermal() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "/data/epitaph/thermal.log"
}

log_charging() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "/data/epitaph/charging.log"
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

# ──────────────────────────────────────────────────────────────────────────────
# DYNAMIC WRITER: USER-FACING GOVERNOR SWITCH HELPER
# ──────────────────────────────────────────────────────────────────────────────
write_governor_helper() {
  cat << 'EOF' > /data/epitaph/set_governor.sh
#!/system/bin/sh
# ==============================================================================
#  Epitaph Governor Switch Helper Script
#  Designed by Naidrahiqa & Antigravity AI
#  Usage: sh set_governor.sh [epitaph|performance|powersave]
# ==============================================================================

GOV_ARG=$(echo "$1" | tr '[:upper:]' '[:lower:]')

LOG_FILE="/data/epitaph/governor.log"
mkdir -p /data/epitaph 2>/dev/null

log_gov() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Translate user argument to exact kernel governor name
case "$GOV_ARG" in
  performance)
    TARGET_GOV="epitaph_perf"
    ;;
  powersave)
    TARGET_GOV="epitaph_save"
    ;;
  epitaph|balanced|*)
    TARGET_GOV="epitaph"
    ;;
esac

# 1. Switch scaling governors for all CPU policies
AVAILABLE_GOVS=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null)
if ! echo "$AVAILABLE_GOVS" | grep -q "$TARGET_GOV"; then
  log_gov "⚠️ Governor $TARGET_GOV tidak tersedia. Fallback ke schedutil."
  TARGET_GOV="schedutil"
fi

log_gov "Swiching CPU governor to: $TARGET_GOV"

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  if [ -f "$policy/scaling_governor" ]; then
    echo "$TARGET_GOV" > "$policy/scaling_governor" 2>/dev/null
  fi
done

# 2. Re-apply correct hispeed_freq tuning parameters per governor type
# Helio G88 (MT6769) policy0 = cpu0-5 (A55 Little), policy6 = cpu6-7 (A75 Big)
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  [ ! -d "$policy" ] && continue
  p_num="${policy##*policy}"
  
  GOV_DIR=""
  if [ -d "$policy/$TARGET_GOV" ]; then
    GOV_DIR="$policy/$TARGET_GOV"
  elif [ -d "$policy/schedutil" ]; then
    GOV_DIR="$policy/schedutil"
  fi
  
  if [ -n "$GOV_DIR" ]; then
    case "$TARGET_GOV" in
      epitaph_perf)
        # Aggressive performance values
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          echo 1800000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.8GHz Big Core floor
          echo 70 > "$GOV_DIR/hispeed_load" 2>/dev/null
        else
          echo 1700000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.7GHz Little Core floor
          echo 70 > "$GOV_DIR/hispeed_load" 2>/dev/null
        fi
        ;;
      epitaph_save)
        # Highly conservative powersaving values
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          echo 1150000 > "$GOV_DIR/hispeed_freq" 2>/dev/null
          echo 95 > "$GOV_DIR/hispeed_load" 2>/dev/null
        else
          echo 1100000 > "$GOV_DIR/hispeed_freq" 2>/dev/null
          echo 95 > "$GOV_DIR/hispeed_load" 2>/dev/null
        fi
        ;;
      epitaph|schedutil|*)
        # Balanced everyday usage values (Initial Tunings)
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          echo 1800000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.8GHz Big floor
          echo 85 > "$GOV_DIR/hispeed_load" 2>/dev/null
        else
          echo 1700000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.7GHz Little floor
          echo 85 > "$GOV_DIR/hispeed_load" 2>/dev/null
        fi
        ;;
    esac
  fi
done

# 3. Print current governor state
echo "=== CPU GOVERNOR STATUS ==="
for cpu_dir in /sys/devices/system/cpu/cpu[0-7]; do
  cpu_idx="${cpu_dir##*cpu}"
  if [ -f "$cpu_dir/cpufreq/scaling_governor" ]; then
    cur_gov=$(cat "$cpu_dir/cpufreq/scaling_governor")
    cur_freq=$(cat "$cpu_dir/cpufreq/scaling_cur_freq")
    echo "  Core $cpu_idx: Governor=$cur_gov | Frequency=$((cur_freq / 1000))MHz"
  fi
done
echo "==========================="
EOF
  chmod 755 /data/epitaph/set_governor.sh
}

write_benchmark_suite() {
  mkdir -p /data/epitaph/bench 2>/dev/null

  # 1. governor_sanity.sh
  cat << 'EOF' > /data/epitaph/bench/governor_sanity.sh
#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Validation Suite — Governor Sanity Checks
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}=== EPITAPH GOVERNOR SANITY TESTS ===${NC}"

assert_test() {
  local desc="$1"
  local cond="$2"
  if [ "$cond" -eq 0 ]; then
    echo -e "  [ ${GREEN}PASS${NC} ] $desc"
  else
    echo -e "  [ ${RED}FAIL${NC} ] $desc"
    GLOBAL_FAIL=$((GLOBAL_FAIL + 1))
  fi
}

GLOBAL_FAIL=0

echo -e "\n${YELLOW}Langkah 1: Memeriksa Ketersediaan Governor...${NC}"
AV_GOVS=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null)

echo "$AV_GOVS" | grep -q "epitaph"
assert_test "Governor 'epitaph' (balanced) terdeteksi" $?

echo "$AV_GOVS" | grep -q "epitaph_perf"
assert_test "Governor 'epitaph_perf' terdeteksi" $?

echo "$AV_GOVS" | grep -q "epitaph_save"
assert_test "Governor 'epitaph_save' terdeteksi" $?

echo -e "\n${YELLOW}Langkah 2: Memeriksa Sysfs Tunables...${NC}"
sh /data/epitaph/set_governor.sh epitaph >/dev/null 2>&1

TUNABLE_DIR="/sys/devices/system/cpu/cpufreq/policy0/epitaph"
if [ -d "$TUNABLE_DIR" ]; then
  assert_test "Direktori tunables governor seimbang ditemukan" 0
  
  OLD_VAL=$(cat "$TUNABLE_DIR/hispeed_load" 2>/dev/null || echo "85")
  echo 90 > "$TUNABLE_DIR/hispeed_load" 2>/dev/null
  NEW_VAL=$(cat "$TUNABLE_DIR/hispeed_load" 2>/dev/null)
  
  if [ "$NEW_VAL" = "90" ]; then
    assert_test "Sysfs parameter 'hispeed_load' dapat ditulisi" 0
  else
    assert_test "Sysfs parameter 'hispeed_load' gagal ditulisi" 1
  fi
  echo "$OLD_VAL" > "$TUNABLE_DIR/hispeed_load" 2>/dev/null
  
  [ -f "$TUNABLE_DIR/touch_boost_duration_ms" ]
  assert_test "Parameter 'touch_boost_duration_ms' ditemukan" $?
  
  [ -f "$TUNABLE_DIR/touch_boost_freq" ]
  assert_test "Parameter 'touch_boost_freq' ditemukan" $?
else
  assert_test "Direktori tunables governor seimbang TIDAK ditemukan" 1
fi

echo -e "\n${YELLOW}Langkah 3: Memeriksa Input Touch & Launch Boost Nodes...${NC}"
[ -f "/sys/module/epitaph_input/parameters/enabled" ]
assert_test "Global touch boost toggle ditemukan" $?

[ -f "/sys/module/epitaph_input/parameters/launch_boost_enabled" ]
assert_test "Global launch boost toggle ditemukan" $?

[ -f "/sys/kernel/epitaph/boost_state" ]
assert_test "Telemetry node 'boost_state' ditemukan" $?

if [ -f "/sys/kernel/epitaph/boost_state" ]; then
  B_STATE=$(cat /sys/kernel/epitaph/boost_state 2>/dev/null)
  echo -e "  [ INFO ] Status boost saat ini: ${CYAN}$B_STATE${NC}"
fi

echo -e "\n${YELLOW}Langkah 4: Memeriksa Thermal Coordinator...${NC}"
[ -f "/sys/kernel/epitaph/thermal_state" ]
assert_test "Telemetry node 'thermal_state' ditemukan" $?

if [ -f "/sys/kernel/epitaph/thermal_state" ]; then
  T_STATE=$(cat /sys/kernel/epitaph/thermal_state 2>/dev/null)
  if [ "$T_STATE" = "cool" ] || [ "$T_STATE" = "warm" ] || [ "$T_STATE" = "hot" ]; then
    assert_test "Nilai telemetry 'thermal_state' valid ($T_STATE)" 0
  else
    assert_test "Nilai telemetry 'thermal_state' TIDAK valid ($T_STATE)" 1
  fi
fi

echo -e "\n${CYAN}=====================================${NC}"
if [ "$GLOBAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}HASIL: SEMUA TES SANITY GOVERNOR LOLOS (PASS)${NC}"
  exit 0
else
  echo -e "${RED}HASIL: ADA $GLOBAL_FAIL TES SANITY GOVERNOR GAGAL (FAIL)${NC}"
  exit 1
fi
EOF

  # 2. ramp_test.sh
  cat << 'EOF' > /data/epitaph/bench/ramp_test.sh
#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Validation Suite — CPU Frequency Ramp Latency Test
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================

CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== EPITAPH CPU FREQUENCY RAMP BENCHMARK ===${NC}"

CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy6"
[ ! -d "$CORE_POLICY" ] && CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy4"
[ ! -d "$CORE_POLICY" ] && CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy0"

CORE_NUM="${CORE_POLICY##*policy}"

test_governor_ramp() {
  local gov_name="$1"
  
  sh /data/epitaph/set_governor.sh "$gov_name" >/dev/null 2>&1
  sleep 1
  
  local min_f=$(cat "$CORE_POLICY/scaling_min_freq")
  local max_f=$(cat "$CORE_POLICY/scaling_max_freq")
  
  local target_hs=""
  if [ -d "$CORE_POLICY/epitaph" ]; then
    target_hs=$(cat "$CORE_POLICY/epitaph/hispeed_freq")
  elif [ -d "$CORE_POLICY/schedutil" ]; then
    target_hs=$(cat "$CORE_POLICY/schedutil/hispeed_freq")
  fi
  [ -z "$target_hs" ] || [ "$target_hs" -eq 0 ] && target_hs=$(( (min_f + max_f) / 2 ))
  
  echo -e "Memulai pengujian untuk ${YELLOW}$gov_name${NC} (Target hispeed_freq: $((target_hs / 1000))MHz)..."
  
  echo "$min_f" > "$CORE_POLICY/scaling_max_freq" 2>/dev/null
  sleep 3
  
  echo "$max_f" > "$CORE_POLICY/scaling_max_freq" 2>/dev/null
  
  local start_t=$(date +%s%3N)
  
  (taskset -c "$CORE_NUM" sh -c "while true; do :; done") &
  local stress_pid=$!
  
  local elapsed=0
  local cur_f=0
  while [ "$elapsed" -lt 1500 ]; do
    cur_f=$(cat "$CORE_POLICY/scaling_cur_freq" 2>/dev/null)
    if [ "$cur_f" -ge "$target_hs" ]; then
      local end_t=$(date +%s%3N)
      elapsed=$((end_t - start_t))
      break
    fi
    elapsed=$(( $(date +%s%3N) - start_t ))
  done
  
  kill -9 "$stress_pid" 2>/dev/null
  wait "$stress_pid" 2>/dev/null
  
  if [ "$cur_f" -ge "$target_hs" ]; then
    echo "$elapsed"
  else
    echo "TIMEOUT"
  fi
}

echo -e "Menjalankan uji responsivitas transisi beban kerja...\n"

LATENCY_EPITAPH=$(test_governor_ramp "epitaph")
sleep 2
LATENCY_PERF=$(test_governor_ramp "performance")
sleep 2
LATENCY_SAVE=$(test_governor_ramp "powersave")

echo -e "\n${CYAN}=== HASIL COMPARISON RAMP LATENCY ===${NC}"
echo -e "  epitaph (balanced)      : ${YELLOW}${LATENCY_EPITAPH}ms${NC}"
echo -e "  epitaph_perf            : ${YELLOW}${LATENCY_PERF}ms${NC}"
echo -e "  epitaph_save            : ${YELLOW}${LATENCY_SAVE}ms${NC}"
echo -e "======================================"
EOF

  # 3. battery_impact.sh
  cat << 'EOF' > /data/epitaph/bench/battery_impact.sh
#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Validation Suite — Battery Power Consumption Test
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================

CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m'

echo -e "${CYAN}=== EPITAPH BATTERY CONSUMPTION BENCHMARK ===${NC}"
echo -e "Metode: Mengukur rata-rata arus pengosongan daya (discharge current) selama 60 detik beban kerja multi-threaded."

get_discharge_current() {
  local cur_raw=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo "0")
  local cur_abs=${cur_raw#-}
  echo $((cur_abs / 1000))
}

run_workload_and_measure() {
  local gov_name="$1"
  
  sh /data/epitaph/set_governor.sh "$gov_name" >/dev/null 2>&1
  sleep 2
  
  local start_pct=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "100")
  echo -e "\nMemulai pengujian untuk ${YELLOW}$gov_name${NC} (Kapasitas Awal: ${start_pct}%)..."
  
  local pids=""
  for i in 0 1 2 3; do
    (sh -c "while true; do :; done") &
    pids="$pids $!"
  done
  
  local total_current=0
  local samples=30
  local i=0
  
  while [ "$i" -lt "$samples" ]; do
    sleep 2
    local cur_ma=$(get_discharge_current)
    total_current=$((total_current + cur_ma))
    i=$((i + 1))
  done
  
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  
  local end_pct=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "100")
  local avg_current=$((total_current / samples))
  local pct_drain=$((start_pct - end_pct))
  
  echo -e "  -> Pengujian Selesai. Rata-rata konsumsi arus: ${GREEN}${avg_current}mA${NC} | Penurunan Baterai: ${pct_drain}%"
  
  echo "${avg_current}:${pct_drain}"
}

BATT_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
if [ "$BATT_STATUS" = "Charging" ] || [ "$BATT_STATUS" = "Full" ]; then
  echo -e "${YELLOW}⚠️ PERINGATAN: Pengisi daya terhubung. Hasil arus pengosongan mungkin tidak akurat atau bernilai 0!${NC}"
fi

RES_EPITAPH=$(run_workload_and_measure "epitaph")
sleep 5
RES_PERF=$(run_workload_and_measure "performance")
sleep 5
RES_SAVE=$(run_workload_and_measure "powersave")

CUR_EPITAPH=${RES_EPITAPH%%:*}
DRAIN_EPITAPH=${RES_EPITAPH##*:}

CUR_PERF=${RES_PERF%%:*}
DRAIN_PERF=${RES_PERF##*:}

CUR_SAVE=${RES_SAVE%%:*}
DRAIN_SAVE=${RES_SAVE##*:}

echo -e "\n${CYAN}=== RINGKASAN EFISIENSI DAYA ===${NC}"
echo -e "  powersave (hemat daya)  : ${GREEN}${CUR_SAVE}mA${NC} (Delta %: -${DRAIN_SAVE}%)"
echo -e "  epitaph (balanced)      : ${GREEN}${CUR_EPITAPH}mA${NC} (Delta %: -${DRAIN_EPITAPH}%)"
echo -e "  epitaph_perf            : ${GREEN}${CUR_PERF}mA${NC} (Delta %: -${DRAIN_PERF}%)"
echo -e "================================"
EOF

  # 4. thermal_test.sh
  cat << 'EOF' > /data/epitaph/bench/thermal_test.sh
#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Validation Suite — Thermal Handoff Verification Test
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================

CYAN='\033[1;36m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

echo -e "${CYAN}=== EPITAPH THERMAL HANDOFF TEST ===${NC}"
echo -e "Metode: Memberikan beban penuh pada seluruh core CPU Helio G88 untuk menaikkan suhu"
echo -e "        serta memantau transisi status koordinasi thermal governor."

cpu_zone=""
for tz in /sys/class/thermal/thermal_zone*; do
  if [ -f "$tz/type" ]; then
    type=$(cat "$tz/type" | tr '[:upper:]' '[:lower:]')
    if echo "$type" | grep -qE "cpu|soc|mtktscpu"; then
      cpu_zone="$tz"
      break
    fi
  fi
done

if [ -z "$cpu_zone" ]; then
  echo -e "${YELLOW}⚠️ PERINGATAN: Tidak ada thermal zone CPU/SoC spesifik yang terdeteksi!${NC}"
  echo -e "  Mencoba fallback menggunakan /sys/class/thermal/thermal_zone0..."
  cpu_zone="/sys/class/thermal/thermal_zone0"
fi

if [ ! -d "$cpu_zone" ] || [ ! -f "$cpu_zone/temp" ]; then
  echo -e "${RED}❌ ERROR: Thermal zone '$cpu_zone' tidak valid atau berkas 'temp' hilang!${NC}"
  exit 1
fi

echo -e "  Menggunakan thermal zone: ${CYAN}$cpu_zone${NC} (${GREEN}$(cat $cpu_zone/type 2>/dev/null || echo "unknown")${NC})"

get_temp() {
  local temp_raw=$(cat "$cpu_zone/temp" 2>/dev/null || echo "0")
  echo $((temp_raw / 1000))
}

sh /data/epitaph/set_governor.sh epitaph >/dev/null 2>&1
INIT_TEMP=$(get_temp)
INIT_STATE=$(cat /sys/kernel/epitaph/thermal_state 2>/dev/null || echo "unknown")

echo -e "Suhu Awal Perangkat: ${GREEN}${INIT_TEMP}°C${NC} (Status: ${CYAN}${INIT_STATE}${NC})"

echo -e "\n${YELLOW}Memicu stres seluruh core CPU untuk memanaskan SoC...${NC}"
stress_pids=""
for i in 0 1 2 3 4 5 6 7; do
  (sh -c "while true; do :; done") &
  stress_pids="$stress_pids $!"
done

START_TIME=$(date +%s)
PASSED_WARM=false
PASSED_HOT=false

while true; do
  sleep 5
  CUR_TEMP=$(get_temp)
  CUR_STATE=$(cat /sys/kernel/epitaph/thermal_state 2>/dev/null || echo "unknown")
  CUR_BOOST=$(cat /sys/kernel/epitaph/boost_state 2>/dev/null || echo "unknown")
  
  ELAPSED=$(( $(date +%s) - START_TIME ))
  
  echo -e "[ ${ELAPSED}s ] Suhu: ${YELLOW}${CUR_TEMP}°C${NC} | State: ${CYAN}${CUR_STATE}${NC} | Active Boost: ${CYAN}${CUR_BOOST}${NC}"
  
  if [ "$CUR_STATE" = "warm" ]; then
    PASSED_WARM=true
  fi
  
  if [ "$CUR_STATE" = "hot" ]; then
    PASSED_HOT=true
    
    echo 100 > /sys/devices/system/cpu/cpufreq/policy0/epitaph/touch_boost_duration_ms 2>/dev/null
    
    sleep 1
    CUR_BOOST_TEST=$(cat /sys/kernel/epitaph/boost_state 2>/dev/null)
    
    echo -e "\n${YELLOW}Melakukan uji penolakan boost pada HOT state...${NC}"
    if [ "$CUR_BOOST_TEST" = "none" ] || [ -z "$CUR_BOOST_TEST" ]; then
      echo -e "  [ ${GREEN}PASS${NC} ] Boost dinonaktifkan sepenuhnya pada kondisi HOT"
      VERIFIED_BOOST_DISABLE=true
    else
      echo -e "  [ ${RED}FAIL${NC} ] Boost MASIH aktif (${CUR_BOOST_TEST}) pada kondisi HOT!"
      VERIFIED_BOOST_DISABLE=false
    fi
    break
  fi
  
  if [ "$CUR_TEMP" -ge 65 ]; then
    echo -e "${RED}🚨 Batas suhu darurat terlampaui. Menghentikan stres loop demi keamanan!${NC}"
    break
  fi
  
  if [ "$ELAPSED" -ge 90 ]; then
    echo -e "${YELLOW}⌛ Timeout tercapai. Suhu tidak naik cukup signifikan dalam 90 detik.${NC}"
    break
  fi
done

echo -e "\nMenghentikan stres beban kerja dan mendinginkan SoC..."
for pid in $stress_pids; do
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done

echo 80 > /sys/devices/system/cpu/cpufreq/policy0/epitaph/touch_boost_duration_ms 2>/dev/null

echo -e "\n${CYAN}=== ANALISIS HASIL KOORDINASI THERMAL ===${NC}"
if [ "$PASSED_WARM" = "true" ]; then
  echo -e "  Transisi ke WARM state  : ${GREEN}TERDETEKSI${NC}"
else
  echo -e "  Transisi ke WARM state  : ${RED}GAGAL${NC}"
fi

if [ "$PASSED_HOT" = "true" ]; then
  echo -e "  Transisi ke HOT state   : ${GREEN}TERDETEKSI${NC}"
else
  echo -e "  Transisi ke HOT state   : ${RED}GAGAL${NC}"
fi

if [ "$VERIFIED_BOOST_DISABLE" = "true" ]; then
  echo -e "  Proteksi Boost HOT      : ${GREEN}TERVERIFIKASI AMAN${NC}"
else
  echo -e "  Proteksi Boost HOT      : ${RED}LEAK/GAGAL${NC}"
fi
echo -e "==========================================="
EOF

  chmod 755 /data/epitaph/bench/*.sh 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
# DAEMON SUBROUTINES (Mencegah Eksekusi Ganda via Daemon Flag)
# ──────────────────────────────────────────────────────────────────────────────

# 1. Thermal-Aware Daemon Loop
thermal_daemon() {
  log_thermal "=== THERMAL DAEMON STARTED ==="
  local last_state=""
  
  # Identifikasi CPU thermal zone dinamis untuk Helio G88 (MT6769)
  local cpu_zone=""
  for tz in /sys/class/thermal/thermal_zone*; do
    if [ -f "$tz/type" ]; then
      local type=$(cat "$tz/type" | tr '[:upper:]' '[:lower:]')
      if echo "$type" | grep -qE "cpu|soc|mtktscpu"; then
        cpu_zone="$tz"
        break
      fi
    fi
  done
  
  [ -z "$cpu_zone" ] && cpu_zone="/sys/class/thermal/thermal_zone0"
  log_thermal "Thermal zone terpilih: $cpu_zone ($(cat $cpu_zone/type 2>/dev/null || echo 'unknown'))"
  
  while true; do
    local temp_raw=$(cat "$cpu_zone/temp" 2>/dev/null || echo "0")
    local temp=$((temp_raw / 1000))
    local current_state="WARM"
    
    if [ "$temp" -lt 40 ]; then
      current_state="COOL"
    elif [ "$temp" -gt 55 ]; then
      current_state="HOT"
    else
      current_state="WARM"
    fi
    
    # Deteksi transisi status thermal
    if [ "$current_state" != "$last_state" ]; then
      log_thermal "Transisi Suhu: ${last_state:-NONE} -> ${current_state} (${temp}°C)"
      last_state="$current_state"
      echo "$current_state" > "/data/adb/epitaph/thermal_state" 2>/dev/null
      
      # Terapkan pembatasan thermal governor & clock secara dinamis
      apply_thermal_tuning "$current_state"
    fi
    
    # Jalankan pengecekan memory pressure LMKD dinamis di loop yang sama
    tune_lmkd
    
    sleep 10
  done
}

# 2. Charging-State Boost Daemon Loop
charging_daemon() {
  log_charging "=== CHARGING DAEMON STARTED ==="
  local last_status=""
  
  while true; do
    local status=$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d ' \r\n')
    [ -z "$status" ] && status="Discharging"
    
    if [ "$status" != "$last_status" ]; then
      log_charging "Transisi Daya: ${last_status:-NONE} -> ${status}"
      last_status="$status"
      
      local therm_state=$(cat "/data/adb/epitaph/thermal_state" 2>/dev/null || echo "WARM")
      
      if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        if [ "$therm_state" = "HOT" ]; then
          log_charging "🚨 Suhu terlalu panas (${therm_state}). Boost pengisian daya dilewati."
          revert_charging_boost
        else
          apply_charging_boost
        fi
      else
        revert_charging_boost
      fi
    fi
    
    # Proteksi real-time jika perangkat tiba-tiba memanas saat dicas
    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
      local therm_state=$(cat "/data/adb/epitaph/thermal_state" 2>/dev/null || echo "WARM")
      local boost_active=$(cat "/data/adb/epitaph/charging_boost_active" 2>/dev/null || echo "false")
      
      if [ "$therm_state" = "HOT" ] && [ "$boost_active" = "true" ]; then
        log_charging "🚨 Perangkat memanas saat dicas! Mencabut boost pengisian daya secara darurat."
        revert_charging_boost
      elif [ "$therm_state" != "HOT" ] && [ "$boost_active" = "false" ]; then
        log_charging "⚡ Suhu stabil kembali. Menerapkan ulang boost pengisian daya."
        apply_charging_boost
      fi
    fi
    
    sleep 10
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# 3-MODE POWER PROFILE DEFINITIONS (Governor-Centric Transitions)
# ──────────────────────────────────────────────────────────────────────────────

battery() {
  log_msg "Tuning profile: battery"
  
  # 1. Switch to Epitaph Powersave Governor
  sh /data/epitaph/set_governor.sh powersave
  
  # CPU Frequency Caps (A55 Little Core & A75 Big Core)
  # LITTLE Cluster (policy0) batasi max ke 1.38GHz
  write_value 500000 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
  write_value 1380000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
  
  # BIG Cluster (policy6/4) batasi max ke 1.38GHz
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    p_num="${p##*policy}"
    if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
      write_value 900000 "$p/scaling_min_freq"
      write_value 1380000 "$p/scaling_max_freq"
    fi
  done
  
  # CPU Uclamp - Maksimal Penghematan Baterai
  write_value 0 /dev/cpuctl/cpu.uclamp.min
  write_value 0 /dev/cpuctl/top-app/cpu.uclamp.min
  write_value 0 /dev/cpuctl/foreground/cpu.uclamp.min
  write_value 0 /dev/cpuctl/background/cpu.uclamp.min
  write_value 0 /dev/cpuctl/system-background/cpu.uclamp.min
  
  # GPU Mali & GED Power Saving Settings
  write_value 0 /sys/kernel/ged/hal/gpu_boost
  write_value 0 /sys/module/ged/parameters/boost_gpu_enable
  for mali_dir in /sys/class/misc/mali0/device /sys/devices/platform/*.mali; do
    if [ -d "$mali_dir" ]; then
      write_value "coarse_demand" "$mali_dir/power_policy"
    fi
  done
  
  # Virtual Memory (Swappiness Rendah, Flush Agresif)
  write_value 130 /proc/sys/vm/swappiness
  write_value 20 /proc/sys/vm/dirty_ratio
  write_value 5 /proc/sys/vm/dirty_background_ratio
  write_value 300 /proc/sys/vm/dirty_writeback_centisecs
  write_value 2000 /proc/sys/vm/dirty_expire_centisecs
  
  # EAS Scheduler Latency (Batasi Siklus Bangun CPU)
  write_value 24000000 /proc/sys/kernel/sched_latency_ns
  write_value 4000000 /proc/sys/kernel/sched_min_granularity_ns
  write_value 6000000 /proc/sys/kernel/sched_wakeup_granularity_ns
  
  # Cpuset (Batasi Latar Belakang ke Little Core)
  write_value "0-5" /dev/cpuset/background/cpus
  write_value "0-5" /dev/cpuset/system-background/cpus
  write_value "0-5" /dev/cpuset/restricted/cpus
}

balanced() {
  log_msg "Tuning profile: balanced"
  
  # 1. Switch to Balanced Epitaph Governor
  sh /data/epitaph/set_governor.sh epitaph
  
  # CPU Frequency (Full Range untuk Little & Big)
  write_value 500000 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
  write_value 1800000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
  
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    p_num="${p##*policy}"
    if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
      write_value 900000 "$p/scaling_min_freq"
      write_value 2000000 "$p/scaling_max_freq"
    fi
  done
  
  # CPU Uclamp - Responsif tapi Ramah Baterai
  write_value 0 /dev/cpuctl/cpu.uclamp.min
  write_value 64 /dev/cpuctl/top-app/cpu.uclamp.min
  write_value 16 /dev/cpuctl/foreground/cpu.uclamp.min
  write_value 0 /dev/cpuctl/background/cpu.uclamp.min
  write_value 0 /dev/cpuctl/system-background/cpu.uclamp.min
  
  # GPU Mali & GED Balanced Settings
  write_value 0 /sys/kernel/ged/hal/gpu_boost
  write_value 1 /sys/module/ged/parameters/boost_gpu_enable
  for mali_dir in /sys/class/misc/mali0/device /sys/devices/platform/*.mali; do
    if [ -d "$mali_dir" ]; then
      write_value "dynamic" "$mali_dir/power_policy"
    fi
  done
  
  # Virtual Memory Balanced
  write_value 150 /proc/sys/vm/swappiness
  write_value 15 /proc/sys/vm/dirty_ratio
  write_value 3 /proc/sys/vm/dirty_background_ratio
  write_value 150 /proc/sys/vm/dirty_writeback_centisecs
  write_value 1000 /proc/sys/vm/dirty_expire_centisecs
  
  # EAS Scheduler Latency Balanced
  write_value 16000000 /proc/sys/kernel/sched_latency_ns
  write_value 3000000 /proc/sys/kernel/sched_min_granularity_ns
  write_value 4000000 /proc/sys/kernel/sched_wakeup_granularity_ns
  
  # Cpuset Balanced
  write_value "0-5" /dev/cpuset/background/cpus
  write_value "0-5" /dev/cpuset/system-background/cpus
  write_value "0-5" /dev/cpuset/restricted/cpus
}

performance() {
  log_msg "Tuning profile: performance"
  
  # 1. Switch to Epitaph Performance Governor
  sh /data/epitaph/set_governor.sh performance
  
  # CPU Frequency (Buka Limit Bawah Core untuk Menghilangkan Stutter)
  write_value 700000 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
  write_value 1800000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
  
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    p_num="${p##*policy}"
    if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
      write_value 1150000 "$p/scaling_min_freq"
      write_value 2000000 "$p/scaling_max_freq"
    fi
  done
  
  # CPU Uclamp - Responsivitas Maksimal untuk UI & Game (Tidak 1024 agar deepsleep aktif)
  write_value 0 /dev/cpuctl/cpu.uclamp.min
  write_value 180 /dev/cpuctl/top-app/cpu.uclamp.min
  write_value 64 /dev/cpuctl/foreground/cpu.uclamp.min
  write_value 0 /dev/cpuctl/background/cpu.uclamp.min
  write_value 0 /dev/cpuctl/system-background/cpu.uclamp.min
  
  # GPU Mali & GED High Boost Settings
  write_value 1 /sys/kernel/ged/hal/gpu_boost
  write_value 1 /sys/module/ged/parameters/boost_gpu_enable
  for mali_dir in /sys/class/misc/mali0/device /sys/devices/platform/*.mali; do
    if [ -d "$mali_dir" ]; then
      write_value "always_on" "$mali_dir/power_policy"
      if [ -f "$mali_dir/dvfs_max_freq" ]; then
        if [ -f "$mali_dir/dvfs_max_freq_khz" ]; then
          copy_value "$mali_dir/dvfs_max_freq_khz" "$mali_dir/dvfs_max_freq"
        elif [ -f "$mali_dir/max_clock" ]; then
          copy_value "$mali_dir/max_clock" "$mali_dir/dvfs_max_freq"
        fi
      fi
    fi
  done
  
  # Virtual Memory (Swappiness Tinggi untuk ZRAM, Sinkronisasi I/O Sangat Cepat)
  write_value 160 /proc/sys/vm/swappiness
  write_value 10 /proc/sys/vm/dirty_ratio
  write_value 2 /proc/sys/vm/dirty_background_ratio
  write_value 100 /proc/sys/vm/dirty_writeback_centisecs
  write_value 500 /proc/sys/vm/dirty_expire_centisecs
  
  # EAS Scheduler Latency Rendah (Menghindari Frame Drop)
  write_value 10000000 /proc/sys/kernel/sched_latency_ns
  write_value 1500000 /proc/sys/kernel/sched_min_granularity_ns
  write_value 2000000 /proc/sys/kernel/sched_wakeup_granularity_ns
  
  # Cpuset (Buka Semua Core untuk Background Services)
  write_value "0-7" /dev/cpuset/background/cpus
  write_value "0-7" /dev/cpuset/system-background/cpus
  write_value "0-7" /dev/cpuset/restricted/cpus
}

# ──────────────────────────────────────────────────────────────────────────────
# THERMAL-AWARE DYNAMIC SCALING
# ──────────────────────────────────────────────────────────────────────────────

apply_thermal_tuning() {
  local state="$1"
  log_thermal "Menerapkan limit thermal state: $state"
  
  case "$state" in
    COOL)
      # Kembalikan clock maksimal
      write_value 1800000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        p_num="${p##*policy}"
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          write_value 2000000 "$p/scaling_max_freq"
        fi
      done
      ;;
      
    WARM)
      # Profil standar harian
      write_value 1800000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        p_num="${p##*policy}"
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          write_value 2000000 "$p/scaling_max_freq"
        fi
      done
      ;;
      
    HOT)
      # Throttling Aktif: Pangkas clock atas untuk mencegah hardware degradation
      log_thermal "🚨 THROTILING AKTIF: Batasi frekuensi maksimal core!"
      write_value 1500000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        p_num="${p##*policy}"
        if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
          write_value 1600000 "$p/scaling_max_freq"
        fi
      done
      
      # Turunkan swappiness untuk mengurangi beban kerja CPU dari kompresi ZRAM intensif
      write_value 100 /proc/sys/vm/swappiness
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
# CHARGING-STATE BOOST SCALING
# ──────────────────────────────────────────────────────────────────────────────

apply_charging_boost() {
  echo "true" > "/data/adb/epitaph/charging_boost_active" 2>/dev/null
  log_charging "⚡ Mengaktifkan OC Charging Boost!"
  
  # Buka frekuensi maksimal
  write_value 1800000 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    p_num="${p##*policy}"
    if [ "$p_num" -eq 6 ] || [ "$p_num" -eq 4 ]; then
      write_value 2000000 "$p/scaling_max_freq"
    fi
  done
  
  # Dorong clock GPU agar tetap stabil saat beban berat serentak
  write_value 1 /sys/kernel/ged/hal/gpu_boost
}

revert_charging_boost() {
  echo "false" > "/data/adb/epitaph/charging_boost_active" 2>/dev/null
  local current_mode=$(cat "/data/adb/epitaph/mode" 2>/dev/null | tr -d ' \r\n')
  [ -z "$current_mode" ] && current_mode="balanced"
  log_charging "🔋 Menormalkan profil pengisian daya (kembali ke profil user: $current_mode)"
  
  # Re-apply mode aktif saat ini untuk menormalkan governor
  apply_profile "$current_mode"
}

# ──────────────────────────────────────────────────────────────────────────────
# DYNAMIC LOW MEMORY KILLER (LMKD) TUNING (4-6GB RAM Variants)
# ──────────────────────────────────────────────────────────────────────────────

tune_lmkd() {
  local mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  local mem_avail_mb=$((mem_avail_kb / 1024))
  
  local pressure_tier="comfortable"
  if [ "$mem_avail_mb" -lt 400 ]; then
    pressure_tier="tight"
  elif [ "$mem_avail_mb" -lt 800 ]; then
    pressure_tier="moderate"
  else
    pressure_tier="comfortable"
  fi
  
  local minfree_pages=""
  
  case "$MODE" in
    performance)
      case "$pressure_tier" in
        comfortable)
          minfree_pages="12288,16384,20480,24576,32768,46080"
          ;;
        moderate)
          minfree_pages="18432,23040,27648,32256,46080,61440"
          ;;
        tight)
          minfree_pages="23040,28160,33280,38400,56320,81920"
          ;;
      esac
      ;;
    battery)
      case "$pressure_tier" in
        comfortable)
          minfree_pages="18432,23040,27648,32256,51200,71680"
          ;;
        moderate)
          minfree_pages="23040,28160,33280,40960,61440,89600"
          ;;
        tight)
          minfree_pages="30720,35840,46080,56320,81920,115200"
          ;;
      esac
      ;;
    balanced|*)
      case "$pressure_tier" in
        comfortable)
          minfree_pages="15360,20480,25600,30720,40960,56320"
          ;;
        moderate)
          minfree_pages="18432,23040,27648,34560,51200,76800"
          ;;
        tight)
          minfree_pages="24576,30720,38400,46080,69120,97280"
          ;;
      esac
      ;;
  esac
  
  # Terapkan ke parameter driver lowmemorykiller kernel jika aktif
  if [ -e "/sys/module/lowmemorykiller/parameters/minfree" ]; then
    write_value "$minfree_pages" /sys/module/lowmemorykiller/parameters/minfree
  fi
  
  # Setel Android LMKD properti level minfree dinamis
  setprop sys.lmk.minfree_levels "$minfree_pages" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────────────
# SYSTEM INITIALIZATION & MAIN EXECUTION
# ──────────────────────────────────────────────────────────────────────────────

apply_profile() {
  local target_mode="$1"
  log_msg "Menerapkan profil daya utama: $target_mode"
  case "$target_mode" in
    battery)
      battery
      ;;
    performance)
      performance
      ;;
    balanced|*)
      balanced
      ;;
  esac
  
  # Sinkronisasi status persistensi profil
  echo "$target_mode" > "$MODE_FILE" 2>/dev/null
}

# Intercept background daemon calls immediately
if [ "$1" = "--thermal-daemon" ]; then
  thermal_daemon
  exit 0
fi

if [ "$1" = "--charging-daemon" ]; then
  charging_daemon
  exit 0
fi

log_msg "=== EPITAPH TUNER TUNING IN PROGRESS ==="

# 1. WIFI MODULE LOADER & RECOVERY
log_msg "Langkah 1: Menjalankan WiFi Module Loader..."
CFG_LOADED=false
if lsmod | grep -q cfg80211; then
  log_msg "cfg80211 sudah termuat"
  CFG_LOADED=true
else
  for search_dir in /data/adb/wifi_fix /vendor/lib/modules /vendor_dlkm/lib/modules; do
    if [ -f "$search_dir/cfg80211.ko" ]; then
      insmod "$search_dir/rfkill.ko" 2>/dev/null
      insmod "$search_dir/libarc4.ko" 2>/dev/null
      insmod "$search_dir/cfg80211.ko" 2>/dev/null
      if lsmod | grep -q cfg80211; then
        CFG_LOADED=true
        insmod "$search_dir/mac80211.ko" 2>/dev/null
        break
      fi
    fi
  done
fi

WLAN_LOADED=false
if lsmod | grep -qE "wlan_drv_gen4m"; then
  log_msg "Vendor WiFi driver sudah termuat"
  WLAN_LOADED=true
elif [ "$CFG_LOADED" = "true" ]; then
  for wlan_dir in /vendor/lib/modules /vendor_dlkm/lib/modules; do
    for wlan_file in wlan_drv_gen4m_6768.ko wlan_drv_gen4m.ko; do
      if [ -f "$wlan_dir/$wlan_file" ]; then
        insmod "$wlan_dir/$wlan_file" 2>/dev/null
        if lsmod | grep -qE "wlan_drv_gen4m"; then
          WLAN_LOADED=true
          break 2
        fi
      fi
    done
  done
fi

# 2. DYNAMICALLY GENERATE AND WRITE GOVERNOR SWITCH HELPER AND BENCHMARKS
log_msg "Langkah 2: Menulis skrip set_governor.sh dan benchmark suite..."
write_governor_helper
write_benchmark_suite

# Enable touch boost and launch boost via sysfs
write_value 1 /sys/module/epitaph_input/parameters/enabled
write_value 1 /sys/module/epitaph_input/parameters/launch_boost_enabled

# 3. READ PERSISTENT MODE AND APPLY THE INITIAL GOVERNOR
PROP_MODE=$(getprop epitaph.profile 2>/dev/null | tr -d ' \r\n')
if [ -n "$PROP_MODE" ]; then
  MODE="$PROP_MODE"
else
  MODE=$(cat "$MODE_FILE" 2>/dev/null | tr -d ' \r\n')
fi

[ -z "$MODE" ] && MODE="balanced"
if [ "$MODE" != "performance" ] && [ "$MODE" != "balanced" ] && [ "$MODE" != "battery" ]; then
  MODE="balanced"
fi

# Terapkan profil utama (yang sekarang memanggil set_governor.sh)
apply_profile "$MODE"

# Log which governor is active per CPU to /data/epitaph/governor.log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Active Governor Per CPU after boot initial configuration:" >> "$GOV_LOG"
for cpu_dir in /sys/devices/system/cpu/cpu[0-7]; do
  cpu_idx="${cpu_dir##*cpu}"
  if [ -f "$cpu_dir/cpufreq/scaling_governor" ]; then
    cur_gov=$(cat "$cpu_dir/cpufreq/scaling_governor")
    echo "  Core $cpu_idx: Governor=$cur_gov" >> "$GOV_LOG"
  fi
done

# 4. ZRAM & STORAGE OPTIMIZATIONS
log_msg "Langkah 4: Menginisialisasi VM, ZRAM, dan Block IO Scheduler..."
write_value 100 /proc/sys/vm/vfs_cache_pressure

# ZRAM 6GB Setup
ZRAM_SIZE=6442450944
if [ "$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)" != "$ZRAM_SIZE" ]; then
  swapoff /dev/block/zram0 2>/dev/null || true
  write_value 1 /sys/block/zram0/reset
  if grep -q "zstd" /sys/block/zram0/comp_algorithm 2>/dev/null; then
    write_value "zstd" /sys/block/zram0/comp_algorithm
  else
    write_value "lz4" /sys/block/zram0/comp_algorithm
  fi
  write_value "$ZRAM_SIZE" /sys/block/zram0/disksize
  write_value 2 /sys/block/zram0/max_comp_streams
  mkswap /dev/block/zram0 2>/dev/null || true
  swapon /dev/block/zram0 -p 32767 2>/dev/null || true
fi

# Antrean Blok Penyimpanan eMMC 5.1 & Scheduler
for queue in /sys/block/*/queue; do
  if [ -d "$queue" ]; then
    write_value 512 "$queue/read_ahead_kb"
    write_value 0 "$queue/add_random"
    write_value 0 "$queue/rotational"
    write_value 0 "$queue/iostats"
    write_value 2 "$queue/rq_affinity"
    write_value 1 "$queue/nomerges"
    if [ -f "$queue/scheduler" ]; then
      if grep -q "kyber" "$queue/scheduler" 2>/dev/null && [ "$MODE" = "performance" ]; then
        write_value "kyber" "$queue/scheduler"
      else
        write_value "mq-deadline" "$queue/scheduler"
      fi
    fi
  fi
done

# Optimasi TCP BBR
write_value "bbr" /proc/sys/net/ipv4/tcp_congestion_control
write_value "fq" /proc/sys/net/core/default_qdisc
write_value 3 /proc/sys/net/ipv4/tcp_fastopen
write_value 0 /proc/sys/net/ipv4/tcp_slow_start_after_idle

# Membuat skrip apply instan agar runtime manual berjalan mulus
cat << 'EOF' > "$APPLY_FILE"
#!/system/bin/sh
# Trigger re-apply Epitaph Schedutil profile real-time tanpa reboot
/system/bin/sh /data/adb/service.d/epitaph_tuner.sh
EOF
chmod 755 "$APPLY_FILE" 2>/dev/null

# 5. MEMULAI BACKGROUND MONITORING SECARA AMAN (Cegah Duplikasi Daemon)
log_msg "Langkah 5: Melakukan sterilisasi dan memicu proses background daemons..."

pkill -f "epitaph_tuner.sh --thermal-daemon" || true
pkill -f "epitaph_tuner.sh --charging-daemon" || true

/system/bin/sh /data/adb/service.d/epitaph_tuner.sh --thermal-daemon >/dev/null 2>&1 &
/system/bin/sh /data/adb/service.d/epitaph_tuner.sh --charging-daemon >/dev/null 2>&1 &

# Buat berkas status untuk info user / Kernel Manager
echo "active_profile: $MODE" > "$STATUS_FILE"
echo "wifi_status: cfg=$CFG_LOADED, vendor=$WLAN_LOADED" >> "$STATUS_FILE"
echo "thermal_monitor: active" >> "$STATUS_FILE"
echo "charging_boost: ready" >> "$STATUS_FILE"
echo "last_applied: $(date)" >> "$STATUS_FILE"

log_msg "=== EPITAPH TUNER INITIALIZATION COMPLETED SUCCESSFULLY ==="
