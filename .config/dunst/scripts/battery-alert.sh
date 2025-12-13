#!/bin/bash

# Battery status and percentage (for systems with `/sys/class/power_supply/`)
BATTERY_PATH="/sys/class/power_supply/BAT0" # Adjust if needed (e.g., BAT1)
STATUS="$BATTERY_PATH/status"
CAPACITY="$BATTERY_PATH/capacity"

# Read current values
BATTERY_STATUS=$(cat "$STATUS")
BATTERY_PERCENT=$(cat "$CAPACITY")

# Critical alert (10% or below + discharging)
if [ "$BATTERY_PERCENT" -le 10 ] && [ "$BATTERY_STATUS" = "Discharging" ]; then
	notify-send -u critical -i battery-low "Battery Critical!" "⚡ $BATTERY_PERCENT% remaining, plug in now!" -t 0
fi

# Full charge alert (100% + "Full" status)
if [ "$BATTERY_PERCENT" -ge 100 ] && [ "$BATTERY_STATUS" = "Full" ]; then
	notify-send -u normal -i battery-full "Battery Fully Charged!" "🔌 Unplug to preserve battery health." -t 5000
fi
