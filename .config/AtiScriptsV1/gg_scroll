#!/usr/bin/env bash

STATE_FILE="/tmp/qtile_gg_state"
TIMEOUT=0.5

NOW=$(date +%s.%N)

if [[ -f "$STATE_FILE" ]]; then
	LAST=$(cat "$STATE_FILE")
	ELAPSED=$(echo "$NOW - $LAST" | bc)

	if (($(echo "$ELAPSED < $TIMEOUT" | bc -l))); then
		# Second press detected → scroll to top
		xdotool click --repeat 300 --delay 0 4
		rm -f "$STATE_FILE"
		exit 0
	fi
fi

# First press: store timestamp
echo "$NOW" >"$STATE_FILE"
