#!/usr/bin/env bash
#
# Script name: dm-confedit
# Description: Hierarchical config file browser/editor
# Dependencies: rofi, nvim
# License: MIT

set -euo pipefail

# Configuration
RMENU="rofi -dmenu -i -p"
DMEDITOR="alacritty -e nvim"
CONFIG_DIR="$HOME/.config"
SEPARATOR=""

# File patterns to exclude (case insensitive)
# File patterns to exclude (case insensitive)
EXCLUDE_PATTERNS=(
	"*.jpg" "*.jpeg" "*.png" "*.gif" "*.webp" # Images
	"*.mp4" "*.avi" "*.mov" "*.mkv" "*.webm"  # Videos
	"*.mp3" "*.wav" "*.ogg" "*.flac"          # Audio
	"*.zip" "*.tar" "*.gz" "*.rar" "*.7z"     # Archives
	"*.pdf" "*.doc" "*.docx" "*.odt"          # Documents
	"*.iso" "*.img"                           # Disk images
	"*.bak" "*.tmp" "*.swp" "*.swo"           # Temporary/backup
	"*.log" "*.lock"                          # Logs and locks
	"*.db" "*.sqlite" "*.ldb"                 # Databases
	"*.cache" "*.old"                         # Cache and old files
	"*.bin" "*.exe" "*.dll"                   # Binaries
	"*.class" "*.pyc" "*.o" "*.so" "*.a"      # Compiled
	".DS_Store" "Thumbs.db"                   # System metadata
	"*.out" "*.obj"                           # Build artifacts
	"*.crt" "*.pem" "*.key"                   # SSL files
)

main() {
	local current_dir="$CONFIG_DIR"
	local navigation_stack=()

	while true; do
		# Get all directories and files in current directory
		local items=()
		local dirs=()
		local files=()

		# Find directories first
		while IFS= read -r -d '' dir; do
			local dir_name="${dir##*/}"
			dirs+=("$dir_name/")
		done < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

		# Then find files (excluding non-config patterns)
		while IFS= read -r -d '' file; do
			local filename="${file##*/}"
			local exclude_file=0

			# Check against exclude patterns
			for pattern in "${EXCLUDE_PATTERNS[@]}"; do
				if [[ "${filename,,}" == ${pattern,,} ]]; then
					exclude_file=1
					break
				fi
			done

			# Include if not excluded
			if [[ $exclude_file -eq 0 ]]; then
				files+=("$filename")
			fi
		done < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

		# Combine directories and files
		items=("${dirs[@]}" "${files[@]}")

		# Show current path in prompt
		local relative_path="${current_dir#$CONFIG_DIR/}"
		[[ -z "$relative_path" ]] && relative_path="ROOT"

		# Add back option if not in root
		[[ "$current_dir" != "$CONFIG_DIR" ]] && items=("../" "${items[@]}")

		# Show menu
		local choice=$(printf '%s\n' "${items[@]}" | $RMENU "Config ${SEPARATOR} ${relative_path}:")

		# Handle selection
		if [[ -z "$choice" ]]; then
			# Exit if nothing selected
			[[ ${#navigation_stack[@]} -eq 0 ]] && exit 0
			# Go back in navigation stack
			current_dir="${navigation_stack[-1]}"
			unset 'navigation_stack[-1]'
		elif [[ "$choice" == "../" ]]; then
			# Go up one directory
			current_dir="$(dirname "$current_dir")"
		elif [[ "$choice" == */ ]]; then
			# Enter directory
			navigation_stack+=("$current_dir")
			current_dir="${current_dir}/${choice%/}"
		else
			# Open file in nvim
			$DMEDITOR "${current_dir}/${choice}"
			exit 0
		fi
	done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
