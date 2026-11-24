#!/bin/sh
# The README's clip: ~15 s of bead on an empty workspace (none of your
# windows), recorded with wf-recorder and saved as WebM:
#   the welcome intro → the launcher → maths → the dashboard → a toast.
#
#   tools/clip.sh [OUT]      (default: docs/clip.webm)
#
# Needs a running bead, wf-recorder, ffmpeg and jq. Demo mode is on while it
# runs (no username, no Discord). Your wallpaper is in it, and the dashboard
# shows what's playing: pause music first, and watch it before publishing.
set -eu
out=${1:-docs/clip.webm}
share=${XDG_DATA_HOME:-$HOME/.local/share}/bead
ipc() { qs -p "$share" ipc call "$@" >/dev/null 2>&1 || true; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
[ "$(qs -p "$share" ipc call toast ping 2>/dev/null)" = pong ] || { echo "bead isn't running" >&2; exit 1; }

mon=$(jq -r '.islandScreen // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/bead/settings.json" 2>/dev/null || true)
[ -n "$mon" ] || mon=$(hyprctl monitors -j | jq -r 'sort_by(.id) | .[0].name')
was=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
used=$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id')
ws=
for i in 9 8 7 6 10 11 12; do echo "$used" | grep -qx "$i" || { ws=$i; break; }; done
[ -n "$ws" ] || { echo "no empty workspace to stage on" >&2; exit 1; }
raw=$(mktemp --suffix=.mkv)
dispatch "hl.dsp.focus({ monitor = \"$mon\" })"
dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
ipc demo on
rec=
trap '[ -n "$rec" ] && kill -INT "$rec" 2>/dev/null; ipc demo off; ipc launcher close; ipc dashboard close; ipc welcome close; dispatch "hl.dsp.focus({ workspace = \"$was\" })"; rm -f "$raw"' EXIT
sleep 0.6

wf-recorder -o "$mon" -f "$raw" >/dev/null 2>&1 &
rec=$!
sleep 0.8
ipc welcome open;      sleep 6.5      # the intro: bead → pill → frame → card
ipc welcome close;     sleep 1.0
ipc launcher open;     sleep 0.6
ipc launcher search "fire"; sleep 1.4
ipc launcher search "12 usd to eur"; sleep 1.6
ipc launcher close;    sleep 0.6
ipc dashboard open;    sleep 2.2
ipc dashboard close;   sleep 0.6
ipc osd toast "Deployed to staging" "rocket_launch" "action"; sleep 2.0
kill -INT "$rec"; wait "$rec" 2>/dev/null || true; rec=

mkdir -p "$(dirname "$out")"
# 1280 wide, 30 fps, VP9: small enough for a README
ffmpeg -loglevel error -y -i "$raw" -vf "fps=30,scale=1280:-2:flags=lanczos" -c:v libvpx-vp9 -b:v 0 -crf 36 -row-mt 1 -an "$out"
echo "$out ($(du -h "$out" | cut -f1)): watch it before publishing"
