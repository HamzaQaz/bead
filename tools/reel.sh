#!/bin/sh
# The whole tour, for a post (r/unixporn): the island, dashboard tabs, launcher,
# notifications, bar panels, overview and the App Store, as stills and one
# near-lossless 60 fps recording with a mark at each scene.
#
#   tools/reel.sh [OUT_DIR]         (default: reel/)
#     OUT_DIR/stills/NAME.png   the whole monitor, at each settled moment
#     OUT_DIR/run.mkv           the recording (x264, crf 10, 60 fps)
#     OUT_DIR/run.marks         SECONDS NAME, where each scene starts in it
#
# Stages everything on an empty workspace with demo mode on (made-up media and
# notifications, no name, no Discord) and the pointer hidden, then puts your
# workspace and pointer back. Needs a running bead, grim, wf-recorder, jq.
# It takes about 95 s: don't touch anything meanwhile. Real pop-ups (Glint, a
# Claude Code prompt) still show in demo mode: clear them first, and look through
# everything before you publish it.
set -eu
out=${1:-reel}
share=${XDG_DATA_HOME:-$HOME/.local/share}/bead
here=$(dirname "$0")
ipc() { qs -p "$share" ipc call "$@" >/dev/null 2>&1 || true; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
[ "$(qs -p "$share" ipc call toast ping 2>/dev/null)" = pong ] || { echo "bead isn't running" >&2; exit 1; }
mkdir -p "$out/stills"

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
trap '[ -n "$rec" ] && kill -INT "$rec" 2>/dev/null; ipc demo off; ipc launcher close; ipc dashboard close; ipc voice cancel; ipc notifs close; ipc welcome close; ipc store close; ipc settings close; ipc overview close; ipc timer stopAll; ipc activity clear reel; dispatch "hl.dsp.focus({ workspace = \"$was\" })"; hyprctl dispatch "hl.dsp.cursor.move({ x = ${ptr%,*}, y = ${ptr#*,} })" >/dev/null; pointer false' EXIT

dispatch "hl.dsp.focus({ monitor = \"$mon\" })"
dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
ipc demo on
ipc dashboard close; ipc launcher close; ipc notifs close
pointer true
at 960 700
sleep 1.2

wf-recorder -o "$mon" -r 60 -c libx264 -p crf=10 -p preset=ultrafast -f "$out/run.mkv" >/dev/null 2>&1 &
rec=$!
t0=$(date +%s.%N)
: >"$out/run.marks"
mark() { echo "$(awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN { print a - b }') $1" >>"$out/run.marks"; }
shot() { # the workspace must still be ours (you switched away: stop)
	now=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
	[ "$now" = "$ws" ] || { echo "the workspace changed mid-way: stopped" >&2; exit 1; }
	grim -o "$mon" "$out/stills/$1.png"
}
sleep 0.8

# the welcome's intro, played out, then its first slide; then it leaves
mark welcome;        ipc welcome open; sleep 1.0
n=0; while [ "$(qs -p "$share" ipc call welcome playing 2>/dev/null)" = true ] && [ $n -lt 60 ]; do sleep 0.25; n=$((n + 1)); done
mark hello;          sleep 2.4; shot hello
ipc welcome close;   sleep 1.6
# the island at rest, something playing
mark rest;           sleep 1.6; shot rest
# hover: the media card grows
mark media;          at "$cx" 18 700; sleep 0.9; shot media; sleep 0.3
at 960 700 600;      sleep 1.0
# the dashboard, tab by tab
mark dashboard;      ipc dashboard open; ipc dashboard tab 0; sleep 1.6; shot dashboard
for t in 1 2 3 4 5 6; do mark "tab$t"; ipc dashboard tab $t; sleep 1.5; shot "tab$t"; done
ipc dashboard close; sleep 1.0
# the launcher: apps, then maths
mark launcher;       ipc launcher open; sleep 0.3; ipc launcher search "term"; sleep 1.3; shot launcher
mark maths;          ipc launcher search "5 usd to eur"; sleep 1.4; shot maths
ipc launcher close;  sleep 0.9
# notifications, then the history
mark notify;         ipc demo notify 0; sleep 1.5; shot notify; sleep 2.2
mark notify2;        ipc demo notify 1; sleep 1.5; shot notify2; sleep 2.4
mark history;        ipc notifs open; sleep 1.2; shot history; sleep 0.4
ipc notifs close;    sleep 0.9
# live activity on the island: a build with progress, then done
mark activity;       ipc activity set reel deployed_code "Building bead" 0.15; sleep 0.7
for p in 0.35 0.55 0.8 1; do ipc activity set reel deployed_code "Building bead" $p; sleep 0.45; done
shot activity;       ipc activity done reel "Build finished"; sleep 2.2
# a toast, a timer
mark toast;          ipc osd toast "Deployed to staging" "rocket_launch" "action"; sleep 0.8; shot toast; sleep 1.6
mark timer;          ipc timer start "25m"; sleep 1.6; shot timer; sleep 0.6
# voice
mark voice;          ipc voice preview "open spotify on workspace five"; sleep 1.2; shot voice; sleep 1.0
ipc voice cancel;    sleep 0.9
# the bar's panels
for p in wifi bt power; do mark "panel-$p"; ipc bar panel $p; sleep 1.5; shot "panel-$p"; ipc bar panel $p; sleep 0.6; done
# the overview
mark overview;       ipc overview open; sleep 1.6; shot overview; ipc overview close; sleep 1.0
# the App Store: the front, a glide down and back, a search by need, an app
mark store;          ipc store open ""; sleep 3.2; shot store
ipc store scroll 760; sleep 1.6; shot store-down; ipc store scroll -760; sleep 1.4
mark search;         q=""; for c in s c r e e n " " r e c o r d e r; do q="$q$c"; ipc store open "$q"; sleep 0.07; done
sleep 2.4;           shot search
mark details;        ipc store detail obs-studio; sleep 3.2; shot details; sleep 0.4
ipc store close;     sleep 1.2
mark end
kill -INT "$rec"; wait "$rec" 2>/dev/null || true; rec=
echo "$out: $(ls "$out/stills" | wc -l) stills, run.mkv ($(du -h "$out/run.mkv" | cut -f1)), run.marks"
