pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// The power button's panel: who and how long up, then lock, suspend, log out,
// reboot, shut down. The last three ask for a second click (it lights red and
// counts down 4 s before giving up).
PanelColumn {
    id: root
    property bool active: false
    signal done()
    width: 284
    spacing: 14

    property string armed: ""
    property int secs: 0
    onActiveChanged: { armed = ""; if (active) Session.refresh(); }
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        running: root.armed !== ""
        onTriggered: { root.secs--; if (root.secs <= 0) root.armed = ""; }
    }

    function press(a: var): void {
        if (a.confirm && armed !== a.id) { armed = a.id; secs = 4; countdown.restart(); return; }
        armed = "";
        done();
        Session.run(a);
    }

    // header: you, the machine, uptime
    Row {
        x: 4
        spacing: 10
        Rectangle {
            width: 36; height: 36; radius: 18
            color: Qt.alpha(Theme.tone("action"), 0.18)
            Text {
                anchors.centerIn: parent
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Theme.tone("action")
                text: Session.user.charAt(0).toUpperCase()
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Bold
                color: Theme.text
                text: Session.user + (Session.host ? "@" + Session.host : "")
            }
            Label { font.pixelSize: 11; text: Session.uptimeText }
        }
    }

    Row {
        id: buttons
        width: parent.width
        Repeater {
            model: Session.actions
            Item {
                id: act
                required property var modelData
                readonly property bool armed: root.armed === modelData.id
                width: buttons.width / Session.actions.length
                height: 66
                Rectangle {
                    id: circle
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44; height: 44; radius: act.armed ? 14 : 22
                    color: act.armed ? Theme.tone("error")
                        : Qt.alpha(Theme.text, ma.pressed ? 0.16 : ma.containsMouse ? 0.11 : 0.06)
                    scale: ma.pressed ? 0.92 : 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on radius { SpringAnimation { spring: 5; damping: 0.35 } }
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                    Icon {
                        anchors.fill: parent
                        name: act.modelData.glyph
                        size: 20
                        fill: act.armed || ma.containsMouse ? 1 : 0
                        color: act.armed ? Theme.frame : act.modelData.id === "shutdown" ? Theme.tone("error") : Theme.text
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: circle.bottom
                    anchors.topMargin: 6
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: act.armed ? Font.Bold : Font.Medium
                    color: act.armed ? Theme.tone("error") : Theme.subtext
                    text: act.armed ? `Sure? ${root.secs}` : act.modelData.title
                }
                MouseArea {
                    id: ma
                    anchors.fill: circle
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.press(act.modelData)
                }
            }
        }
    }
}
