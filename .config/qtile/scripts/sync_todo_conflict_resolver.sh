#!/usr/bin/env bash

TODO_DIR="$HOME/.config/rofi/Todo_files"

FILES=("todos.md" "Shared_Links.md")

for FILE in "${FILES[@]}"; do
	MAIN_FILE="$TODO_DIR/$FILE"

	# Find first conflict file for this main file
	CONFLICT_FILE=$(find "$TODO_DIR" -name "${FILE%.md}.sync-conflict*.md" | head -n 1)

	if [[ -n "$CONFLICT_FILE" ]]; then
		echo "⚠️ Conflict file found for $FILE: $CONFLICT_FILE"
		echo "📋 Replacing $MAIN_FILE with contents of conflict..."

		cp "$CONFLICT_FILE" "$MAIN_FILE" && rm "$CONFLICT_FILE"

		echo "✅ Overwritten $FILE and deleted conflict."
	else
		echo "✅ No conflict file found for $FILE."
	fi
done
