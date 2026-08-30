#!/usr/bin/env bash
# ============================================================
#  qs-reload-guard — make Quickshell's hot reload actually land.
#
#  THE BUG THIS EXISTS FOR
#  -----------------------
#  Quickshell watches its config and reloads on change, so an edit to the
#  topbar shows up without restarting anything. That is true right up until
#  two files are written close together, and then it silently is not.
#
#  Caught on 2026-08-30, from the topbar's own instance log:
#
#      03:00:04.302  INFO: Reloading configuration...
#      03:00:04.372                                    <- BarTheme.qml written
#      03:00:06.692  INFO: Configuration Loaded
#      (nothing for the next twelve hours)
#
#  The reload began 70 ms BEFORE the second file of the batch was written.
#  Quickshell fired on the first file's event, read the tree as it stood
#  mid-write, and the events that arrived while that reload was in flight
#  were dropped rather than queued. It then sat there for twelve hours
#  serving QML that no file on disk matched.
#
#  There is no error for this. `log.log` says "Configuration Loaded" and
#  means it — it loaded, just not what you wrote. The symptom is that a
#  feature plainly present in the file is simply absent from the bar. The
#  reported version of it was "the systray thing disappeared": the tray
#  section had been added at 03:03 and the running process had never once
#  had it compiled in. Diagnosed by comparing the LIVE IPC surface against
#  the file — `qs ipc --pid <pid> show` did not list the `toggleSystemTray`
#  that file plainly defines, which is the cheapest staleness test there is.
#
#  WHY A `touch` IS THE WHOLE FIX
#  ------------------------------
#  Quickshell does not reload because a file event arrived; it reloads
#  because the tree HASHES DIFFERENTLY from what it currently has loaded. An
#  event is only the prompt to go and re-check. Measured here, on a config
#  rigged to take ~2 s to compile:
#
#      instance already current, `touch`            -> no reload at all
#      instance already current, rewrite same bytes -> no reload at all
#      instance STALE (mid-reload write dropped)    -> `touch` RELOADS it
#
#  So `touch` is not "force a reload", it is "go and re-check against disk",
#  and it costs one utimensat when there is nothing wrong. That is what makes
#  this guard safe to run on a timer: it cannot cause a spurious reload, it
#  can only end one that should never have been happening.
#
#  WHY NOT A GIT HOOK
#  ------------------
#  The obvious fix — post-merge/post-checkout hooks touching the QML — was
#  the first thing considered and it is the wrong shape. The write that lost
#  the tray was an EDITOR batch, not a git operation; a hook would not have
#  fired at all. Git checkout, `stow`, an editor writing four files, and a
#  merge into `test` are four different write paths into the same directory
#  and only one of them is git's. So the guard watches the DIRECTORY, which
#  is the one thing all four have in common.
#
#  TWO LAYERS, BECAUSE THE FAST ONE CAN STILL BE MISSED
#  ----------------------------------------------------
#  1. EVENTS, debounced. Writes accumulate and nothing is re-checked until
#     the tree has been quiet for $DEBOUNCE. Firing per-event would recreate
#     the original bug from the other side, since re-checking mid-batch is
#     precisely what went wrong. A batch of any size collapses into one
#     re-check after its last file lands. Typical heal time: ~1 s.
#
#  2. A HEARTBEAT, every $HEARTBEAT seconds. Layer 1 still assumes inotify
#     delivered the event at all — not true across an overflowed queue, a
#     subdirectory created after the watch was set up, or a tree swapped out
#     from under the watch by `stow -D`. The heartbeat assumes nothing: it
#     re-checks on a timer whether anything happened or not. Because a
#     re-check on a current instance does nothing, this is close to free, and
#     it is what makes the fix hold for cases nobody has thought of yet.
#
#  It does mean the entry file's mtime moves every $HEARTBEAT, so git's
#  stat cache re-hashes it on the next `git status`. For a 188 KB file that
#  is not worth optimising away.
# ============================================================
set -euo pipefail

# Overridable so this can be pointed at a throwaway config tree and tested
# without touching the running session. That is how it was verified.
WATCH_ROOT="${QS_RELOAD_GUARD_ROOT:-$HOME/.config/quickshell}"
DEBOUNCE="${QS_RELOAD_GUARD_DEBOUNCE:-1.0}"
HEARTBEAT="${QS_RELOAD_GUARD_HEARTBEAT:-60}"   # 0 disables layer 2

log() { printf 'qs-reload-guard: %s\n' "$*" >&2; }

command -v inotifywait >/dev/null 2>&1 || {
  log "inotify-tools is not installed — nothing to watch with"; exit 1; }
[[ -d "$WATCH_ROOT" ]] || { log "no config tree at $WATCH_ROOT"; exit 1; }

# Resolved before watching. ~/.config/quickshell is a symlink into ~/.dotfiles,
# and inotify watches INODES — the paths reported back have to be comparable
# with the ones `ps` reports, which are whatever argv happened to say.
WATCH_ROOT=$(realpath -- "$WATCH_ROOT")

# One guard per session. Same reasoning as topbar.sh's entry_running: this is
# reachable from autostart AND by hand, and two guards would re-check the same
# entry twice for every batch.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/qs-reload-guard.lock"
exec 9>"$LOCK"
flock -n 9 || { log "another guard already holds $LOCK — not starting a second"; exit 0; }

