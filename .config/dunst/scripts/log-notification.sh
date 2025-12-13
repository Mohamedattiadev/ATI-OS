#!/bin/bash

# Save body content for later
mkdir -p /tmp/dunst-bodies
id=$(date +%s%N)
echo "$DUNST_BODY" >"/tmp/dunst-bodies/$id"

# Output a clickable action string with the ID
echo "action=copy:$id"
