#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Validation Suite — Governor Sanity Checks
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================

# ANSI terminal colors untuk status visual yang premium
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}=== EPITAPH GOVERNOR SANITY TESTS ===${NC}"

# Helper untuk memvalidasi test case
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

# 1. Pengecekan ketersediaan 3 custom governors di CPU0
echo -e "\n${YELLOW}Langkah 1: Memeriksa Ketersediaan Governor...${NC}"
AV_GOVS=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null)

echo "$AV_GOVS" | grep -q "epitaph"
assert_test "Governor 'epitaph' (balanced) terdeteksi" $?

echo "$AV_GOVS" | grep -q "epitaph_performance"
assert_test "Governor 'epitaph_performance' terdeteksi" $?

echo "$AV_GOVS" | grep -q "epitaph_powersave"
assert_test "Governor 'epitaph_powersave' terdeteksi" $?

# 2. Pengecekan sysfs tunables governor
echo -e "\n${YELLOW}Langkah 2: Memeriksa Sysfs Tunables...${NC}"
sh /data/epitaph/set_governor.sh epitaph >/dev/null 2>&1

TUNABLE_DIR="/sys/devices/system/cpu/cpufreq/policy0/epitaph"
if [ -d "$TUNABLE_DIR" ]; then
  assert_test "Direktori tunables governor seimbang ditemukan" 0
  
  # Tes tulis-baca pada sysfs nodes
  OLD_VAL=$(cat "$TUNABLE_DIR/hispeed_load" 2>/dev/null || echo "85")
  echo 90 > "$TUNABLE_DIR/hispeed_load" 2>/dev/null
  NEW_VAL=$(cat "$TUNABLE_DIR/hispeed_load" 2>/dev/null)
  
  if [ "$NEW_VAL" = "90" ]; then
    assert_test "Sysfs parameter 'hispeed_load' dapat ditulisi" 0
  else
    assert_test "Sysfs parameter 'hispeed_load' gagal ditulisi" 1
  fi
  echo "$OLD_VAL" > "$TUNABLE_DIR/hispeed_load" 2>/dev/null # Kembalikan nilai semula
  
  [ -f "$TUNABLE_DIR/touch_boost_duration_ms" ]
  assert_test "Parameter 'touch_boost_duration_ms' ditemukan" $?
  
  [ -f "$TUNABLE_DIR/touch_boost_freq" ]
  assert_test "Parameter 'touch_boost_freq' ditemukan" $?
else
  assert_test "Direktori tunables governor seimbang TIDAK ditemukan" 1
fi

# 3. Pengecekan parameter touch/launch boost global
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

# 4. Pengecekan modul koordinasi thermal
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

# 5. Kesimpulan akhir
echo -e "\n${CYAN}=====================================${NC}"
if [ "$GLOBAL_FAIL" -eq 0 ]; then
  echo -e "${GREEN}HASIL: SEMUA TES SANITY GOVERNOR LOLOS (PASS)${NC}"
  exit 0
else
  echo -e "${RED}HASIL: ADA $GLOBAL_FAIL TES SANITY GOVERNOR GAGAL (FAIL)${NC}"
  exit 1
fi
