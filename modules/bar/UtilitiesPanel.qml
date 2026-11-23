pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import qs.components
import qs.config
import qs.services

// Utilities: screenshots (area, window, screen) with the latest few to
// reopen, screen recording (screen or area, optionally with sound; stop while
// running), and quick toggles: do not disturb, keep awake, mic, colour picker.
Column {
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
    component Section: Label {
        x: 4
        topPadding: 4
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    PanelHeader { icon: "widgets"; title: "Utilities" }

    // ── screenshot ──
    Section { text: "Screenshot" }
    Row {
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
                glyph: modelData.g
                label: modelData.t
                onHit: { root.done(); Capture.shot(modelData.m); }
            }
        }
    }
    // the latest few: click to edit
    FolderListModel {
        id: shots
        folder: "file://" + (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures") + "/Screenshots"
        nameFilters: ["*.png", "*.jpg"]
        sortField: FolderListModel.Time
        showDirs: false
    }
    Row {
        visible: shots.count > 0
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

    // ── record ──
    Section { text: "Record" }
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
    Row {
        visible: !Recorder.recording
        width: root.width
        spacing: 8
        Tile { width: (root.width - 16) / 3; glyph: "screen_record"; label: "Screen"; onHit: { root.done(); Capture.record("screen"); } }
        Tile { width: (root.width - 16) / 3; glyph: "crop_free"; label: "Area"; onHit: { root.done(); Capture.record("area"); } }
        Tile {
            width: (root.width - 16) / 3
            glyph: Capture.withSound ? "volume_up" : "volume_off"
            label: "Sound"
            on: Capture.withSound
            onHit: Capture.withSound = !Capture.withSound
        }
    }

    // ── quick toggles ──
    Section { text: "Quick" }
    Grid {
        columns: 4
        spacing: 8
        Tile { width: (root.width - 24) / 4; glyph: "do_not_disturb_on"; label: "Quiet"; on: Notifs.dnd; onHit: Notifs.dnd = !Notifs.dnd }
        Tile { width: (root.width - 24) / 4; glyph: "coffee"; label: "Awake"; on: Idle.keepAwake; onHit: Idle.keepAwake = !Idle.keepAwake }
        Tile { width: (root.width - 24) / 4; glyph: Audio.micMuted ? "mic_off" : "mic"; label: "Mic"; on: !Audio.micMuted; onHit: Audio.toggleMicMute() }
        Tile { width: (root.width - 24) / 4; glyph: "colorize"; label: "Picker"; onHit: { root.done(); Capture.pickColour(); } }
    }
}
