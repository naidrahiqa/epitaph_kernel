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

# Target Core untuk Pengujian (Helio G88 policy6 = Core 6 A75 Big Core)
CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy6"
[ ! -d "$CORE_POLICY" ] && CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy4"
[ ! -d "$CORE_POLICY" ] && CORE_POLICY="/sys/devices/system/cpu/cpufreq/policy0"

CORE_NUM="${CORE_POLICY##*policy}"

test_governor_ramp() {
  local gov_name="$1"
  
  # 1. Switch governor
  sh /data/epitaph/set_governor.sh "$gov_name" >/dev/null 2>&1
  sleep 1
  
  local min_f=$(cat "$CORE_POLICY/scaling_min_freq")
  local max_f=$(cat "$CORE_POLICY/scaling_max_freq")
  
  # Dapatkan nilai hispeed_freq saat ini
  local target_hs=""
  if [ -d "$CORE_POLICY/epitaph" ]; then
    target_hs=$(cat "$CORE_POLICY/epitaph/hispeed_freq")
  elif [ -d "$CORE_POLICY/schedutil" ]; then
    target_hs=$(cat "$CORE_POLICY/schedutil/hispeed_freq")
  fi
  [ -z "$target_hs" ] || [ "$target_hs" -eq 0 ] && target_hs=$(( (min_f + max_f) / 2 ))
  
  echo -e "Memulai pengujian untuk ${YELLOW}$gov_name${NC} (Target hispeed_freq: $((target_hs / 1000))MHz)..."
  
  # 2. Paksa CPU ke frekuensi minimum untuk menstabilkan kondisi idle (3 detik)
  echo "$min_f" > "$CORE_POLICY/scaling_max_freq" 2>/dev/null
  sleep 3
  
  # Kembalikan batas maksimal frekuensi
  echo "$max_f" > "$CORE_POLICY/scaling_max_freq" 2>/dev/null
  
  # 3. Catat waktu mulai dan picu beban kerja stress loop (dipasangkan ke core target via taskset)
  local start_t=$(date +%s%3N)
  
  # Trigger stress loop background
  (taskset -c "$CORE_NUM" sh -c "while true; do :; done") &
  local stress_pid=$!
  
  # 4. Polling frekuensi secara intensif hingga mencapai target hispeed_freq
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
  
  # Bersihkan stress background process
  kill -9 "$stress_pid" 2>/dev/null
  wait "$stress_pid" 2>/dev/null
  
  if [ "$cur_f" -ge "$target_hs" ]; then
    echo "$elapsed"
  else
    echo "TIMEOUT"
  fi
}

# Jalankan pengujian ramp-up speed secara berurutan
echo -e "Menjalankan uji responsivitas transisi beban kerja...\n"

LATENCY_EPITAPH=$(test_governor_ramp "epitaph")
sleep 2
LATENCY_PERF=$(test_governor_ramp "performance")
sleep 2
LATENCY_SAVE=$(test_governor_ramp "powersave")

echo -e "\n${CYAN}=== HASIL COMPARISON RAMP LATENCY ===${NC}"
echo -e "  epitaph (balanced)      : ${YELLOW}${LATENCY_EPITAPH}ms${NC}"
echo -e "  epitaph_performance     : ${YELLOW}${LATENCY_PERF}ms${NC}"
echo -e "  epitaph_powersave       : ${YELLOW}${LATENCY_SAVE}ms${NC}"
echo -e "======================================"
