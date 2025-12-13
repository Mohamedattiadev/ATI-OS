#!/bin/bash

chosen=$(echo -e "100\n80\n60\n40\n20\n10" | rofi -dmenu -p "Set Brightness to %")

if [[ -n $chosen ]]; then
	xbacklight -set "$chosen"
fi
