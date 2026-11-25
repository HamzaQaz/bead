#!/bin/sh
# The demo reel for the landing page and the README: about a minute of bead
# on an empty workspace, recorded with wf-recorder. The pointer glides to
# the bar and the wallpaper it picks (tools/glide.py; hidden otherwise) and the interesting parts get eased zooms,
# added afterwards (tools/zoom.py):
#   the welcome intro → the launcher (apps, maths, clipboard) → notifications
#   → Wi-Fi, Bluetooth, power → the dashboard's tabs → a wallpaper change (the
#   colour ripple) → the overview → a voice command → a toast → the lock screen.
#
#   tools/clip.sh [OUT]      (default: docs/demo.webm, and the same as .mp4)
#
# Needs a running bead, wf-recorder, ffmpeg, jq and python-pillow. Demo mode is
# on while it runs: everything shown is made up (services/demo.js), and no
# recording indicator. It changes the wallpaper to bead's tide and back to the
# one you had, and puts the pointer back where it was. Watch it before publishing.
set -eu
out=${1:-docs/demo.webm}
share=${XDG_DATA_HOME:-$HOME/.local/share}/bead
ipc() { qs -p "$share" ipc call "$@" >/dev/null 2>&1 || true; }
dispatch() { hyprctl dispatch "$1" >/dev/null; }
[ "$(qs -p "$share" ipc call toast ping 2>/dev/null)" = pong ] || { echo "bead isn't running" >&2; exit 1; }

mon=$(jq -r '.islandScreen // empty' "${XDG_CONFIG_HOME:-$HOME/.config}/bead/settings.json" 2>/dev/null || true)
[ -n "$mon" ] || mon=$(hyprctl monitors -j | jq -r 'sort_by(.id) | .[0].name')
was=$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | .activeWorkspace.name')
# not one with windows, and not one another monitor is showing (focusing
# that would jump to the other monitor instead of bringing it here)
used=$(hyprctl workspaces -j | jq -r '.[] | select(.windows > 0) | .id'; hyprctl monitors -j | jq -r '.[].activeWorkspace.id')
ws=
for i in 9 8 7 6 10 11 12; do echo "$used" | grep -qx "$i" || { ws=$i; break; }; done
[ -n "$ws" ] || { echo "no empty workspace to stage on" >&2; exit 1; }
raw=$(mktemp --suffix=.mkv); zoomed=$(mktemp --suffix=.mkv); zooms=$(mktemp)
marks="${out%.*}.marks"; mkdir -p "$(dirname "$out")"; : >"$marks"
here=$(dirname "$0")
glide() { python3 "$here/glide.py" "$@"; }
# a showcase zoom starting now: zoom SECONDS X Y SCALE (X Y on the monitor)
zoom() { echo "$(awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN { print a - b }') $*" >>"$zooms"; }
# a scene starting now, for editing the reel (OUT.marks: SECONDS NAME)
mark() { echo "$(awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN { print a - b }') $1" >>"$marks"; }
# where the monitor is, for the pointer (glide takes layout coordinates)
read -r mx my <<EOF2
$(hyprctl monitors -j | jq -r --arg m "$mon" '.[] | select(.name == $m) | "\(.x) \(.y)"')
EOF2
at() { glide $((mx + $1)) $((my + $2)) "${3:-650}"; }
ptr=$(hyprctl cursorpos | tr -d ' ')
dispatch "hl.dsp.focus({ monitor = \"$mon\" })"
dispatch "hl.dsp.focus({ workspace = \"$ws\" })"
ipc demo on
rec=
wp=$(qs -p "$share" ipc call wallpaper current 2>/dev/null || true)   # "still PATH" or "live ID"
trap '[ -n "$rec" ] && kill -INT "$rec" 2>/dev/null; [ -n "$wp" ] && ipc wallpaper ${wp%% *} "${wp#* }"; ipc demo off; ipc launcher close; ipc dashboard close; ipc welcome close; ipc voice cancel; ipc notifs close; ipc overview close; ipc lock endPreview; dispatch "hl.dsp.focus({ workspace = \"$was\" })"; hyprctl dispatch "hl.dsp.cursor.move({ x = ${ptr%,*}, y = ${ptr#*,} })" >/dev/null; hyprctl dispatch "function() hl.config({ cursor = { invisible = false } }) end" >/dev/null; rm -f "$raw" "$zoomed" "$zooms"' EXIT
sleep 0.6

