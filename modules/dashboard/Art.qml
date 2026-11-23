import QtQuick
import QtQuick.Effects
import qs.components
import qs.config

// Rounded album art with a music-note placeholder.
Item {
    id: root
    property url source: ""
    property real radius: 12
    readonly property bool ready: img.status === Image.Ready

    Rectangle { anchors.fill: parent; radius: root.radius; color: Qt.alpha(Theme.text, 0.08) }
    Image {
        id: img
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(400, 400)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    Rectangle { id: mask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
    MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask; visible: root.ready }
    Icon { anchors.centerIn: parent; visible: !root.ready; name: "music_note"; size: Math.min(root.width, root.height) * 0.38; color: Theme.subtext }
}
