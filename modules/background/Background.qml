pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Draws a still wallpaper on every screen (live ones are linux-wallpaperengine's
// job). A new picture crossfades in over the old one.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData
        visible: Wallpaper.kind === "still" && Wallpaper.current !== ""
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "bead-background"
        color: "black"

        // two layers: the one on top fades in, then becomes the bottom
        property bool flip: false
        readonly property string src: Wallpaper.kind === "still" ? "file://" + Wallpaper.current : ""
        onSrcChanged: {
            const next = flip ? a : b;
            next.source = src;
        }
        component Layer: Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(win.width, win.height)
            asynchronous: true
            cache: false
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
        Layer {
            id: a
            z: win.flip ? 0 : 1
            onStatusChanged: if (status === Image.Ready && source == win.src) { opacity = 1; b.opacity = 0; win.flip = false; }
        }
        Layer {
            id: b
            z: win.flip ? 1 : 0
            onStatusChanged: if (status === Image.Ready && source == win.src) { opacity = 1; a.opacity = 0; win.flip = true; }
        }
        Component.onCompleted: if (src) a.source = src
    }
}
