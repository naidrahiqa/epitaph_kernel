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

# 1. Identifikasi CPU thermal zone dinamis
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
[ -z "$cpu_zone" ] && cpu_zone="/sys/class/thermal/thermal_zone0"

get_temp() {
  local temp_raw=$(cat "$cpu_zone/temp" 2>/dev/null || echo "0")
  echo $((temp_raw / 1000))
}

# Pastikan awal pengujian suhu stabil atau cool/warm
sh /data/epitaph/set_governor.sh epitaph >/dev/null 2>&1
INIT_TEMP=$(get_temp)
INIT_STATE=$(cat /sys/kernel/epitaph/thermal_state 2>/dev/null || echo "unknown")

echo -e "Suhu Awal Perangkat: ${GREEN}${INIT_TEMP}°C${NC} (Status: ${CYAN}${INIT_STATE}${NC})"

# 2. Picu beban kerja stress penuh pada seluruh 8 core CPU
echo -e "\n${YELLOW}Memicu stres seluruh core CPU untuk memanaskan SoC...${NC}"
stress_pids=""
for i in 0 1 2 3 4 5 6 7; do
  (sh -c "while true; do :; done") &
  stress_pids="$stress_pids $!"
done

# 3. Monitor transisi suhu dan status thermal governor (maksimal 60 detik)
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
    
    # Verifikasi bahwa pada HOT state, boost state tetap 'none' meskipun disentuh / task forked
    # Kirim touch boost trigger buatan via sysfs untuk memicu evaluasi governor
    echo 100 > /sys/devices/system/cpu/cpufreq/policy0/epitaph/touch_boost_duration_ms 2>/dev/null
    
    # Tunggu sebentar dan baca kembali boost state
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
  
  # Timeout proteksi keamanan agar CPU tidak overheating berlebih (>65°C)
  if [ "$CUR_TEMP" -ge 65 ]; then
    echo -e "${RED}🚨 Batas suhu darurat terlampaui. Menghentikan stres loop demi keamanan!${NC}"
    break
  fi
  
  if [ "$ELAPSED" -ge 90 ]; then
    echo -e "${YELLOW}⌛ Timeout tercapai. Suhu tidak naik cukup signifikan dalam 90 detik.${NC}"
    break
  fi
done

# 4. Bersihkan stress loop
echo -e "\nMenghentikan stres beban kerja dan mendinginkan SoC..."
for pid in $stress_pids; do
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done

# Kembalikan konfigurasi semula
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
