pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Game mode, on its own: while a game is fullscreen (anywhere, even when you
// alt-tab to another workspace), the power profile goes to performance and
// Hyprland's blur and animations go off. When the last game closes or leaves
// fullscreen, they go back to what they were. Settings.gameMode turns it off.
//
// A game is a fullscreen window that's a Steam game (steam_app_*), gamescope,
// a Windows .exe, Minecraft, or anything started by Steam, Proton, Wine,
// Lutris, Heroic, Bottles, umu or a Minecraft launcher. What it changed is kept
// in $XDG_RUNTIME_DIR/bead/gamemode.json, so a restart mid-game still undoes it.
Singleton {
    id: root

    property bool active: false
    property string game: ""          // the game's window class
    signal started(string game)
    signal ended()

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/gamemode.json"

    // looks again shortly after windows change (open, close, fullscreen)
    Connections {
        target: Hyprland
        function onRawEvent(e: HyprlandEvent): void {
            if (/^(openwindow|closewindow|fullscreen|movewindow|windowtitle)$/.test(e.name)) check.restart();
        }
    }
    Timer { id: check; interval: 700; onTriggered: if (!probe.running) probe.running = true }
    // leaving: only once no game has been seen for a few seconds (loading
    // screens drop out of fullscreen for a moment)
    Timer { id: leave; interval: 4000; onTriggered: root.stop() }

    Process {
        id: probe
        command: ["sh", "-c", `
hyprctl clients -j | jq -r '.[] | select(.fullscreen != 0) | "\\(.pid) \\(.class)"' | while read -r pid cls; do
  case "$cls" in steam_app_*|gamescope|*.exe|Minecraft*|minecraft*) echo "$cls"; exit 0;; esac
  p=$pid
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    p=$(sed 's/.*) //' /proc/$p/stat 2>/dev/null | cut -d' ' -f2)
    [ -n "$p" ] && [ "$p" -gt 1 ] || break
    case "$(cat /proc/$p/comm 2>/dev/null)" in
      reaper|steam|wine*|proton|gamescope*|lutris*|heroic*|umu-run|pressure-vessel*|bottles*|prismlauncher|PrismLauncher|minecraft-launc*|[Cc]urse[Ff]orge*)
        echo "$cls"; exit 0;;
    esac
  done
done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const cls = text.trim().split("\n")[0] ?? "";
                if (cls && Settings.gameMode) {
                    leave.stop();
                    root.game = cls;
                    if (!root.active) root.start();
                } else if (root.active && !leave.running) leave.start();
            }
        }
    }

    // what it was, saved; then performance, and no blur or animations
    function start(): void {
        active = true;
        apply.command = ["sh", "-c", `
f="$1"; mkdir -p "\${f%/*}"
[ -f "$f" ] || printf '{"profile":"%s","blur":%s,"anim":%s}' \\
  "$(powerprofilesctl get 2>/dev/null)" \\
  "$(hyprctl getoption decoration:blur:enabled -j | jq .bool)" \\
  "$(hyprctl getoption animations:enabled -j | jq .bool)" > "$f"
command -v powerprofilesctl >/dev/null && powerprofilesctl set performance 2>/dev/null
hyprctl dispatch 'function() hl.config({ decoration = { blur = { enabled = false } }, animations = { enabled = false } }) end' >/dev/null`, "sh", stateFile];
        apply.running = true;
        started(game);
    }
    function stop(): void {
        if (!active) return;
        active = false;
        game = "";
        restore();
        ended();
    }
    // put back what was saved (also at start-up, after a restart mid-game)
    function restore(): void {
        apply.command = ["sh", "-c", `
f="$1"; [ -f "$f" ] || exit 0
p=$(jq -r '.profile // empty' "$f"); b=$(jq -r '.blur' "$f"); a=$(jq -r '.anim' "$f")
[ "$b" = true ] || [ "$b" = false ] || b=true; [ "$a" = true ] || [ "$a" = false ] || a=true
[ -n "$p" ] && powerprofilesctl set "$p" 2>/dev/null
hyprctl dispatch "function() hl.config({ decoration = { blur = { enabled = $b } }, animations = { enabled = $a } }) end" >/dev/null
rm -f "$f"`, "sh", stateFile];
        apply.running = true;
    }
    Process { id: apply }

    // turned off in Settings mid-game: undo it now
    Connections {
        target: Settings
        function onGameModeChanged(): void { if (!Settings.gameMode) root.stop(); else check.restart(); }
    }
    Component.onCompleted: { restore(); check.restart(); }
}
