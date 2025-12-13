#!/bin/bash
# Speak → type only final sentences into focused window

notify-send "🎤 STT" "Listening..."
stt | while read -r line; do
	# Skip empty or non-final lines
	[[ -z "$line" ]] && continue
	[[ "$line" != Sentence:* ]] && continue

	# Extract the text after "Sentence: "
	text="${line#Sentence: }"

	# Clean up invisible chars
	cleaned=$(echo "$text" | tr -cd '[:print:]\n')

	notify-send "🎤 STT" "Typing: $cleaned"
	xdotool type --delay 40 "$cleaned "
done
notify-send "🎤 STT" "Stopped listening."
