#!/bin/bash

BAT="/sys/class/power_supply/BAT0"

LAST_STATUS=""
LAST_PERCENT=""

read_battery() {
	STATUS=$(cat "$BAT/status")
	PERCENT=$(cat "$BAT/capacity")
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

# Listen for EVENTS (no polling)
udevadm monitor --subsystem-match=power_supply | while read -r _; do

	# Wait for kernel to settle
	sleep 1

	read_battery

	# Ignore duplicate events
	[[ "$STATUS" == "$LAST_STATUS" && "$PERCENT" == "$LAST_PERCENT" ]] && continue

	# 🔌 Plug / unplug
	if [[ "$STATUS" != "$LAST_STATUS" ]]; then
		if [[ "$STATUS" == "Charging" ]]; then
			notify "🔌 Charger plugged in"
		elif [[ "$STATUS" == "Discharging" ]]; then
			notify "🔌 Charger unplugged"
		fi
	fi

	# ✅ Full
	if [[ "$PERCENT" == "100" && "$STATUS" == "Full" && "$LAST_PERCENT" != "100" ]]; then
		notify "✅ Battery is full — unplug charger"
	fi

	# 🔴 Low
	if [[ "$PERCENT" -le 10 && "$STATUS" == "Discharging" && "$LAST_PERCENT" -gt 10 ]]; then
		notify_critical "⚡ $PERCENT% remaining — plug in now!"
	fi

	LAST_STATUS="$STATUS"
	LAST_PERCENT="$PERCENT"

done
