#!/system/bin/sh
# ==============================================================================
#  Epitaph Kernel Stats Collector
#  Designed by Naidrahiqa & Antigravity AI
#  Epitaph Kernel — Redmi 12 (fire) — GKI 6.6
# ==============================================================================
# Skrip ini berjalan secara periodik untuk mengumpulkan metrik sistem vital
# dan menulis data tersebut dalam format JSON ke /data/epitaph/stats.json
# ==============================================================================

JSON_FILE="/data/epitaph/stats.json"
mkdir -p /data/epitaph 2>/dev/null

# 1. Mengumpulkan Informasi CPU Freq (LITTLE & BIG Clusters)
LITTLE_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null || echo "0")
BIG_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null || echo "0")

# Konversi ke MHz agar lebih manusiawi
LITTLE_MHZ=$((LITTLE_FREQ / 1000))
BIG_MHZ=$((BIG_FREQ / 1000))

# 2. Mengumpulkan Informasi Thermal Zone Suhu CPU
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

TEMP_RAW=$(cat "$cpu_zone/temp" 2>/dev/null || echo "0")
TEMP=$((TEMP_RAW / 1000))

# 3. Mengumpulkan Informasi RAM Tersedia
MEM_FREE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
if [ -z "$MEM_FREE_KB" ]; then
  MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
fi
MEM_FREE_MB=$((MEM_FREE_KB / 1024))

# 4. Membaca Profil Daya dan Status Thermal Aktif
PROFILE=$(getprop epitaph.profile 2>/dev/null | tr -d ' \r\n')
if [ -z "$PROFILE" ]; then
  PROFILE=$(cat /data/adb/epitaph/mode 2>/dev/null | tr -d ' \r\n')
fi
[ -z "$PROFILE" ] && PROFILE="balanced"

THERMAL_STATE=$(cat /data/adb/epitaph/thermal_state 2>/dev/null | tr -d ' \r\n')
[ -z "$THERMAL_STATE" ] && THERMAL_STATE="WARM"

# 5. Mengukur Kekuatan Sinyal WiFi (dBm RSSI)
WIFI_RSSI=$(grep "wlan0" /proc/net/wireless 2>/dev/null | awk '{print $4}' | tr -d '.')
if [ -z "$WIFI_RSSI" ]; then
  WIFI_RSSI=$(dumpsys wifi 2>/dev/null | grep -i "rssi" | head -n1 | grep -oE '\-[0-9]+')
fi
[ -z "$WIFI_RSSI" ] && WIFI_RSSI="-50"

# 6. Menghitung Waktu Uptime
UPTIME_SECS=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d. -f1)
[ -z "$UPTIME_SECS" ] && UPTIME_SECS="0"

UPTIME_H=$((UPTIME_SECS / 3600))
UPTIME_M=$(((UPTIME_SECS % 3600) / 60))
UPTIME_S=$((UPTIME_SECS % 60))
UPTIME_STR="${UPTIME_H}h ${UPTIME_M}m ${UPTIME_S}s"

# 7. Membentuk Struktur JSON Secara Mandiri & Menulis ke File
cat << EOF > "$JSON_FILE"
{
  "cpu": {
    "little_freq_mhz": $LITTLE_MHZ,
    "big_freq_mhz": $BIG_MHZ
  },
  "thermal": {
    "cpu_temp_c": $TEMP,
    "state": "$THERMAL_STATE"
  },
  "memory": {
    "available_ram_mb": $MEM_FREE_MB
  },
  "network": {
    "wifi_rssi_dbm": $WIFI_RSSI
  },
  "system": {
    "active_profile": "$PROFILE",
    "uptime": "$UPTIME_STR",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
  }
}
EOF

chmod 644 "$JSON_FILE" 2>/dev/null
echo "✅ Stats compiled into $JSON_FILE successfully."
