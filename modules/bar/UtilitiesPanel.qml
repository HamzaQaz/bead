pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import qs.components
import qs.config
import qs.services

// Utilities: capture (a screenshot, a video or a GIF of an area, a window or
// the screen; the latest screenshots to reopen; stop a running recording) and
// a row of quick toggles: do not disturb, keep awake, mic, colour picker.
PanelColumn {
    id: root
    property bool active: false
    signal done()   // close the panel (before a capture)
    width: 300
    spacing: 8

    // a square-ish button with a glyph and a label; `on` lights it
    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string label: ""
        property bool on: false
        property color tone: Theme.tone("action")
        signal hit()
        height: 64
        radius: 16
        color: on ? tile.tone : Qt.alpha(Theme.text, tma.pressed ? 0.15 : tma.containsMouse ? 0.1 : 0.055)
        scale: tma.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
        Column {
            anchors.centerIn: parent
            spacing: 4
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 22; height: 22
                name: tile.glyph
                size: 21
                fill: tile.on || tma.containsMouse ? 1 : 0
                color: tile.on ? Theme.frame : Theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: tile.on ? Theme.frame : Theme.subtext
                text: tile.label
            }
        }
        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.hit() }
    }
    // what a capture makes; remembered while bead runs
    property string kind: "shot" // shot | video | gif

    // a small pill toggle for the quick row
    component Chip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property bool on: false
        signal hit()
        height: 34
        radius: 17
        color: on ? Theme.tone("action") : Qt.alpha(Theme.text, cma.pressed ? 0.15 : cma.containsMouse ? 0.1 : 0.055)
        scale: cma.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
        Row {
            anchors.centerIn: parent
            spacing: 5
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: chip.glyph
                size: 16
                fill: chip.on ? 1 : 0
                color: chip.on ? Theme.frame : Theme.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: chip.on ? Theme.frame : Theme.subtext
                text: chip.label
            }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.hit() }
    }

    PanelHeader {
        icon: "widgets"
        title: "Utilities"
        // video only: record what's playing too
        Rectangle {
            visible: root.kind === "video" && !Recorder.recording
            width: 30; height: 30; radius: 15
            color: Capture.withSound ? Qt.alpha(Theme.tone("action"), 0.2) : Qt.alpha(Theme.text, sma.containsMouse ? 0.1 : 0.055)
            Behavior on color { ColorAnimation { duration: 160 } }
            Icon {
                anchors.centerIn: parent
                name: Capture.withSound ? "volume_up" : "volume_off"
                size: 16
                fill: 1
                color: Capture.withSound ? Theme.tone("action") : Theme.subtext
            }
            MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Capture.withSound = !Capture.withSound }
        }
    }

    // ── a recording running: one big stop ──
    Tile {
        visible: Recorder.recording
        width: root.width
        height: 52
        on: true
        tone: Theme.tone("error")
        glyph: "stop_circle"
        label: "Stop recording · " + Recorder.label
        onHit: Recorder.stop()
    }

    // ── capture: what (shot / video / GIF), then where ──
    Rectangle {
        visible: !Recorder.recording
        width: root.width
        height: 34
        radius: 17
        color: Qt.alpha(Theme.text, 0.055)
        readonly property var kinds: [{ k: "shot", t: "Screenshot", g: "photo_camera" }, { k: "video", t: "Video", g: "videocam" }, { k: "gif", t: "GIF", g: "gif_box" }]
        // the lit segment slides between choices
        Rectangle {
            id: seg
            readonly property int i: Math.max(0, parent.kinds.findIndex(o => o.k === root.kind))
            x: 3 + i * (parent.width - 6) / 3
            y: 3
            width: (parent.width - 6) / 3
            height: parent.height - 6
            radius: height / 2
            color: Theme.tone("action")
            Behavior on x { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.2 } }
        }
        Row {
            x: 3
            y: 3
            Repeater {
                model: parent.parent.kinds
                Item {
                    id: kb
                    required property var modelData
                    required property int index
                    readonly property bool on: root.kind === modelData.k
                    width: (root.width - 6) / 3
                    height: 28
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: kb.modelData.g
                            size: 15
                            fill: kb.on ? 1 : 0
                            color: kb.on ? Theme.frame : Theme.subtext
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: kb.on ? Theme.frame : Theme.subtext
                            Behavior on color { ColorAnimation { duration: 160 } }
                            text: kb.modelData.t
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.kind = kb.modelData.k }
                }
            }
        }
    }
    Row {
        visible: !Recorder.recording
        width: root.width
        spacing: 8
        Repeater {
            model: [
                { m: "area", g: "screenshot_region", t: "Area" },
                { m: "window", g: "select_window", t: "Window" },
                { m: "screen", g: "screenshot_monitor", t: "Screen" }
            ]
            Tile {
                required property var modelData
                width: (root.width - 16) / 3
                height: 58
                glyph: modelData.g
                label: modelData.t
                onHit: {
                    root.done();
                    if (root.kind === "shot") Capture.shot(modelData.m);
                    else Capture.record(modelData.m, root.kind === "video" ? undefined : false, root.kind === "gif");
                }
            }
        }
    }
    // screenshots only: the latest few, click to edit
    FolderListModel {
        id: shots
        folder: "file://" + (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures") + "/Screenshots"
        nameFilters: ["*.png", "*.jpg"]
        sortField: FolderListModel.Time
        showDirs: false
    }
    Row {
        visible: shots.count > 0 && root.kind === "shot" && !Recorder.recording
        width: root.width
        spacing: 8
        Repeater {
            model: shots   // newest first; only the first three show
            Rectangle {
                id: thumb
                required property int index
                required property string filePath
                readonly property string path: filePath
                visible: index < 3
                width: (root.width - 16) / 3
                height: width * 9 / 16
                radius: 10
                color: Qt.alpha(Theme.text, 0.06)
                // the picture, rounded by a mask (clip alone keeps square corners)
                Image {
                    anchors.fill: parent
                    source: Wallpaper.url(thumb.path)
                    sourceSize: Qt.size(240, 135)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: thumbMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                }
                Rectangle { id: thumbMask; anchors.fill: parent; radius: 10; visible: false; layer.enabled: true }
                Rectangle { // hover ring
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: thumbMa.containsMouse ? 2 : 0
                    border.color: Theme.tone("action")
                }
                MouseArea {
                    id: thumbMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.done(); Quickshell.execDetached(["satty", "--filename", thumb.path, "--output-filename", thumb.path]); }
                }
            }
        }
    }

    // ── quick toggles: one compact row ──
    Rectangle { width: root.width; height: 1; color: Qt.alpha(Theme.text, 0.08) }
    Row {
        width: root.width
        spacing: 6
        readonly property real w: (root.width - 18) / 4
        Chip { width: parent.w; glyph: "do_not_disturb_on"; label: "Quiet"; on: Notifs.dnd; onHit: Notifs.dnd = !Notifs.dnd }
        Chip { width: parent.w; glyph: "coffee"; label: "Awake"; on: Idle.keepAwake; onHit: Idle.keepAwake = !Idle.keepAwake }
        Chip { width: parent.w; glyph: Audio.micMuted ? "mic_off" : "mic"; label: "Mic"; on: !Audio.micMuted; onHit: Audio.toggleMicMute() }
        Chip { width: parent.w; glyph: "colorize"; label: "Pick"; onHit: { root.done(); Capture.pickColour(); } }
    }
}
