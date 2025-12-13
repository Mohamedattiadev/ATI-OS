#!/usr/bin/env bash
#
# Script name: dm-satty
# Description: Take screenshots with maim and optional editing with satty
# Dependencies: dmenu, maim, satty, xdotool, xclip, xrandr
# License: MIT

set -euo pipefail

# Configuration - customize these paths
MAIM_DIR="${HOME}/Screenshots"
MAIM_PREFIX="screenshot"
RMENU="rofi -dmenu -i -p"

# Create screenshot directory if it doesn't exist
mkdir -p "${MAIM_DIR}"

get_timestamp() {
	date '+%Y%m%d-%H%M%S'
}

copy_to_clipboard() {
	case "$XDG_SESSION_TYPE" in
	'x11') xclip -selection clipboard -t image/png ;;
	'wayland') wl-copy -t image/png ;;
	*)
		echo "Unknown display server"
		exit 1
		;;
	esac
}

show_error() {
	echo "Error: $1" >&2
	notify-send "Screenshot Error" "$1"
	exit 1
}

main() {
	local maim_args=""
	local file_type=""
	local use_satty=false

	# Available screenshot modes
	declare -a modes=(
		"Fullscreen"
		"Active window"
		"Selected region"
		"Fullscreen (edit with satty)"
		"Selected region (edit with satty)"
	)

	# Get monitor information
	if ! command -v xrandr &>/dev/null; then
		show_error "xrandr is required but not installed"
	fi

	_displays=$(xrandr --listactivemonitors 2>/dev/null | awk '/+/ {print $4, $3}' | awk -F'[x/+* ]' '{print $1,$2"x"$4"+"$6"+"$7}') || {
		show_error "Failed to get monitor information"
	}

	# Add monitor-specific options
	IFS=$'\n'
	declare -A display_mode
	for i in ${_displays}; do
		monitor_name="${i%% *}"
		modes+=("${monitor_name}")
		display_mode["${monitor_name}"]="${i##* }"
	done
	unset IFS

	# Prompt for screenshot type
	target=$(printf '%s\n' "${modes[@]}" | ${RMENU} "Take screenshot of:") || exit 0

	# Check if satty should be used
	case "$target" in
	*"(edit with satty)")
		use_satty=true
		target="${target% (edit with satty)*}"
		if ! command -v satty &>/dev/null; then
			show_error "satty is not installed"
		fi
		;;
	esac

	# Set maim arguments based on selection
	case "$target" in
	"Fullscreen")
		file_type="full"
		;;
	"Active window")
		if ! command -v xdotool &>/dev/null; then
			show_error "xdotool is required but not installed"
		fi
		active_window=$(xdotool getactivewindow)
		maim_args="-i ${active_window}"
		file_type="window"
		;;
	"Selected region")
		maim_args="-s"
		file_type="region"
		;;
	*)
		# Monitor selection
		maim_args="-g ${display_mode[${target}]}"
		file_type="${target}"
		;;
	esac

	# Prompt for delay
	delay=$(printf '%s\n' "$(seq 0 5)" | ${RMENU} "Delay (in seconds):") || exit 0
	if [ ! "${delay}" -eq "0" ]; then
		maim_args="${maim_args} --delay=${delay}"
	fi

	maim_args="${maim_args} -qd 0.5"

	if $use_satty; then
		# Capture and edit with satty
		temp_file="/tmp/satty-$(get_timestamp).png"
		maim ${maim_args} >"${temp_file}" || show_error "Failed to capture screenshot"

		# Check satty version and use appropriate syntax
		if satty --help | grep -q '\--filename'; then
			satty --filename "${temp_file}" || show_error "Failed to open satty"
		else
			satty "${temp_file}" || show_error "Failed to open satty"
		fi

		# Save edited screenshot to permanent location
		output_file="${MAIM_DIR}/${MAIM_PREFIX}-satty-$(get_timestamp).png"
		mv "${temp_file}" "${output_file}"
		notify-send "Screenshot Saved" "${output_file}"

	else
		# Regular screenshot options
		destination=$(printf '%s\n' "File" "Clipboard" "Both" | ${RMENU} "Destination:") || exit 0

		case "$destination" in
		"File")
			output_file="${MAIM_DIR}/${MAIM_PREFIX}-${file_type}-$(get_timestamp).png"
			maim ${maim_args} "${output_file}" || show_error "Failed to save screenshot"
			notify-send "Screenshot Saved" "${output_file}"
			;;
		"Clipboard")
			maim ${maim_args} | copy_to_clipboard || show_error "Failed to copy to clipboard"
			notify-send "Screenshot Copied" "Image saved to clipboard"
			;;
		"Both")
			output_file="${MAIM_DIR}/${MAIM_PREFIX}-${file_type}-$(get_timestamp).png"
			maim ${maim_args} | tee "${output_file}" | copy_to_clipboard || {
				show_error "Failed to save and copy screenshot"
			}
			notify-send "Screenshot Saved" "${output_file}\nAnd copied to clipboard"
			;;
		*)
			exit 0
			;;
		esac
	fi
}

# Run the main function
main "$@"