# the pointer is hidden, and shows only where it does something (the bar, the
# wallpaper pick): it's moved into place while hidden, then glides
pointer() { dispatch "function() hl.config({ cursor = { invisible = $1 } }) end"; }
show() { at "$1" "$2" 1; sleep 0.05; pointer false; }
pointer true
at 960 620 1
# near-lossless capture: the zoom pass and the web encodes start from this
wf-recorder -o "$mon" -r 60 -c libx264 -p crf=14 -p preset=superfast -f "$raw" >/dev/null 2>&1 &
rec=$!
t0=$(date +%s.%N)
sleep 0.8
mark intro
ipc welcome open;      sleep 12       # the intro: bead → island, the frame and bar sketched, then the real ones
ipc welcome close;     sleep 0.8

# the launcher: apps, maths, the clipboard
mark launcher
ipc launcher open;     sleep 0.5
zoom 7.4 960 230 1.45
ipc launcher search "term"; sleep 1.8
ipc launcher search "12 usd to eur"; sleep 2.0
ipc launcher mode ";";  sleep 2.4
ipc launcher close;    sleep 0.7

# notifications: one pops up, then the history
mark notifications
zoom 3.6 1690 60 1.9
ipc demo notify 0;     sleep 3.8
ipc notifs open;       sleep 0.4
zoom 3.4 1700 330 1.5; sleep 3.4
ipc notifs close;      sleep 0.7

# the bar: Wi-Fi, Bluetooth, you (the pointer does this one)
mark bar
show 420 760
at 27 962 900;         ipc bar panel wifi; sleep 0.3
zoom 7.0 260 860 1.7;  sleep 2.0
at 27 1000 450;        ipc bar panel bt; sleep 2.1
at 27 1059 450;        ipc bar panel power; sleep 2.2
ipc bar panel power;   sleep 0.3
pointer true;          sleep 0.4

# the dashboard
mark dashboard
ipc dashboard tab 0;   sleep 1.6
zoom 3.2 1130 230 1.7; sleep 3.4
ipc dashboard tab 1;   sleep 2.2     # media
ipc dashboard tab 3;   sleep 2.0     # weather
ipc dashboard tab 2;   sleep 2.0     # performance
mark wallpaper
ipc dashboard tab 5;   sleep 1.0     # wallpapers: the pointer picks tide
show 1060 520
at 834 320 700;        sleep 0.35
ipc wallpaper still "$share/data/wallpapers/tide.jpg"; sleep 0.5   # new colours ripple out from the island
pointer true
ipc dashboard close;   sleep 3.4

# the overview
mark overview
ipc overview open;     sleep 0.4
zoom 3.2 960 170 1.4;  sleep 3.4
ipc overview close;    sleep 0.7

# voice, a toast
mark voice
ipc voice preview "open spotify on workspace five"; sleep 0.2
zoom 4.8 960 60 1.8;   sleep 2.8
ipc voice cancel;      sleep 0.4
mark toast
ipc osd toast "Deployed to staging" "rocket_launch" "action"; sleep 2.6

# the lock screen
mark lock
ipc lock preview;      sleep 3.8
ipc lock endPreview;   sleep 1.0
kill -INT "$rec"; wait "$rec" 2>/dev/null || true; rec=
mark end
pointer false   # yours back now, not after the encodes

python3 "$here/zoom.py" "$raw" "$zooms" "$zoomed"
mkdir -p "$(dirname "$out")"
# full HD, 60 fps: VP9 WebM, and H.264 MP4 for browsers without VP9
ffmpeg -loglevel error -y -i "$zoomed" -c:v libvpx-vp9 -b:v 0 -crf 28 -row-mt 1 -pix_fmt yuv420p -an "$out"
ffmpeg -loglevel error -y -i "$zoomed" -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -movflags +faststart -an "${out%.*}.mp4"
# and a still from the end of the intro, for the page before the video plays
ffmpeg -loglevel error -y -ss 12.5 -i "$zoomed" -frames:v 1 -q:v 2 "${out%.*}-poster.jpg"
echo "$out ${out%.*}.mp4 ${out%.*}-poster.jpg ($(du -ch "$out" "${out%.*}.mp4" | tail -1 | cut -f1)): watch it before publishing"
