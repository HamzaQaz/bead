// bead-hold: a still of the screen held over everything while bead restarts,
// then faded out, so a restart reads as one crossfade instead of the wallpaper,
// bar and window sizes popping in turn. `bead restart` takes the stills
// (grim, one per monitor, in $BEAD_HOLD_DIR) and runs this as its own instance.
// It lets every click through, and lets go by itself after 8 s.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    settings.watchFiles: false

    readonly property string dir: Quickshell.env("BEAD_HOLD_DIR") || "/tmp/bead-hold"
    property bool releasing: false
    property int loaded: 0

    function release(): void {
        if (releasing) return;
        releasing = true;
        quit.start();
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bead-hold"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {} // clicks go through

            Image {
                anchors.fill: parent
                source: "file://" + root.dir + "/" + win.modelData.name + ".png"
                cache: false
                smooth: true
                fillMode: Image.Stretch
                onStatusChanged: if (status === Image.Ready) root.loaded++
                opacity: root.releasing ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            }
        }
    }

    Timer { id: quit; interval: 450; onTriggered: Qt.quit() }
    Timer { interval: 8000; running: true; onTriggered: root.release() } // never stuck

    IpcHandler {
        target: "hold"
        // "yes" once every monitor's still is showing
        function ready(): string { return root.loaded >= Quickshell.screens.length ? "yes" : "no"; }
        function release(): void { root.release(); }
    }
}
