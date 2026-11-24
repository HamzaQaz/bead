#!/bin/sh
# The README's screenshots: stages each part of bead through its IPC on an
# empty workspace (so none of your windows are in them) and captures it.
#
#   tools/screenshots.sh [OUT_DIR]      (default: docs/screenshots)
#
# Needs a running bead, grim and jq (with magick, they're saved as WebP).
# Demo mode is on while it runs (no username, no Discord), and it leaves out
# what would show your own things (clipboard history, the overview's window
# thumbnails, notifications). Look through them before you publish anyway:
# what's playing shows on the dashboard, and your wallpaper is in every shot.
set -eu
out=${1:-docs/screenshots}
share=${XDG_DATA_HOME:-$HOME/.local/share}/bead
ipc() { qs -p "$share" ipc call "$@" >/dev/null 2>&1 || true; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }

[ "$(qs -p "$share" ipc call toast ping 2>/dev/null)" = pong ] || { echo "bead isn't running" >&2; exit 1; }
mkdir -p "$out"

# the island's monitor (bead's home screen): the first one, unless set
mon=$(jq -r '.islandScreen // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/bead/settings.json" 2>/dev/null || true)
[ -n "$mon" ] || mon=$(hyprctl monitors -j | jq -r 'sort_by(.id) | .[0].name')
read -r mx my mw mh <<EOF
$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | "\(.x) \(.y) \(.width / .scale | floor) \(.height / .scale | floor)"')
EOF

# an empty workspace to stage on, then back to where you were
was=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
used=$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id')
ws=
for i in 9 8 7 6 10 11 12; do echo "$used" | grep -qx "$i" || { ws=$i; break; }; done
[ -n "$ws" ] || { echo "no empty workspace to stage on" >&2; exit 1; }
dispatch "hl.dsp.focus({ monitor = \"$mon\" })"
dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
ipc demo on # your name and Discord stay out of them
trap 'ipc demo off; ipc launcher close; ipc dashboard close; ipc welcome close; ipc voice cancel; dispatch "hl.dsp.focus({ workspace = \"$was\" })"' EXIT

shot() { # NAME X Y W H (relative to the monitor; whole monitor when left out)
	f="$out/$1.png"
	# only ever the empty workspace: if you switched away meanwhile, stop
	now=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
	if [ "$now" != "$ws" ] || [ "$(hyprctl workspaces -j | jq -r --arg w "$ws" '.[] | select(.name == $w) | .windows')" != 0 ]; then
		echo "the workspace changed mid-way (to $now): stopped, nothing more captured; run it again without touching anything for ~25 s" >&2
		rm -f "$f"
		exit 1
	fi
	if [ $# -gt 1 ]; then grim -g "$((mx + $2)),$((my + $3)) ${4}x${5}" "$f"; else grim -o "$mon" "$f"; fi
	# WebP when magick is there (near-lossless: smaller, and no banding in
	# the dark gradients that lossy WebP shows), which GitHub displays
	if command -v magick >/dev/null; then magick "$f" -strip -quality 100 -define webp:near-lossless=60 "${f%.png}.webp" && rm "$f" && f=${f%.png}.webp; fi
	echo "$f"
}
cx=$((mw / 2))

# start from nothing open
ipc dashboard close; ipc launcher close; ipc notifs close
sleep 0.8
shot desktop

ipc launcher search "term"
sleep 0.9
shot launcher $((cx - 450)) 0 900 520
ipc launcher close

ipc launcher search "5 usd to eur"
sleep 1.2
shot launcher-maths $((cx - 450)) 0 900 260
ipc launcher close
sleep 0.5

# voice: the words it understood lit up (a dry run: nothing happens)
# voice: the words it understood lit up (a preview: nothing's decided or run)
ipc voice preview "open spotify on workspace five"
sleep 0.9
shot voice $((cx - 260)) 0 520 172
ipc voice cancel
sleep 0.5

ipc osd toast "Deployed to staging" "rocket_launch" "action"
sleep 0.5
shot toast $((cx - 260)) 0 520 60
sleep 2

ipc dashboard open
sleep 1.2
shot dashboard
ipc dashboard close
sleep 0.6

# the welcome, once "bead." is written
ipc welcome open
sleep 6.7
shot welcome
ipc welcome close
sleep 0.5
