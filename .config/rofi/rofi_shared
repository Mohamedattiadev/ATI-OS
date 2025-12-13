#!/bin/bash

ROFI_THEME="$HOME/.config/rofi/themes/kill-large.rasi"
VIDEO_FILE="$HOME/.config/rofi/Todo_files/Shared_Links.md"
THUMB_DIR="/tmp/link-thumbs"
mkdir -p "$THUMB_DIR"

BROWSER="brave" # or firefox/chromium/etc.

# Clipboard helper
copy_to_clipboard() {
	local text="$1"
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

# Thumbnail function using jq for reliability
get_thumbnail() {
	local url="$1"
	local thumb_path="$THUMB_DIR/$(echo -n "$url" | md5sum | cut -d' ' -f1).jpg"
	local vid img_url

	if [[ ! -f "$thumb_path" ]]; then
		if [[ "$url" =~ (youtu\.be|youtube\.com) ]]; then
			vid=$(echo "$url" | grep -oE '([A-Za-z0-9_-]{11})' | sed 1q)
			if [[ -n "$vid" ]]; then
				wget -q -O "$thumb_path" "https://img.youtube.com/vi/${vid}/hqdefault.jpg"
			fi
		fi
		if [[ ! -s "$thumb_path" ]]; then
			img_url=$(curl -s "https://api.microlink.io/?url=${url}&palette=true" | jq -r '.data.image.url // empty')
			if [[ -n "$img_url" ]]; then
				wget -q -O "$thumb_path" "$img_url"
			fi
		fi
		if [[ ! -s "$thumb_path" ]]; then
			convert -size 480x270 xc:'#333333' -gravity center -fill white -pointsize 24 -annotate 0 "No Preview" "$thumb_path"
		fi
	fi
	echo "$thumb_path"
}

# Build rofi input from markdown file
build_rofi_input() {
	grep -Eo '\[.*\]\(http[^)]+\)' "$VIDEO_FILE" | while read -r line; do
		title=$(echo "$line" | sed -E 's/^\[(.*)\]\(http.*\)$/\1/')
		url=$(echo "$line" | sed -E 's/^\[.*\]\((http.*)\)$/\1/')
		echo "$title|$url"
	done
}

# Show preview in feh
show_preview() {
	local url="$1"
	local thumb_path
	thumb_path=$(get_thumbnail "$url")
	pkill -f "feh --title link-preview" 2>/dev/null
	(feh --title "link-preview" \
		--geometry 200x150 \
		--scale-down \
		--zoom max \
		--force-aliasing \
		"$thumb_path" </dev/null &>/dev/null &)
}

# Function to add a new link
add_new_link() {
	local url="$1"
	if ! [[ "$url" =~ ^https?:// ]]; then
		notify-send "❌ Invalid Input" "'$url' is not a valid URL."
		return
	fi
	notify-send "⏳ Fetching title for..." "$url"
	local page_title
	page_title=$(curl -sL --max-time 10 "$url" | grep -io '<title>.*</title>' | sed -e 's/<title>\(.*\)<\/title>/\1/' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n 1)
	if [[ -z "$page_title" ]]; then
		page_title=$(echo "$url" | sed -E 's_https?://([^/]+)/?.*_\1_')
		notify-send "⚠️ Title not found" "Using domain '$page_title' instead."
	fi
	page_title=$(echo "$page_title" | tr -d '[]')
	local markdown_link="- [$page_title]($url)"
	echo "$markdown_link" >>"$VIDEO_FILE"
	notify-send "✅ Link Added" "$page_title"
}

# Function to edit the title of an existing link
edit_link_title() {
	local old_title="$1"
	local url="$2"
	local new_title
	new_title=$(rofi -dmenu -p "Edit Title" -mesg "$url" -insert "$old_title")

	if [[ -n "$new_title" ]]; then
		local escaped_url
		escaped_url=$(printf '%s\n' "$url" | sed 's/[&/\]/\\&/g')
		sed -i "/(${escaped_url})/s/\[.*\]/\[${new_title}\]/" "$VIDEO_FILE"
		notify-send "✅ Title Updated" "'$new_title'"
	fi
}

# --- CORRECTED FUNCTION ---
# This function handles deleting a link, with confirmation
delete_link() {
	local title="$1"
	local url="$2"

	# Ask for confirmation using a Rofi prompt
	local confirmation
	confirmation=$(printf "No\nYes" | rofi -dmenu -p "Delete this link?" -mesg "$title")

	# If the user confirmed, proceed with deletion
	if [[ "$confirmation" == "Yes" ]]; then
		# To make deletion robust, we will find the line containing the unique URL
		# and delete it, rather than trying to match the whole complex string.

		# First, we need to escape special characters in the URL (like '/') for sed
		local escaped_url
		escaped_url=$(printf '%s\n' "$url" | sed 's/[&/\]/\\&/g')

		# Now use sed to find any line containing the unique "($escaped_url)" string and delete it.
		# The '-i' flag edits the file in-place. This is much more reliable.
		sed -i "/(${escaped_url})/d" "$VIDEO_FILE"

		notify-send "🗑️ Link Deleted" "$title"
	fi
}

# MAIN interactive loop

last_index=0

while true; do
	mapfile -t LINES < <(build_rofi_input)

	if [[ ${#LINES[@]} -eq 0 ]]; then
		if [[ "$(rofi -dmenu -p 'No links found. Add a new one?' -lines 2 <<<$'Yes\nNo')" == "Yes" ]]; then
			ret=13
		else
			break
		fi
	else
		mapfile -t TITLES < <(printf "%s\n" "${LINES[@]}" | sed 's/|\([^|]*\)$//')
		selection=$(printf "%s\n" "${TITLES[@]}" |
			rofi -dmenu -markup-rows \
				-theme "$ROFI_THEME" \
				-p "Links" \
				-selected-row "$last_index" \
				-kb-custom-1 "Alt+o" \
				-kb-custom-2 "Alt+y" \
				-kb-custom-3 "Alt+s" \
				-kb-custom-4 "Alt+a" \
				-kb-custom-5 "Alt+e" \
				-kb-custom-6 "Alt+d")
		ret=$?
	fi

	# --- HANDLE ROFI ACTIONS ---

	if [[ $ret -eq 1 ]]; then
		pkill -f "feh --title link-preview" 2>/dev/null
		break
	fi

	index=-1
	if [[ -n "$selection" ]]; then
		for i in "${!TITLES[@]}"; do
			if [[ "${TITLES[$i]}" == "$selection" ]]; then
				index="$i"
				break
			fi
		done
	fi

	if [[ $index -lt 0 && $ret -ne 13 ]]; then
		continue
	fi

	if [[ $index -ge 0 ]]; then
		full_line="${LINES[$index]}"
		title=$(echo "$full_line" | sed 's/|\([^|]*\)$//')
		url=$(echo "$full_line" | sed -n 's/.*|\(.*\)/\1/p')
		last_index=$index
	fi

	case $ret in
	0 | 10) # Open
		[[ -n "$url" ]] && $BROWSER "$url" &
		pkill -f "feh --title link-preview" 2>/dev/null
		break
		;;
	11) # Copy
		copy_to_clipboard "$url"
		notify-send "📋 Copied URL" "$title"
		;;
	12) # Preview
		show_preview "$url"
		;;
	13) # Add New Link (from Alt+a)
		new_url=$(rofi -dmenu -p "Enter URL to Add")
		if [[ -n "$new_url" ]]; then
			add_new_link "$new_url"
			last_index=0
		fi
		;;
	14) # Edit Title (from Alt+e)
		edit_link_title "$title" "$url"
		;;
	15) # Delete Link (from Alt+d)
		delete_link "$title" "$url"
		last_index=0
		;;
	esac
done
