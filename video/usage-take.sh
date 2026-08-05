#!/usr/bin/env bash
set -u
N=:9
k(){ DISPLAY=$N xdotool key --clearmodifiers "$@"; }
t(){ DISPLAY=$N xdotool type --clearmodifiers --delay 55 "$1"; }
m(){ DISPLAY=$N xdotool mousemove "$1" "$2"; }
c(){ DISPLAY=$N xdotool click "$1"; }
s(){ sleep "$1"; }
s 0.9
t "ls Projects"; s 0.3; k Return; s 1.5
t "cat Projects/config.json"; s 0.3; k Return; s 1.9
k super+3; s 2.4
m 1180 430; s 0.4
for _ in 1 2 3 4 5 6 7 8; do c 5; s 0.16; done
s 1.4
k super+Tab; s 1.8
k super+Tab; s 1.8
k super+Tab; s 1.6
m 226 317; s 0.4; c 1; s 1.2
k alt+shift+d; s 2.6
k alt+shift+d; s 1.6
k super+p; s 0.8
k c; s 2.2
for _ in 1 2 3 4; do k Down; s 0.45; done
s 0.9
k Escape; s 1.4
k super+4; s 2.0
