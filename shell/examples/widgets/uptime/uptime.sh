#!/bin/sh
# An "Exec" widget: the first line of stdout is what the bar shows. Runs every `interval` seconds from widget.json, in this
# folder (which is first on PATH, so widget.json can name the script without a path).
s=$(cut -d. -f1 /proc/uptime)
d=$((s / 86400)); h=$((s % 86400 / 3600)); m=$((s % 3600 / 60))
if [ "$d" -gt 0 ]; then echo "${d}d ${h}h"; else echo "${h}h ${m}m"; fi
