#!/bin/sh
# Close-up GIFs of the island and notifications: each scene is recorded as
# just its region of the screen, losslessly, and turned into a GIF at that
# size (no scaling, so the UI stays sharp).
#
#   tools/gifs.sh [OUT_DIR]       (default: gifs/)
#     OUT_DIR/NAME.mkv   the lossless region recording (x264rgb, crf 0)
#     OUT_DIR/NAME.gif   from it: 30 fps, one palette per clip
#
# Stages everything on an empty workspace with demo mode on (made-up track and
# notifications) and the pointer hidden, then puts your workspace and pointer
# back. Real pop-ups (Glint, a Claude Code prompt) still show: clear them
# first, and look at the GIFs before you publish them. About 40 s.
# Needs a running bead, wf-recorder, ffmpeg, jq.
set -eu
out=${1:-gifs}
share=${XDG_DATA_HOME:-$HOME/.local/share}/bead
here=$(dirname "$0")
ipc() { qs -p "$share" ipc call "$@" >/dev/null 2>&1 || true; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
[ "$(qs -p "$share" ipc call toast ping 2>/dev/null)" = pong ] || { echo "bead isn't running" >&2; exit 1; }
mkdir -p "$out"

mon=$(jq -r '.islandScreen // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/bead/settings.json" 2>/dev/null || true)
[ -n "$mon" ] || mon=$(hyprctl monitors -j | jq -r 'sort_by(.id) | .[0].name')
read -r mx my mw <<EOF
$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | "\(.x) \(.y) \(.width / .scale | floor)"')
EOF
cx=$((mw / 2))
was=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
used=$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id'; hyprctl monitors -j | jq -r '.[].activeWorkspace.id')
ws=
for i in 9 8 7 6 10 11 12; do echo "$used" | grep -qx "$i" || { ws=$i; break; }; done
[ -n "$ws" ] || { echo "no empty workspace to stage on" >&2; exit 1; }

ptr=$(hyprctl cursorpos | tr -d ' ')
pointer() { dispatch "function() hl.config({ cursor = { invisible = $1 } }) end"; }
at() { python3 "$here/glide.py" $((mx + $1)) $((my + $2)) "${3:-1}"; }
rec=
trap '[ -n "$rec" ] && kill -INT "$rec" 2>/dev/null; ipc demo off; ipc launcher close; ipc dashboard close; ipc voice cancel; ipc notifs close; dispatch "hl.dsp.focus({ workspace = \"$was\" })"; hyprctl dispatch "hl.dsp.cursor.move({ x = ${ptr%,*}, y = ${ptr#*,} })" >/dev/null; pointer false' EXIT

dispatch "hl.dsp.focus({ monitor = \"$mon\" })"
dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
ipc demo on
ipc dashboard close; ipc launcher close; ipc notifs close
pointer true
at 960 700
sleep 1.2

# start NAME X Y W H: record that region (relative to the monitor), losslessly
start() {
	now=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
	[ "$now" = "$ws" ] || { echo "the workspace changed mid-way: stopped" >&2; exit 1; }
	name=$1
	wf-recorder -g "$((mx + $2)),$((my + $3)) ${4}x${5}" -r 60 -c libx264rgb -p crf=0 -p preset=ultrafast -f "$out/$name.mkv" >/dev/null 2>&1 &
	rec=$!
	sleep 0.5
}
stop() { kill -INT "$rec"; wait "$rec" 2>/dev/null || true; rec=; }

# the island: rest, the media card on hover, the launcher
start island $((cx - 440)) 0 880 550
sleep 1.0
at "$cx" 18; sleep 0.95   # the card; staying past ~1 s goes on to the dashboard
at 960 700;          sleep 1.2
ipc launcher open; sleep 0.3; ipc launcher search "term"; sleep 1.6
ipc launcher search "5 usd to eur"; sleep 1.6
ipc launcher close;  sleep 1.0
stop

# a notification out of the corner, then another
start notifications $((mw - 640)) 0 640 400
ipc demo notify 0;   sleep 4.4
ipc demo notify 1;   sleep 4.6
stop

# a toast, then voice
start toast-voice $((cx - 360)) 0 720 450
ipc osd toast "Deployed to staging" "rocket_launch" "action"; sleep 2.6
ipc voice preview "open spotify on workspace five"; sleep 2.4
ipc voice cancel;    sleep 1.0
stop

# the dashboard dropping out of the frame
start dashboard $((cx - 600)) 0 1200 750
ipc dashboard open; ipc dashboard tab 0; sleep 2.4
ipc dashboard close; sleep 1.2
stop

# the GIFs: at the recorded size, 30 fps, one palette per clip (built from
# what changes, so the UI gets the colours), light error diffusion
for f in "$out"/*.mkv; do
	ffmpeg -loglevel error -y -i "$f" -vf "fps=30,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" "${f%.mkv}.gif"
done
ls -sh "$out"/*.gif
