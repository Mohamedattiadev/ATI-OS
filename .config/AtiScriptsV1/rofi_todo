#!/usr/bin/env bash
#!/usr/bin/env bash

# CONFIGURATION
# -----------------------------------------------------------------------------
TODO_FILE="$HOME/.config/rofi/Todo_files/todos.md"
SUBTASK_FILE="$HOME/.config/rofi/Todo_files/subtasks.md"
WORKING_FILE="$HOME/.config/rofi/Todo_files/working_on.txt"
mkdir -p "$(dirname "$TODO_FILE")"
touch "$TODO_FILE" "$SUBTASK_FILE" "$WORKING_FILE"

# Ensure each task file ends with a newline (prevents merging lines)
for f in "$TODO_FILE" "$SUBTASK_FILE" "$WORKING_FILE"; do
	[ -s "$f" ] && tail -c1 "$f" | read -r _ || echo >>"$f"
done
# SED command for macOS/Linux
SED_COMMAND="sed -i"
if [[ "$(uname)" == "Darwin" ]]; then
	SED_COMMAND="sed -i ''"
fi

# AWK command - GNU Awk (gawk) is recommended.
AWK_COMMAND="gawk"

# COLORS
# -----------------------------------------------------------------------------
HEADER_COLOR="#61afef"

# ICONS (Nerd Font)
# -----------------------------------------------------------------------------
ICON_TODO="󰄱" # checkbox_blank_outline
ICON_DONE="󰄲" # checkbox_marked
ICON_ADD=""  # plus_circle
ICON_DEL="󰆴"
ICON_EDIT="" # pencil
ICON_WORKING="󰡠"
ICON_DUE="󰥔"
SMALL_DUE_ICON="󰄉"
ICON_YANK="󰅍"
ICON_SUBTASK="  └─"
ICON_DONE_TODAY="󰄲" # check_circle_outline
# SESSIONS
# -----------------------------------------------------------------------------
SESSIONS=("Today's Todos" "Future Tasks" "General Tasks" "Done Tasks")
SESSION_TODAY=0
SESSION_FUTURE=1
SESSION_GENERAL=2
SESSION_DONE=3
current_session_index=$SESSION_TODAY

# SED command for macOS/Linux
# -----------------------------------------------------------------------------
SED_COMMAND="sed -i"
if [[ "$(uname)" == "Darwin" ]]; then
	SED_COMMAND="sed -i ''"
fi

# AWK command - GNU Awk (gawk) is recommended.
AWK_COMMAND="gawk"

# COLORS
# -----------------------------------------------------------------------------
HEADER_COLOR="#61afef"

# SESSIONS
# -----------------------------------------------------------------------------
# FORMAT FUNCTION (EXCLUDES SUBTASKS FROM DONE SECTIONS)
# -----------------------------------------------------------------------------

# -------------------- RANDOM COLOR FUNCTION -----------------------

