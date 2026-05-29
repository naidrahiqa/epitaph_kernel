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
    TARGET_GOV="epitaph_performance"
    ;;
  powersave)
    TARGET_GOV="epitaph_powersave"
    ;;
  epitaph|balanced|*)
    TARGET_GOV="epitaph"
    ;;
esac

# 1. Switch scaling governors for all CPU policies
AVAILABLE_GOVS=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null)
if ! echo "$AVAILABLE_GOVS" | grep -q "$TARGET_GOV"; then
  # Fallback to standard schedutil if custom governor isn't compiled or loaded
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
  
  # Detect whether we are modifying cpufreq/epitaph or cpufreq/schedutil directory
  GOV_DIR=""
  if [ -d "$policy/epitaph" ]; then
    GOV_DIR="$policy/epitaph"
  elif [ -d "$policy/schedutil" ]; then
    GOV_DIR="$policy/schedutil"
  fi
  
  if [ -n "$GOV_DIR" ]; then
    case "$TARGET_GOV" in
      epitaph_performance)
        # Aggressive performance values
        if [ "$p_num" -eq 6 ]; then
          echo 1800000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.8GHz Big Core floor
          echo 70 > "$GOV_DIR/hispeed_load" 2>/dev/null
        else
          echo 1700000 > "$GOV_DIR/hispeed_freq" 2>/dev/null  # 1.7GHz Little Core floor
          echo 70 > "$GOV_DIR/hispeed_load" 2>/dev/null
        fi
        ;;
      epitaph_powersave)
        # Highly conservative powersaving values
        if [ "$p_num" -eq 6 ]; then
          echo 1150000 > "$GOV_DIR/hispeed_freq" 2>/dev/null
          echo 95 > "$GOV_DIR/hispeed_load" 2>/dev/null
        else
          echo 1100000 > "$GOV_DIR/hispeed_freq" 2>/dev/null
          echo 95 > "$GOV_DIR/hispeed_load" 2>/dev/null
        fi
        ;;
      epitaph|schedutil|*)
        # Balanced everyday usage values
        if [ "$p_num" -eq 6 ]; then
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
