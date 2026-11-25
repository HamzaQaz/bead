import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config

// Where a voice click is about to land ("click the update button"): a ring
// closes in on the spot with what Claude saw there, for `hold` ms, then
// `go()`. Esc in that time: `cancelled()`. It takes the keyboard only for
// that moment (so Esc reaches it) and never the pointer: the click goes
// through to what's underneath once it's gone.
Scope {
    id: root
    property bool showing: false
    property real gx: 0          // global (layout) position of the click
    property real gy: 0
    property string label: ""
    property int hold: 900
    signal go()
    signal cancelled()

    function show(x: real, y: real, what: string): void {
        gx = x; gy = y; label = what;
        showing = true;
        timer.restart();
    }
    function finish(ok: bool): void {
        if (!showing) return;
        showing = false;
        timer.stop();
        if (ok) go(); else cancelled();
    }
    Timer { id: timer; interval: root.hold; onTriggered: root.finish(true) }

    readonly property var where: Quickshell.screens.find(s => root.gx >= s.x && root.gx < s.x + s.width
        && root.gy >= s.y && root.gy < s.y + s.height) ?? Quickshell.screens[0]

    PanelWindow {
        visible: root.showing
        screen: root.where
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-clickring"
        WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            id: spot
            focus: true
            x: root.gx - (root.where?.x ?? 0)
            y: root.gy - (root.where?.y ?? 0)
            Keys.onEscapePressed: root.finish(false)

            // closes in from wide and faint to tight and bright
            property real t: 0
            NumberAnimation on t {
                running: root.showing
                from: 0; to: 1
                duration: root.hold * 0.7
                easing.type: Easing.OutCubic
            }
            Rectangle {
                readonly property real d: 96 - 60 * spot.t
                width: d; height: d; radius: d / 2
                x: -d / 2; y: -d / 2
                color: Qt.alpha(Theme.tone("action"), 0.12 * spot.t)
                border.width: 3
                border.color: Qt.alpha(Theme.tone("action"), 0.35 + 0.65 * spot.t)
            }
            Rectangle { // the point itself
                width: 6; height: 6; radius: 3
                x: -3; y: -3
                color: Theme.tone("action")
                opacity: spot.t
            }
            Rectangle { // what it is, and how to stop it
                x: 30
                y: -height / 2
                height: 30
                radius: 15
                width: tag.implicitWidth + 24
                color: Qt.alpha(Theme.frame, 0.92)
                opacity: Math.min(1, spot.t * 2)
                Text {
                    id: tag
                    anchors.centerIn: parent
                    font.family: Theme.font
                    font.pixelSize: Theme.body
                    color: Theme.text
                    textFormat: Text.StyledText
                    text: root.label.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "  <font color=\"" + Theme.subtext + "\">Esc to stop</font>"
                }
            }
        }
    }
}
