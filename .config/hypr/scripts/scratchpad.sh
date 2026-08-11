#!/usr/bin/env bash
# ============================================================
#  Scratchpad toggle — the spawn-on-first-use half of qtile's DropDown.
#
#  qtile's DropDown("term1", "kitty", ...) did two jobs: it spawned the
#  client the first time you hit the key, and toggled visibility every
#  time after.  Hyprland's `togglespecialworkspace` only does the second
#  — on an empty special workspace it happily shows you nothing, which
#  is why binding it directly does not reproduce the old behaviour.
#
#  This restores the first job: if the named special workspace has no
#  clients, spawn the command into it; otherwise just toggle.
#
#  Usage:  scratchpad.sh <name> <command...>
# ============================================================
set -euo pipefail

name="${1:?usage: scratchpad.sh <name> <command...>}"
shift
cmd="$*"

# `hyprctl clients -j` lists every client with its workspace; count the
# ones sitting in special:<name>.  jq is the only hard dependency here.
count=$(hyprctl clients -j | jq --arg ws "special:$name" '[.[] | select(.workspace.name == $ws)] | length')

if [ "$count" -eq 0 ]; then
    # Spawn into the special workspace directly, so the window never
    # flashes on the current one first.
    hyprctl dispatch exec "[workspace special:$name silent] $cmd"
    # Then reveal it.  The client needs a moment to map before the
    # toggle registers it; without this the first press appears to do
    # nothing and the second one hides an already-hidden workspace.
    sleep 0.35
fi

hyprctl dispatch togglespecialworkspace "$name"
