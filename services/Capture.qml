pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Hyprland
import Quickshell.Io

// Screenshots (area, window, screen), screen recordings and the colour
// picker. Files go where Caelestia's did: ~/Pictures/Screenshots and
// ~/Videos/Recordings. Screenshots are copied to the clipboard; the
// notification offers Edit (satty) and Open (for 30 minutes: after that
// nothing waits on it, so a notification kept in the history can't leave a
// process behind). Everything waits a moment
// first so the panel that asked has closed.
Singleton {
    id: root

    property bool withSound: false

    readonly property string shotScript: '
        dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"; mkdir -p "$dir"
        f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
        sleep 0.4
        case $1 in
        area) g=$(slurp -d) || exit 0; grim -g "$g" "$f" ;;
        window) # where the focused window is now (asked at capture time)
            g=$(hyprctl -j activewindow | jq -r \'if .at then "\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])" else empty end\')
            if [ -n "$g" ]; then grim -g "$g" "$f"; else grim -o "$2" "$f"; fi ;;
        *) grim -o "$2" "$f" ;;
        esac || exit 0
        wl-copy -t image/png < "$f"
        a=$(timeout 1800 notify-send -a Screenshot -i "$f" -A edit=Edit -A open=Open "Screenshot saved" "Copied to the clipboard · ${f##*/}")
        case $a in edit) satty --filename "$f" --output-filename "$f" ;; open) xdg-open "$f" ;; esac'

    // $1 mode (screen|area|window), $2 monitor, $3 sound device ("" for none),
    // $4 "gif" to turn it into a GIF afterwards (silent, 15 fps, ≤960 px wide,
    // its own palette), copied to the clipboard as a file to paste anywhere
    readonly property string recordScript: '
        dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"; mkdir -p "$dir"
        stamp=$(date +%Y-%m-%d_%H-%M-%S)
        mode=$1 mon=$2 snd=$3 gif=$4
        if [ "$gif" = gif ]; then
            f="${XDG_RUNTIME_DIR:-/tmp}/bead-gif-$stamp.mp4"; snd=""
        else
            f="$dir/recording_$stamp.mp4"
        fi
        sleep 0.4
        case $mode in
        area) g=$(slurp -d) || exit 0; set -- -g "$g" ;;
        window)
            g=$(hyprctl -j activewindow | jq -r \'if .at then "\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])" else empty end\')
            if [ -n "$g" ]; then set -- -g "$g"; else set -- -o "$mon"; fi ;;
        *) set -- -o "$mon" ;;
        esac
        [ -n "$snd" ] && set -- "$@" "--audio=$snd"
        wf-recorder "$@" -f "$f" >/dev/null 2>&1
        [ -s "$f" ] || exit 0
        if [ "$gif" = gif ]; then
            out="$dir/gif_$stamp.gif"
            qs -p "$5" ipc call osd toast "Making the GIF…" "gif_box" "action" >/dev/null 2>&1
            ffmpeg -loglevel error -y -i "$f" -vf "fps=15,scale=\'min(960,iw)\':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" "$out"
            rm -f "$f"
            [ -s "$out" ] || exit 0
            printf "file://%s\\n" "$out" | wl-copy -t text/uri-list
            a=$(timeout 1800 notify-send -a Recorder -i "$out" -A open=Open -A folder="Show folder" "GIF saved" "Copied to the clipboard · ${out##*/} · $(du -h "$out" | cut -f1)")
            case $a in open) xdg-open "$out" ;; folder) xdg-open "$dir" ;; esac
            exit 0
        fi
        a=$(timeout 1800 notify-send -a Recorder -i video-x-generic -A open=Open -A folder="Show folder" "Recording saved" "${f##*/}")
        case $a in open) xdg-open "$f" ;; folder) xdg-open "$dir" ;; esac'

    function monitorName(): string { return Hyprland.focusedMonitor?.name ?? ""; }
    function soundDevice(sound: bool): string { return sound && Audio.sink ? Audio.sink.name + ".monitor" : ""; }

    function shot(mode: string): void {
        Quickshell.execDetached(["sh", "-c", shotScript, "sh", mode, monitorName()]);
    }
    // sound: record what's playing (defaults to the panel's switch)
    function record(mode, sound, gif): void {
        if (Recorder.recording) return;
        Quickshell.execDetached(["sh", "-c", recordScript, "sh", mode, monitorName(), soundDevice(sound ?? withSound), gif ? "gif" : "", Paths.share]);
    }
    function pickColour(): void {
        Quickshell.execDetached(["sh", "-c", 'sleep 0.4; c=$(hyprpicker -a -f hex 2>/dev/null) && [ -n "$c" ] && notify-send -a "Colour picker" -i color-select-symbolic "$c" "Copied to the clipboard"']);
    }

    // `qs ipc call capture shot area|window|screen`, `record screen|area`, `stop`, `pick`
    IpcHandler {
        target: "capture"
        function shot(mode: string): void { root.shot(mode || "area"); }
        // starts a recording, or stops the one running (so a keybind toggles)
        function record(mode: string): void { if (Recorder.recording) Recorder.stop(); else root.record(mode || "screen", false); }
        function recordSound(mode: string): void { if (Recorder.recording) Recorder.stop(); else root.record(mode || "screen", true); }
        // a GIF: starts one, or stops the one running (which then converts)
        function gif(mode: string): void { if (Recorder.recording) Recorder.stop(); else root.record(mode || "area", false, true); }
        function stop(): void { Recorder.stop(); }
        function pick(): void { root.pickColour(); }
    }
}
