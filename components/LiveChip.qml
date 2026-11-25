import QtQuick
import qs.config

// A live activity as a pill: icon, text, an optional fill for time left, a pulse.
// Click and right-click are the chip's two actions (see LiveActivities).
Rectangle {
    id: chip
    property string icon
    property string tone
    property string text
    property string hint
    property bool pulse: false
    property bool dim: false
    property real progress: -1 // 0..1 fills the chip; -1: none
    signal clicked
    signal rightClicked
    implicitWidth: chipRow.implicitWidth + 20
    implicitHeight: 30
    radius: 15
    color: hover.hovered ? Qt.alpha(Theme.tone(tone), 0.22) : Qt.alpha(Theme.tone(tone), 0.13)
    opacity: dim ? 0.6 : 1
    clip: true
    Behavior on color { ColorAnimation { duration: 120 } }
    Rectangle { // time left
        visible: chip.progress >= 0
        width: parent.width * Math.max(0, Math.min(1, chip.progress))
        height: parent.height
        color: Qt.alpha(Theme.tone(chip.tone), 0.14)
        Behavior on width { NumberAnimation { duration: 150 } }
    }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 6
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: chip.icon
            size: 16
            fill: 1
            color: Theme.tone(chip.tone)
            SequentialAnimation on opacity {
                running: chip.pulse && chip.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: Theme.body
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Theme.text
            text: chip.text
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: chip.clicked() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: chip.rightClicked() }
}
