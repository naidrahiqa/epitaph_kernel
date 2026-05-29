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
  # Konversi ke nilai absolut dan jadikan miliampere (mA)
  local cur_abs=${cur_raw#-}
  echo $((cur_abs / 1000))
}

run_workload_and_measure() {
  local gov_name="$1"
  
  # 1. Switch governor
  sh /data/epitaph/set_governor.sh "$gov_name" >/dev/null 2>&1
  sleep 2
  
  local start_pct=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "100")
  echo -e "\nMemulai pengujian untuk ${YELLOW}$gov_name${NC} (Kapasitas Awal: ${start_pct}%)..."
  
  # 2. Trigger multi-threaded workload (4 stress loops)
  local pids=""
  for i in 0 1 2 3; do
    (sh -c "while true; do :; done") &
    pids="$pids $!"
  done
  
  # 3. Ambil sampel arus pengosongan baterai setiap 2 detik selama 60 detik
  local total_current=0
  local samples=30
  local i=0
  
  while [ "$i" -lt "$samples" ]; do
    sleep 2
    local cur_ma=$(get_discharge_current)
    total_current=$((total_current + cur_ma))
    i=$((i + 1))
  done
  
  # Hentikan beban kerja
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  
  local end_pct=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "100")
  local avg_current=$((total_current / samples))
  local pct_drain=$((start_pct - end_pct))
  
  echo -e "  -> Pengujian Selesai. Rata-rata konsumsi arus: ${GREEN}${avg_current}mA${NC} | Penurunan Baterai: ${pct_drain}%"
  
  # Return data
  echo "${avg_current}:${pct_drain}"
}

# Pastikan perangkat sedang tidak dicharge
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
echo -e "  epitaph_performance     : ${GREEN}${CUR_PERF}mA${NC} (Delta %: -${DRAIN_PERF}%)"
echo -e "================================"