get_session_content() {
	local session_index="$1"

	local working_list
	working_list=" $(paste -sd' ' "$WORKING_FILE") "

	local all_formatted_lines
	all_formatted_lines=$(
		$AWK_COMMAND -v session="$session_index" \
			-v today="$(date "+%Y-%m-%d")" \
			-v working_list="$working_list" \
			-v ICON_TODO="$ICON_TODO" \
			-v ICON_DONE="$ICON_DONE" \
			-v ICON_WORKING="$ICON_WORKING" \
			-v ICON_DONE_TODAY="$ICON_DONE_TODAY" \
			-v SMALL_DUE_ICON="$SMALL_DUE_ICON" \
			-v ICON_SUBTASK="$ICON_SUBTASK" '
	BEGIN { FS = "|" }

	
# deterministic ord() function
function ord(c) {
    return sprintf("%d", strtonum("0x" sprintf("%02x", index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", c)-1 + 65)))
}

# deterministic color from tag
function tag_color(tag,   char_code, r, g, b) {
    char_code = ord(substr(tag,1,1))
    r = (char_code * 53) % 256
    g = (char_code * 97) % 256
    b = (char_code * 193) % 256
    return sprintf("#%02X%02X%02X", r, g, b)
}


	{
		line_num = $1
		line_text = $2
		is_subtask = match(line_text, /^[[:space:]]+- \[[ x]\]/)
		if (!match(line_text, /^[-] \[[ x]\]/)) next
		sub(/^[[:space:]]+/, "", line_text)

		prio_num = 0; prio_mark = ""
		if (match(line_text, /@Prio\((high|normal|low)\)/, m)) {
			prio_tag = m[1]
			if (prio_tag == "high")   { prio_num = 3; prio_mark = "<span color=\"#ff5555\" size=\"80%\" weight=\"bold\">(high)</span> " }
			if (prio_tag == "normal") { prio_num = 2; prio_mark = "<span color=\"#f0c674\" size=\"80%\">(normal)</span> " }
			if (prio_tag == "low")    { prio_num = 1; prio_mark = "<span color=\"#8abeb7\" size=\"80%\">(low)</span> " }
		}

		color_start = ""; color_end = ""
		if (match(line_text, /@Color\(([^)]+)\)/, c)) {
			color_val = c[1]
			color_start = "<span color=\"" color_val "\">"
			color_end = "</span>"
		}

		task_text = line_text
		sub(/^- \[[x ]\] ?/, "", task_text)
		sub(/ ?@Prio\((high|normal|low)\) ?/, "", task_text)
		sub(/ ?@Color\([^)]+\) ?/, "", task_text)

		# --- deterministic @Tag(...) processing ---
		tag_html = ""
		while (match(task_text, /@Tag\(([^)]+)\)/, tag_match)) {
			tag_name = tag_match[1]
			tag_html = tag_html "<span color=\"" tag_color(tag_name) "\">#" tag_name "</span> "
			task_text = substr(task_text, 1, RSTART-1) substr(task_text, RSTART+RLENGTH)
		}

		sub(/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$/, "", task_text)
		gsub(/&/, "&amp;", task_text)
		gsub(/</, "&lt;", task_text)
		gsub(/>/, "&gt;", task_text)

		is_done = (index(line_text, "[x]") > 0)
		match(line_text, /@[0-9]{4}-[0-9]{2}-[0-9]{2}/)
		task_date = substr(line_text, RSTART+1, RLENGTH-1)

		is_due_today = (task_date == today)
		is_done_today = (is_done && task_date == today)
		is_future = (!is_done && task_date > today)

		working_mark = ""
		if (index(working_list, " " line_num " ") > 0) {
			working_mark = "<span color=\"red\">" ICON_WORKING "</span> "
		}

		prefix = (is_subtask ? ICON_SUBTASK " " : "")

		if (is_done) {
			if (is_subtask) next
			if (is_done_today) {
				printf "done_today|%d|%d|%s<span color=\"#00d11f\">%s</span> <span alpha=\"80%%\"><s>%s%s%s%s%s</s></span>\n", prio_num, line_num, prefix, ICON_DONE_TODAY, prio_mark, tag_html, color_start, task_text, color_end
			} else {
				printf "done_all|%d|%d|%s%s<span color=\"green\">%s</span> <span alpha=\"80%%\"><s>%s%s%s%s%s</s></span>\n", prio_num, line_num, prefix, working_mark, ICON_DONE, prio_mark, tag_html, color_start, task_text, color_end
			}
		} else {
			if (is_due_today) {
				printf "today|%d|%d|%s%s<span color=\"#ffd700\">%s</span> %s%s%s%s%s\n", prio_num, line_num, prefix, working_mark, SMALL_DUE_ICON, prio_mark, tag_html, color_start, task_text, color_end
			} else if (is_future) {
				printf "future|%d|%d|%s%s<span color=\"orange\">%s</span> %s%s%s%s%s\n", prio_num, line_num, prefix, working_mark, ICON_TODO, prio_mark, tag_html, color_start, task_text, color_end
			} else {
				printf "general|%d|%d|%s%s<span color=\"orange\">%s</span> %s%s%s%s%s\n", prio_num, line_num, prefix, working_mark, ICON_TODO, prio_mark, tag_html, color_start, task_text, color_end
			}
		}
	}' < <(awk '{ print NR "|" $0 }' "$TODO_FILE")
	)

	if [[ "$session_index" == "$SESSION_TODAY" ]]; then
		echo -e "<b><span color='${HEADER_COLOR}'>${ICON_DUE}</span>  TODAY'S TODOS</b>\0meta\x1fnonselectable\x1ftrue"
		echo "$all_formatted_lines" | grep '^today|' | sort -t'|' -k2,2nr | cut -d'|' -f3-
	elif [[ "$session_index" == "$SESSION_FUTURE" ]]; then
		echo -e "<b><span color='${HEADER_COLOR}'>${ICON_DUE}</span>  FUTURE TASKS</b>\0meta\x1fnonselectable\x1ftrue"
		echo "$all_formatted_lines" | grep '^future|' | sort -t'|' -k2,2nr | cut -d'|' -f3-
	elif [[ "$session_index" == "$SESSION_GENERAL" ]]; then
		echo -e "<b><span color='${HEADER_COLOR}'>${ICON_TODO}</span>  GENERAL TASKS</b>\0meta\x1fnonselectable\x1ftrue"
		echo "$all_formatted_lines" | grep '^general|' | sort -t'|' -k2,2nr | cut -d'|' -f3-
	elif [[ "$session_index" == "$SESSION_DONE" ]]; then
		echo -e "<b><span color='${HEADER_COLOR}'>${ICON_DONE_TODAY}</span>  DONE TODAY</b>\0meta\x1fnonselectable\x1ftrue"
		echo "$all_formatted_lines" | grep '^done_today|' | sort -t'|' -k2,2nr | cut -d'|' -f3-
		echo -e "<b><span color='${HEADER_COLOR}'>${ICON_DONE}</span>  ALL DONE</b>\0meta\x1fnonselectable\x1ftrue"
		echo "$all_formatted_lines" | grep '^done_all|' | sort -t'|' -k2,2nr | cut -d'|' -f3-
	fi
}

