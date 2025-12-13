#!/usr/bin/env bash

copy() {
	if command -v xclip &>/dev/null; then
		printf "%s" "$1" | xclip -selection clipboard
	elif command -v xsel &>/dev/null; then
		printf "%s" "$1" | xsel --clipboard
	elif command -v wl-copy &>/dev/null; then
		printf "%s" "$1" | wl-copy
	else
		notify-send "auto-copy" "No clipboard tool found"
		exit 1
	fi
}

rm -f /tmp/notif-copy-debug.log /tmp/notif-raw.log

dbus-monitor "interface='org.freedesktop.Notifications'" |
	awk -v shell_copy="'"$(realpath "$0")"'" '
function trim(str) {
  gsub(/^[ \t\r\n]+/, "", str)
  return str
}

BEGIN {
  in_notify = 0
  str_count = 0
  strings_seen = 0
}

/.*/ {
  print $0 >> "/tmp/notif-raw.log"
}

/method call.*Notify/ {
  in_notify = 1
  strings_seen = 0
  summary = ""
  body = ""
}

/string/ && in_notify {
  strings_seen++
  match($0, /string "(.*)"/, m)
  value = trim(m[1])

  # Adjusted index:
  # 1 = app_name
  # 2 = app_icon
  # 3 = summary
  # 4 = body
  if (strings_seen == 3) summary = value
  else if (strings_seen == 4) body = value

  if (strings_seen >= 4) {
    in_notify = 0

    print "DEBUG: [" summary "] [" body "]" >> "/tmp/notif-copy-debug.log"

    # Skip "Saved Screenshot\nClipboard"
    if (summary == "Saved Screenshot" && body == "Clipboard")
      next

    message = summary "\n" body
    gsub(/"/, "\\\"", message)
    system("bash -c \"" shell_copy " copy \\\"" message "\\\"\"")
  }
}
'

# If script is called as: ./notif-copy.sh copy "text"
if [[ "$1" == "copy" ]]; then
	shift
	copy "$*"
	exit
fi
