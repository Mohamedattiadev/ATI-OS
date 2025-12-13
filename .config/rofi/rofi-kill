#!/bin/bash

ROFI_THEME="$HOME/.config/rofi/themes/kill-large.rasi"
STATE_FILE="/tmp/rofi-kill-sort-mode"
SORT_MODE="${1:-$(cat "$STATE_FILE" 2>/dev/null || echo 'mem_desc')}"
EXCLUDE="(bash|rofi|Xorg|gnome-shell|wayland|systemd|ps|awk|sed|zsh|sh|dbus)"

# Bar characters for smooth graph
BAR_CHARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

# Contrasting colors
get_colors() {
	echo "#8BE9FD #BD93F9 #50FA7B #F1FA8C #FFB86C #FF79C6 #D6ACFF #9AEDFE #C1FF72 #FAF594"
}

get_sort_flag() {
	case "$1" in
	cpu_asc) echo "%cpu" ;;
	cpu_desc) echo "-%cpu" ;;
	mem_asc) echo "%mem" ;;
	mem_desc) echo "-%mem" ;;
	esac
}

next_sort_mode() {
	case "$1" in
	cpu_desc) echo "cpu_asc" ;;
	cpu_asc) echo "cpu_desc" ;;
	mem_desc) echo "mem_asc" ;;
	mem_asc) echo "mem_desc" ;;
	esac
}

# Build smooth usage bar
draw_bar() {
	value=$1
	levels=${#BAR_CHARS[@]}
	index=$(((value * (levels - 1)) / 100))
	printf "%s" "${BAR_CHARS[$index]}"
}

get_process_list() {
	ps -eo pid,comm,%cpu,%mem,etime,user --sort="$(get_sort_flag "$SORT_MODE")" | awk -v exclude="$EXCLUDE" -v colors="$(get_colors)" '
		BEGIN {
			split(colors, name_colors)
		}
		NR==1 { next }
		!($2 ~ exclude) {
			pid = $1
			cmd = $2
			cpu = $3 + 0
			mem = $4 + 0
			etime = $5
			user = $6

			hash = 0
			for (i = 1; i <= length(cmd); i++) hash += index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", substr(cmd, i, 1))
			color = name_colors[(hash % 10) + 1]

			icon = "🔧"
			if (cmd ~ /firefox/)       icon = "🌐"
			else if (cmd ~ /nautilus/) icon = "📁"
			else if (cmd ~ /code/)     icon = "💻"
			else if (cmd ~ /steam/)    icon = "🎮"
			else if (cmd ~ /vlc/)      icon = "🎞️"
			else if (cmd ~ /spotify/)  icon = "🎵"
			else if (cmd ~ /discord/)  icon = "💬"

			cpu_color = (cpu >= 50) ? "#FF5555" : (cpu >= 20 ? "#E5C07B" : "#FFFFFF")
			mem_color = (mem >= 30) ? "#FF6B6B" : (mem >= 10 ? "#E5C07B" : "#FFFFFF")

			printf "%s|%s|%s|%.1f|%.1f|%s|%s|%s\n", pid, icon, cmd, cpu, mem, etime, user, color
		}
	'
}

build_rofi_input() {
	get_process_list | while IFS='|' read -r pid icon cmd cpu mem etime user color; do
		cpu_bar=$(draw_bar "${cpu%.*}")
		mem_bar=$(draw_bar "${mem%.*}")
		printf "PID: %s | %s <span foreground=\"%s\">%s</span> | CPU: <span foreground=\"#FFB86C\">%.1f%% %s</span> | MEM: <span foreground=\"#BD93F9\">%.1f%% %s</span> | Uptime: %s | User: %s\n" \
			"$pid" "$icon" "$color" "$cmd" "$cpu" "$cpu_bar" "$mem" "$mem_bar" "$etime" "$user"
	done
}

chosen=$(
	build_rofi_input | rofi -markup-rows -dmenu \
		-theme "$ROFI_THEME" \
		-p "Kill Process" \
		-kb-custom-1 "Alt+c" \
		-kb-custom-2 "Alt+m" \
		-kb-custom-3 "Alt+p" \
		-kb-custom-4 "Alt+k" \
		-kb-custom-5 "Control+y" \
		-kb-accept-entry "!Control+a,Return"
)
ret=$?

[[ "$chosen" =~ ^PID:\ ([0-9]+) ]] && pid="${BASH_REMATCH[1]}"

copy_to_clipboard() {
	text="$1"
	if command -v wl-copy &>/dev/null; then
		echo -n "$text" | wl-copy
	elif command -v xclip &>/dev/null; then
		echo -n "$text" | xclip -selection clipboard
	elif command -v xsel &>/dev/null; then
		echo -n "$text" | xsel --clipboard --input
	else
		notify-send "❌ Clipboard tool not found"
	fi
}

# ALT+C – toggle CPU sort
if [[ $ret -eq 10 ]]; then
	new_mode=$([[ $SORT_MODE == cpu_* ]] && next_sort_mode "$SORT_MODE" || echo "cpu_desc")
	echo "$new_mode" >"$STATE_FILE"
	exec "$0" "$new_mode"

# ALT+M – toggle MEM sort
elif [[ $ret -eq 11 ]]; then
	new_mode=$([[ $SORT_MODE == mem_* ]] && next_sort_mode "$SORT_MODE" || echo "mem_desc")
	echo "$new_mode" >"$STATE_FILE"
	exec "$0" "$new_mode"

# ALT+P – Yank full command path
elif [[ $ret -eq 12 && -n "$pid" ]]; then
	path=$(ps -p "$pid" -o args=)
	copy_to_clipboard "$path"
	notify-send "📋 YANKED path: $path"
	exec "$0" "$SORT_MODE"

# ALT+K – force kill with confirmation
elif [[ $ret -eq 13 && -n "$pid" ]]; then
	answer=$(echo -e "❌ No\n✅ Yes" | rofi -dmenu -theme "$ROFI_THEME" -p "Force kill PID $pid?")
	if [[ "$answer" == *Yes* ]]; then
		kill -9 "$pid" && notify-send "☠️ Killed PID $pid" || notify-send "❌ Failed to kill PID $pid"
	fi
	exec "$0" "$SORT_MODE"

# CTRL+Y – Yank PID only
elif [[ $ret -eq 14 && -n "$pid" ]]; then
	copy_to_clipboard "$pid"
	notify-send "📋 Copied PID: $pid"
	exec "$0" "$SORT_MODE"

# ENTER – Regular kill with confirmation
elif [[ -n "$pid" ]]; then
	answer=$(echo -e "❌ No\n✅ Yes" | rofi -dmenu -theme "$ROFI_THEME" -p "Kill PID $pid?")
	if [[ "$answer" == *Yes* ]]; then
		kill -15 "$pid" && notify-send "✅ Process $pid killed" || notify-send "❌ Failed to kill process $pid"
	fi
	exec "$0" "$SORT_MODE"

# ESC or unknown key
else
	[[ $ret -eq 1 ]] && exit 0 || exec "$0" "$SORT_MODE"
fi