update_parent_task_status() {
	local parent_line="$1"

	# Check all subtasks of this parent
	local total_subtasks
	local done_subtasks

	total_subtasks=$(grep -c "@Parent(${parent_line})" "$SUBTASK_FILE")
	done_subtasks=$(grep "@Parent(${parent_line})" "$SUBTASK_FILE" | grep -c "^\s*- \[x\]")

	if [[ $total_subtasks -gt 0 && $total_subtasks -eq $done_subtasks ]]; then
		# All subtasks done: mark parent task done
		local parent_task_line
		parent_task_line=$(sed "${parent_line}q;d" "$TODO_FILE")

		if [[ "$parent_task_line" == *"- [ ]"* ]]; then
			TASK_TEXT_WITH_PRIO=$(echo "$parent_task_line" | sed -E 's/^- \[[x ]\] ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//')
			new_timestamp=$(date "+@%Y-%m-%d %H:%M")
			NEW_LINE="- [x] ${TASK_TEXT_WITH_PRIO} ${new_timestamp}"
			${SED_COMMAND} "${parent_line}c${NEW_LINE}" "$TODO_FILE"
			${SED_COMMAND} "/^${parent_line}$/d" "$WORKING_FILE"
		fi
	else
		# Not all subtasks done: mark parent task not done if currently done
		local parent_task_line
		parent_task_line=$(sed "${parent_line}q;d" "$TODO_FILE")

		if [[ "$parent_task_line" == *"- [x]"* ]]; then
			${SED_COMMAND} "${parent_line}s/\[x\]/[ ]/" "$TODO_FILE"
		fi
	fi
}

