#!/bin/bash

BAT="/sys/class/power_supply/BAT0"
AC="/sys/class/power_supply/AC"

LAST_STATUS=""
LAST_PERCENT=""
LAST_AC=""

read_battery() {
  STATUS=$(cat "$BAT/status")
  PERCENT=$(cat "$BAT/capacity")
  AC_ONLINE=$(cat "$AC/online" 2>/dev/null || echo 0)
}

notify() {
  notify-send "Battery" "$1"
}

notify_critical() {
  notify-send -u critical "Battery Low" "$1"
}

# Initial state
read_battery
LAST_STATUS="$STATUS"
LAST_PERCENT="$PERCENT"
LAST_AC="$AC_ONLINE"

# Listen for EVENTS (UPower-based, no polling loop)
upower --monitor-detail | while read -r _; do

  # Small settle delay (does NOT poll)
  sleep 1

  read_battery

  # Ignore fully duplicate refreshes
  [[ "$STATUS" == "$LAST_STATUS" && "$PERCENT" == "$LAST_PERCENT" && "$AC_ONLINE" == "$LAST_AC" ]] && continue

  # 🔌 Plug / unplug (AC-based, no duplicates)
  if [[ "$AC_ONLINE" != "$LAST_AC" ]]; then
    if [[ "$AC_ONLINE" == "1" ]]; then
      notify "🔌 Charger plugged in"
    else
      notify "🔌 Charger unplugged"
    fi
  fi

  # ✅ Full
  if [[ "$PERCENT" == "100" && "$LAST_PERCENT" != "100" ]]; then
    notify "✅ Battery is full — unplug charger"
  fi

  # 🔴 Low (fires ONLY when crossing 10%)
  if [[ "$PERCENT" -le 10 && "$LAST_PERCENT" -gt 10 && "$AC_ONLINE" == "0" ]]; then
    notify_critical "⚡ $PERCENT% remaining — plug in now!"
  fi

  LAST_STATUS="$STATUS"
  LAST_PERCENT="$PERCENT"
  LAST_AC="$AC_ONLINE"

done
