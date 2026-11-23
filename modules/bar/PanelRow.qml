import QtQuick
import Quickshell.Widgets
import qs.components
import qs.config

// One line in a bar panel: an icon (glyph or image) in a circle, a title and
// a subtitle, optional trailing controls. Lit rows are tinted.
Rectangle {
    id: row
    property string icon: ""
    property string iconRef: ""
    property string image: ""
    property string title: ""
    property string sub: ""
    property bool lit: false
    property bool busy: false
    property bool dim: false
    default property alias trailing: trail.data
    signal clicked(var mouse)

    width: parent?.width ?? 0
    height: 42
    radius: 13
    color: lit ? Qt.alpha(Theme.tone("action"), ma.containsMouse ? 0.24 : 0.16)
        : Qt.alpha(Theme.text, ma.containsMouse ? 0.07 : 0)
    Behavior on color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => row.clicked(e)
    }

    Rectangle {
        id: badge
        x: 7
        anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28; radius: 14
        color: row.lit ? Qt.alpha(Theme.tone("action"), 0.2) : Qt.alpha(Theme.text, 0.06)
        Icon {
            anchors.centerIn: parent
            visible: !row.image
            name: row.icon
            ref: row.iconRef
            size: 16
            fill: row.lit ? 1 : 0
            color: row.lit ? Theme.tone("action") : row.dim ? Theme.subtext : Theme.text
        }
        IconImage {
            anchors.centerIn: parent
            visible: !!row.image
            implicitSize: 16
            source: row.image
        }
        // busy: a ring ripples out of the badge
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: parent.width; height: parent.height; radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: Theme.tone("action")
            opacity: 0
            visible: row.busy
            ParallelAnimation {
                running: row.busy
                loops: Animation.Infinite
                NumberAnimation { target: ring; property: "scale"; from: 0.9; to: 1.55; duration: 1100; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0; duration: 1100; easing.type: Easing.OutCubic }
            }
        }
    }

    Column {
        x: 44
        anchors.verticalCenter: parent.verticalCenter
        width: trail.x - x - 8
        Text {
            width: parent.width
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: row.dim ? Theme.subtext : Theme.text
            text: row.title
        }
        Label {
            width: parent.width
            visible: !!row.sub
            elide: Text.ElideRight
            font.pixelSize: 11
            text: row.sub
        }
    }

    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
    }
}
