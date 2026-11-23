pragma Singleton

import QtQuick
import Quickshell
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

    // $1 mode (screen|area), $2 monitor, $3 sound device ("" for none)
    readonly property string recordScript: '
        dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"; mkdir -p "$dir"
        f="$dir/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
        mode=$1 mon=$2 snd=$3
        sleep 0.4
        if [ "$mode" = area ]; then g=$(slurp -d) || exit 0; set -- -g "$g"; else set -- -o "$mon"; fi
        [ -n "$snd" ] && set -- "$@" "--audio=$snd"
        wf-recorder "$@" -f "$f" >/dev/null 2>&1
        [ -s "$f" ] || exit 0
        a=$(timeout 1800 notify-send -a Recorder -i video-x-generic -A open=Open -A folder="Show folder" "Recording saved" "${f##*/}")
        case $a in open) xdg-open "$f" ;; folder) xdg-open "$dir" ;; esac'

    function monitorName(): string { return Hyprland.focusedMonitor?.name ?? ""; }
    function soundDevice(sound: bool): string { return sound && Audio.sink ? Audio.sink.name + ".monitor" : ""; }

    function shot(mode: string): void {
        Quickshell.execDetached(["sh", "-c", shotScript, "sh", mode, monitorName()]);
    }
    // sound: record what's playing (defaults to the panel's switch)
    function record(mode, sound): void {
        if (Recorder.recording) return;
        Quickshell.execDetached(["sh", "-c", recordScript, "sh", mode, monitorName(), soundDevice(sound ?? withSound)]);
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
        function stop(): void { Recorder.stop(); }
        function pick(): void { root.pickColour(); }
    }
}
