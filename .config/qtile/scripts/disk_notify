#!/bin/bash

total=$(df -h / | awk "NR==2 {print \"💽  TOTAL: \" \$2 \"\n       USED: \" \$3 \"\n       FREE: \" \$4\"\"}")
notify-send -u normal -i drive-harddisk -a success -t 0 "" "💾 DISK USAGE

$total"