# ---------------------------------------------------------------------------
#  Which Quickshell instances are up, and what each one's entry file is
# ---------------------------------------------------------------------------
# The `-p` argv walk is topbar.sh's, for the reason its header gives: `pgrep
# -f` would match this script's own command line, and a substring cannot tell
# `-p <dir>` from `-p <dir>/popups.qml`.
#
# The `ipc`/`log`/`list`/`kill` exclusion is not paranoia — `qs ipc -p <path>
# call ...` is a real command this desktop runs on keybinds and it carries a
# `-p` too. Treating one of those as a running bar would mean re-checking an
# entry on behalf of a process that exited milliseconds ago.
qs_instances() {
  ps -eo pid=,args= | awk '
    /awk/ { next }
    {
      cmd = $2; sub(/.*\//, "", cmd)
      if (cmd != "quickshell" && cmd != "qs") next
      for (i = 2; i <= NF; i++)
        if ($i == "ipc" || $i == "log" || $i == "list" || $i == "kill") next
      for (i = 2; i < NF; i++)
        if ($i == "-p" || $i == "--path") { print $1 "\t" $(i + 1); next }
    }'
}

# Quickshell resolves `-p <dir>` to <dir>/shell.qml and `-p <file>` to the file
# itself; the guard has to reproduce that to know what to re-check.
entry_for() { if [[ -d "$1" ]]; then printf '%s\n' "$1/shell.qml"; else printf '%s\n' "$1"; fi; }
root_for()  { if [[ -d "$1" ]]; then printf '%s\n' "$1"; else dirname -- "$1"; fi; }
realish()   { realpath -m -- "$1" 2>/dev/null || printf '%s\n' "$1"; }

# Ask one instance to re-check itself against disk. Reloads iff it is stale;
# see the header. Reported only when it actually did something, so a quiet log
# means a session that never went stale.
recheck() {
  local pid="$1" entry="$2" logfile before after
  logfile="/run/user/$(id -u)/quickshell/by-pid/$pid/log.log"
  [[ -f "$entry" ]] || return 0

  before=$(stat -c %Y "$logfile" 2>/dev/null || echo 0)
  touch -c -- "$entry" 2>/dev/null || return 0
  sleep 2
  after=$(stat -c %Y "$logfile" 2>/dev/null || echo 0)
  [[ "$after" != "$before" ]] && log "pid $pid was stale — reloaded $(basename -- "$entry")"
  return 0
}

# The ENTRY is what gets re-checked, not the file that changed: a component
# like BarTheme.qml is not an entry point and Quickshell hashes the tree from
# the entry down. Touching the entry is what makes the whole tree re-read.
#
# With no arguments, re-check every instance under $WATCH_ROOT — that is the
# heartbeat. With arguments, only instances whose config root contains one of
# the named files.
recheck_instances() {
  local -a changed=("$@")
  local pid path root entry c
  while IFS=$'\t' read -r pid path; do
    [[ -n "${path:-}" ]] || continue
    root=$(realish "$(root_for "$path")")
    entry=$(entry_for "$path")
    if (( ${#changed[@]} == 0 )); then
      [[ "$root" == "$WATCH_ROOT" || "$root" == "$WATCH_ROOT"/* ]] && recheck "$pid" "$entry"
    else
      for c in "${changed[@]}"; do
        if [[ "$(realish "$c")" == "$root"/* ]]; then recheck "$pid" "$entry"; break; fi
      done
    fi
  done < <(qs_instances)
}

# Only files Quickshell actually compiles. Without this filter an editor
# swapfile or a `.git` index write inside the tree would wake the guard for
# nothing. Anything this misses is still caught by the heartbeat.
interesting() {
  case "$1" in
    *.qml|*.js|*.mjs|*/qmldir) return 0 ;;
    *) return 1 ;;
  esac
}

log "watching $WATCH_ROOT (debounce ${DEBOUNCE}s, heartbeat ${HEARTBEAT}s)"

# The outer loop is for inotifywait dying — an OOM kill, or a `stow -D` taking
# the directory out from under it. A guard that quietly stops guarding is the
# same class of failure as the bug it was written for.
while true; do
  exec 3< <(inotifywait -m -r -q \
              -e close_write -e moved_to -e move_self -e create -e delete \
              --format '%w%f' "$WATCH_ROOT" 2>/dev/null)

  pending=()
  while true; do
    rc=0
    if (( ${#pending[@]} == 0 )); then
      # Idle. Wake on the heartbeat, or immediately when something is written.
      if [[ "$HEARTBEAT" == 0 ]]; then
        IFS= read -r line <&3 || rc=$?
      else
        IFS= read -r -t "$HEARTBEAT" line <&3 || rc=$?
      fi
    else
      # A batch is open: any gap of $DEBOUNCE closes it.
      IFS= read -r -t "$DEBOUNCE" line <&3 || rc=$?
    fi

    if (( rc == 0 )); then
      interesting "$line" && pending+=("$line")
    elif (( rc > 128 )); then
      # `read -t` returns >128 only on timeout. Either a batch just went
      # quiet, or nothing has happened for a whole heartbeat.
      if (( ${#pending[@]} )); then
        recheck_instances "${pending[@]}"
        pending=()
      else
        recheck_instances
      fi
    else
      break   # EOF: inotifywait is gone.
    fi
  done

  exec 3<&-
  log "inotifywait exited — restarting in 2s"
  sleep 2
done