# MAIN LOOP
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
while true; do
	SESSION_TITLE="${SESSIONS[$current_session_index]}"
	SESSION_ICON=""
	case "$current_session_index" in
	$SESSION_TODAY) SESSION_ICON="${ICON_DUE}" ;;
	$SESSION_FUTURE) SESSION_ICON="${ICON_DUE}" ;;
	$SESSION_GENERAL) SESSION_ICON="${ICON_TODO}" ;;
	$SESSION_DONE) SESSION_ICON="${ICON_DONE}" ;;
	esac

	SELECTION=$(get_session_content "$current_session_index" | rofi -theme ~/.config/rofi/themes/todo-large.rasi -dmenu \
		-p "<span color='${HEADER_COLOR}'>${SESSION_ICON}</span> ${SESSION_TITLE}" \
		-mesg "<b>Alt+a:</b> Add | <b>Alt+d:</b> Del | <b>Alt+e:</b> Edit | <b>Ctrl+y:</b> ${ICON_YANK} Yank | <b>Alt+h/l:</b> Session" \
		-markup-rows \
		-i \
		-kb-custom-1 "Alt+a" \
		-kb-custom-2 "Alt+d" \
		-kb-custom-3 "Alt+w" \
		-kb-custom-4 "Alt+e" \
		-kb-custom-5 "Alt+t" \
		-kb-custom-6 "Alt+p" \
		-kb-custom-7 "Alt+h" \
		-kb-custom-8 "Alt+l" \
		-kb-custom-9 "Alt+s" \
		-kb-custom-10 "Alt+u" \
		-kb-custom-11 "Control+y" \
		-format 's')
	EXIT_CODE=$?

	LINE_NUMBER=$(echo "$SELECTION" | cut -d'|' -f1 | xargs)

	if [[ -z "$LINE_NUMBER" ]]; then
		if [[ $EXIT_CODE -eq 1 ]]; then
			exit 0
		fi
		continue
	fi

	LINE_CONTENT=$(sed "${LINE_NUMBER}q;d" "$TODO_FILE")

	case $EXIT_CODE in
	0) # Toggle done
		if [[ "$LINE_CONTENT" == *"- [ ]"* ]]; then
			TASK_TEXT_WITH_PRIO=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//')
			new_timestamp=$(date "+@%Y-%m-%d %H:%M")
			NEW_LINE="- [x] ${TASK_TEXT_WITH_PRIO} ${new_timestamp}"
			${SED_COMMAND} "${LINE_NUMBER}c${NEW_LINE}" "$TODO_FILE"
			${SED_COMMAND} "/^${LINE_NUMBER}$/d" "$WORKING_FILE"
		elif [[ "$LINE_CONTENT" == *"- [x]"* ]]; then
			${SED_COMMAND} "${LINE_NUMBER}s/\[x\]/[ ]/" "$TODO_FILE"
		fi
		;;

	10) # MODIFIED: Add Task
		# Add Task section
		NEW_TODO=$(echo "" | rofi -theme ~/.config/rofi/themes/todo-large.rasi \
			-dmenu -p "${ICON_ADD} Add (-h|-n|-l)(-c color)(# tag)" -filter "")

		if [ -n "$NEW_TODO" ]; then
			TASK_TEXT="$NEW_TODO"
			PRIORITY="normal"
			COLOR_TAG=""

			# Extract color tag first
			if [[ "$TASK_TEXT" =~ -c[[:space:]]([^[:space:]]+) ]]; then
				color_val="${BASH_REMATCH[1]}"
				COLOR_TAG="@Color(${color_val})"
				TASK_TEXT=$(echo "$TASK_TEXT" | sed -E "s/-c[[:space:]]${color_val}[[:space:]]?//")
			fi

			# Extract priority tag from the remaining text
			if [[ "$TASK_TEXT" =~ ^-[hH] ]]; then
				PRIORITY="high"
				TASK_TEXT="${TASK_TEXT:2}"
			elif [[ "$TASK_TEXT" =~ ^-[nN] ]]; then
				PRIORITY="normal"
				TASK_TEXT="${TASK_TEXT:2}"
			elif [[ "$TASK_TEXT" =~ ^-[lL] ]]; then
				PRIORITY="low"
				TASK_TEXT="${TASK_TEXT:2}"
			fi

			TASK_TEXT=$(echo "$TASK_TEXT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

			# Convert #tags to @Tag(name)@Color(random) if COLOR_TAG not set
			TASK_TEXT=$(echo "$TASK_TEXT" | sed -E "s/#([a-zA-Z0-9_]+)/@Tag(\1)/g")

			timestamp=$(date "+@%Y-%m-%d %H:%M")

			# Assemble the final line
			FINAL_LINE="- [ ] @Prio(${PRIORITY}) ${COLOR_TAG} ${TASK_TEXT} ${timestamp}"
			FINAL_LINE=$(echo "$FINAL_LINE" | sed 's/  / /g') # Clean up double spaces

			# Append to file safely
			printf "%s\n" "$FINAL_LINE" >>"$TODO_FILE"
		fi
		;;
	11) # Delete
		${SED_COMMAND} "${LINE_NUMBER}d" "$TODO_FILE"
		${SED_COMMAND} "/^${LINE_NUMBER}$/d" "$WORKING_FILE"
		;;
	12) # Toggle Working On
		if grep -Fxq "$LINE_NUMBER" "$WORKING_FILE"; then
			${SED_COMMAND} "/^${LINE_NUMBER}$/d" "$WORKING_FILE"
		else
			echo "$LINE_NUMBER" >>"$WORKING_FILE"
		fi
		;;

	13) # Edit
		TASK_TEXT_WITH_PRIO=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//')
		CURRENT_TEXT_ONLY=$(echo "$TASK_TEXT_WITH_PRIO" | sed -E 's/ ?@Prio\((low|normal|high)\) ?//')

		OLD_PRIORITY_TAG=$(echo "$TASK_TEXT_WITH_PRIO" | grep -oE "@Prio\((low|normal|high)\)")

		EDIT_PROMPT_TEXT="${CURRENT_TEXT_ONLY}"
		EDITED_INPUT=$(rofi -dmenu -theme ~/.config/rofi/themes/todo-large.rasi \
			-p "${ICON_EDIT} Edit" \
			-mesg "Edit task (optional: -h, -n, -l to change priority)" \
			-filter "$EDIT_PROMPT_TEXT")

		if [ -n "$EDITED_INPUT" ]; then
			NEW_PRIORITY_TAG="$OLD_PRIORITY_TAG"
			EDITED_TEXT="$EDITED_INPUT"
			if [[ "$EDITED_INPUT" =~ ^-[hH][[:space:]]? ]]; then
				NEW_PRIORITY_TAG="@Prio(high)"
				EDITED_TEXT="${EDITED_INPUT:2}"
			elif [[ "$EDITED_INPUT" =~ ^-[nN][[:space:]]? ]]; then
				NEW_PRIORITY_TAG="@Prio(normal)"
				EDITED_TEXT="${EDITED_INPUT:2}"
			elif [[ "$EDITED_INPUT" =~ ^-[lL][[:space:]]? ]]; then
				NEW_PRIORITY_TAG="@Prio(low)"
				EDITED_TEXT="${EDITED_INPUT:2}"
			fi
			EDITED_TEXT=$(echo "$EDITED_TEXT" | sed 's/^[[:space:]]*//')
			TASK_STATE=$(echo "$LINE_CONTENT" | grep -oE "\[[x ]\]")
			NEW_TIMESTAMP=$(date "+@%Y-%m-%d %H:%M")
			NEW_LINE="- ${TASK_STATE} ${NEW_PRIORITY_TAG} ${EDITED_TEXT} ${NEW_TIMESTAMP}"
			NEW_LINE=$(echo "$NEW_LINE" | sed -E 's/ +/ /g; s/ $//')
			${SED_COMMAND} "${LINE_NUMBER}c${NEW_LINE}" "$TODO_FILE"
		fi
		;;
	14) # Change Date (Alt+t)
		NEW_DATE_CHOICE=$(echo -e "Today\nTomorrow\nNext Week\nCustom Date\n(remove)" | rofi -theme ~/.config/rofi/themes/todo-large.rasi -dmenu -p "Select a New Date")

		if [ -n "$NEW_DATE_CHOICE" ]; then
			NEW_DATE=""
			case "$NEW_DATE_CHOICE" in
			"Today") NEW_DATE=$(date "+%Y-%m-%d") ;;
			"Tomorrow") NEW_DATE=$(date --date="tomorrow" "+%Y-%m-%d") ;; # Corrected for BSD/macOS date
			"Next Week") NEW_DATE=$(date --date="+7 days" "+%Y-%m-%d") ;; # Corrected for BSD/macOS date
			"Custom Date")
				NEW_DATE=$(rofi -theme ~/.config/rofi/themes/todo-large.rasi -dmenu -p "Enter a custom date (YYYY-MM-DD)")
				if ! [[ "$NEW_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then NEW_DATE=""; fi
				;;
			"(remove)") NEW_DATE="" ;;
			*) continue ;;
			esac

			TASK_TEXT_WITH_PRIO=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//')
			TASK_STATE=$(echo "$LINE_CONTENT" | grep -oE "\[[x ]\]")
			TASK_TIME=$(echo "$LINE_CONTENT" | grep -oE "[0-9]{2}:[0-9]{2}")

			if [ -n "$NEW_DATE" ]; then
				NEW_LINE="- ${TASK_STATE} ${TASK_TEXT_WITH_PRIO} @${NEW_DATE} ${TASK_TIME}"
			else
				NEW_LINE="- ${TASK_STATE} ${TASK_TEXT_WITH_PRIO}"
			fi

			NEW_LINE=$(echo "$NEW_LINE" | sed -E 's/ +/ /g; s/ $//')
			${SED_COMMAND} "${LINE_NUMBER}c${NEW_LINE}" "$TODO_FILE"
		fi
		;;
	15) # Change Priority (Alt+p)
		NEW_PRIORITY=$(echo -e "high\nnormal\nlow" | rofi -theme ~/.config/rofi/themes/todo-large.rasi -dmenu -p "Change Priority")
		if [ -n "$NEW_PRIORITY" ]; then
			NEW_PRIORITY_TAG="@Prio(${NEW_PRIORITY})"
			TASK_TEXT=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ ?@Prio\((low|normal|high)\) ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//')
			TASK_STATE=$(echo "$LINE_CONTENT" | grep -oE "\[[x ]\]")
			OLD_TIMESTAMP=$(echo "$LINE_CONTENT" | grep -oE " @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$")

			NEW_LINE="- ${TASK_STATE} ${NEW_PRIORITY_TAG} ${TASK_TEXT}${OLD_TIMESTAMP}"
			NEW_LINE=$(echo "$NEW_LINE" | sed -E 's/ +/ /g; s/ $//')
			${SED_COMMAND} "${LINE_NUMBER}c${NEW_LINE}" "$TODO_FILE"
		fi
		;;
	16) # Go to previous session (Alt+h)
		current_session_index=$(((current_session_index - 1 + ${#SESSIONS[@]}) % ${#SESSIONS[@]}))
		continue
		;;
	17) # Go to next session (Alt+l)
		current_session_index=$(((current_session_index + 1) % ${#SESSIONS[@]}))
		continue
		;;

	18) # Add Subtask (Alt+s)
		PARENT_LINE=$(echo "$SELECTION" | cut -d'|' -f1 | xargs)
		SUBTASK_INPUT=$(rofi -theme ~/.config/rofi/themes/todo-large.rasi -dmenu -p "${ICON_ADD} Add Subtask")

		if [ -n "$SUBTASK_INPUT" ]; then
			# This no longer adds the redundant parent task name
			TIMESTAMP=$(date "+@%Y-%m-%d %H:%M")
			NEW_LINE="- [ ] ${SUBTASK_INPUT} @Parent(${PARENT_LINE}) ${TIMESTAMP}"
			echo "$NEW_LINE" >>"$SUBTASK_FILE"
		fi
		;;

	19) # View and toggle Subtasks (Alt+u)
		PARENT_LINE=$(echo "$SELECTION" | cut -d'|' -f1 | xargs)
		if [[ -z "$PARENT_LINE" ]]; then continue; fi

		# Get the clean parent task name for the Rofi title
		PARENT_TASK_TEXT=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ ?@Prio\((low|normal|high)\) ?//; s/ ?@Color\([^)]+\) ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//; s/^[ ]*//; s/[ ]*$//')

		while true; do
			# Read subtasks from file, prepending their line number
			mapfile -t SUBTASKS < <(nl -w1 -s'|' "$SUBTASK_FILE" | $AWK_COMMAND -v pline="$PARENT_LINE" -v icon_done="$ICON_DONE" -v icon_todo="$ICON_TODO" '
				BEGIN { FS = "|" }
				# Find subtasks for the selected parent
				$2 ~ "@Parent\\(" pline "\\)" {
					line_num_in_file = $1
					text = $2
					icon = (text ~ /^\s*- \[x\]/) ? icon_done : icon_todo
					
					# Clean the text for display, removing all tags and metadata
					sub(/^[-] \[[x ]\] ?/, "", text);
					sub(/ ?@Prio\([^)]+\) ?/, "", text);
					sub(/ ?@Color\([^)]+\) ?/, "", text);
					sub(/ ?@Parent\([^)]+\) ?/, "", text);
					sub(/ @.*/, "", text); # Aggressively clean up old, malformed tags like "@MainTaskName @date"
					gsub(/^[[:space:]]*|[[:space:]]*$/, "", text);
					
					# Escape special characters for Pango markup
					gsub(/&/, "&amp;", text); gsub(/</, "&lt;", text); gsub(/>/, "&gt;", text);
					
					# Final format: "line_number|icon Formatted Text"
					printf "%s|%s %s\n", line_num_in_file, icon, text
				}
			')

			if [ ${#SUBTASKS[@]} -eq 0 ]; then
				rofi -e "No subtasks found"
				break
			fi

			# Show the subtask menu. Note the new keybinding and message.
			SELECTED_INDEX=$(printf '%s\n' "${SUBTASKS[@]}" | cut -d'|' -f2- | rofi -theme ~/.config/rofi/themes/todo-large.rasi \
				-dmenu -markup-rows \
				-p "Subtasks for: ${PARENT_TASK_TEXT}" \
				-mesg "<b>Enter:</b> Toggle Done | <b>Ctrl+y:</b> Yank" \
				-format 'i' \
				-kb-custom-1 "Control+y")
			SUB_EXIT_CODE=$?

			# Exit subtask menu if Esc is pressed
			if [[ $SUB_EXIT_CODE -eq 1 ]]; then break; fi
			# Loop again if nothing was selected
			if [[ ! "$SELECTED_INDEX" =~ ^[0-9]+$ ]]; then continue; fi

			# Get the subtask's line number from our array
			SUBTASK_LINE_DATA="${SUBTASKS[$SELECTED_INDEX]}"
			SUBTASK_LINE_NUM=$(echo "$SUBTASK_LINE_DATA" | cut -d'|' -f1)
			if [[ -z "$SUBTASK_LINE_NUM" ]]; then continue; fi

			case $SUB_EXIT_CODE in
			0) # Toggle Done (Enter)
				CUR_LINE=$(sed "${SUBTASK_LINE_NUM}q;d" "$SUBTASK_FILE")
				if [[ "$CUR_LINE" =~ ^-.\[x\].* ]]; then
					NEW_LINE=$(echo "$CUR_LINE" | sed 's/\[x\]/[ ]/')
				else
					NEW_LINE=$(echo "$CUR_LINE" | sed 's/\[ \]/[x]/')
				fi
				${SED_COMMAND} "${SUBTASK_LINE_NUM}s/.*/${NEW_LINE}/" "$SUBTASK_FILE"
				update_parent_task_status "$PARENT_LINE"
				;;
			10) # Yank Subtask (Ctrl+y)
				SUBTASK_CONTENT=$(sed "${SUBTASK_LINE_NUM}q;d" "$SUBTASK_FILE")
				# Extract clean text for clipboard
				SUBTASK_TEXT_ONLY=$(echo "$SUBTASK_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ ?@Prio\(([^)]+)\) ?//; s/ ?@Color\(([^)]+)\) ?//; s/ ?@Parent\(([^)]+)\) ?//; s/ @.*//; s/^[ ]*//; s/[ ]*$//')
				echo -n "$SUBTASK_TEXT_ONLY" | xclip -selection clipboard
				;;
			esac
			# Loop to refresh the subtask list
		done
		;;
	20) # NEW: Yank Task to Clipboard (Ctrl+y)
		TASK_TEXT_ONLY=$(echo "$LINE_CONTENT" | sed -E 's/^- \[[x ]\] ?//; s/ ?@Prio\((low|normal|high)\) ?//; s/ ?@Color\([^)]+\) ?//; s/ @[0-9]{4}-[0-9]{2}-[0-9]{2}( [0-9]{2}:[0-9]{2})?$//; s/^[ ]*//; s/[ ]*$//')
		echo -n "$TASK_TEXT_ONLY" | xclip -selection clipboard
		continue # Re-show the list
		;;
	1 | *) # Escape or unexpected exit code
		exit 0
		;;
	esac
done
