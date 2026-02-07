#NOTE: will be modified again later

##!/usr/bin/env bash
#
#WATCH_DIR="$HOME/.config/rofi/Todo_files"
#
#inotifywait -m -e close_write,create,moved_to "$WATCH_DIR" |
#	while read -r directory events filename; do
#		if [[ "$filename" == todos.sync-conflict*.md ]] || [[ "$filename" == Shared_Links.sync-conflict*.md ]]; then
#			echo "📦 Conflict file detected: $filename"
#			bash ~/.config/qtile/scripts/sync_todo_conflict_resolver.sh
#		fi
#	done
