pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// The preview at the top of each Customise page (Settings): the real thing,
// live. The island's screen is captured and cropped to what the page changes:
// the island (following its state and size), the pop-ups' corner, or the bar
// (on its side, in two halves). Nothing is redrawn, so it can't disagree
// with what's on screen. The buttons make the island or the pop-ups act out
// a state (Look.tryIt), so you can watch it in the preview as you change it.
Rectangle {
    id: root
    property string page: ""
    readonly property var v: Look.v
    readonly property ShellScreen scr: Quickshell.screens.find(s => s.name === Settings.home) ?? Quickshell.screens[0]
    readonly property real sw: scr?.width ?? 1920
    readonly property real sh: scr?.height ?? 1080
    readonly property real dpr: scr?.devicePixelRatio ?? 1
    // capturing only while it's on screen
    readonly property bool live: visible && SettingsApp.open
    width: parent?.width ?? 0
    height: 236
    radius: 16
    clip: true
    color: Qt.alpha(Theme.text, 0.045)
    border.width: 1
    border.color: Qt.alpha(Theme.text, 0.05)

    // the screen, captured (drawn only through the crops below)
    ScreencopyView {
        id: grab
        captureSource: root.scr
        live: root.live
        width: root.sw
        height: root.sh
        visible: false
    }

    // a part of the screen (r, logical px), shown at zoom z
    component Crop: ShaderEffectSource {
        property rect r
        property real zoom: 1
        sourceItem: grab
        hideSource: true
        live: true
        sourceRect: r
        textureSize: Qt.size(Math.max(1, Math.round(r.width * root.dpr)), Math.max(1, Math.round(r.height * root.dpr)))
        width: r.width * zoom
        height: r.height * zoom
        smooth: true
    }

    Rectangle {
        id: view
        x: 16; y: 16
        width: parent.width - 32 - side.width - 16
        height: parent.height - 32
        radius: 12
        clip: true
        color: Theme.frame

        // ── the island (and the motion / look pages): the top middle, framed
        // round the island's size now, gliding as it changes state ──
        Item {
            id: islandView
            visible: root.page !== "popups" && root.page !== "bar"
            anchors.fill: parent
            // the island plus room round it (the frame's melt, the glow), kept to the view's shape
            readonly property real wantW: Math.max(IslandShape.w + 220, 460)
            readonly property real wantH: Math.max(IslandShape.h + root.v.frameThickness / root.dpr + 70, 120)
            readonly property real zoom: Math.max(0.05, Math.min(2, view.width / wantW, view.height / wantH))
            property real cw: Math.max(1, view.width / zoom)
            property real ch: Math.max(1, view.height / zoom)
            Behavior on cw { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            Behavior on ch { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            Crop {
                r: Qt.rect((root.sw - islandView.cw) / 2, 0, islandView.cw, islandView.ch)
                zoom: view.width / islandView.cw
            }
        }

        // ── the pop-ups: the top right corner ──
        Item {
            visible: root.page === "popups"
            anchors.fill: parent
            // the pop-ups' width and room for a stack of three below the top edge
            readonly property real zoom: Math.max(0.05, Math.min(view.width / (root.v.popWidth + 90), view.height / 380))
            readonly property real cw: view.width / zoom
            Crop {
                r: Qt.rect(root.sw - parent.cw, 0, parent.cw, view.height / parent.zoom)
                zoom: parent.zoom
            }
        }

        // ── the bar: on its side, its top half above its bottom half ──
        Column {
            visible: root.page === "bar"
            anchors.centerIn: parent
            spacing: 14
            Repeater {
                model: [0, 1]
                Item {
                    id: half
                    required property int modelData
                    readonly property real thick: 40 + root.v.frameThickness / root.dpr + 8
                    readonly property real len: root.sh / 2
                    readonly property real zoom: Math.max(0.05, Math.min(view.width / len, (view.height - 14) / 2 / thick))
                    width: len * zoom
                    height: thick * zoom
                    Crop {
                        r: Qt.rect(0, half.modelData * half.len, half.thick, half.len)
                        zoom: half.zoom
                        // turned a quarter, so the bar's top is at the left
                        transformOrigin: Item.TopLeft
                        rotation: -90
                        y: half.thick * half.zoom
                    }
                }
            }
        }

        // tucked: there's nothing to see up there
        Rectangle {
            visible: root.page !== "popups" && root.page !== "bar" && IslandShape.state === "tucked"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            width: tk.implicitWidth + 20; height: 24; radius: 12
            color: Qt.alpha(Theme.frame, 0.85)
            Text { id: tk; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: Theme.caption; color: Theme.subtext; text: "Tucked away: something's fullscreen on that screen" }
        }
        Text {
            visible: root.page === "bar"
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
            font.family: Theme.font; font.pixelSize: Theme.tiny; color: Theme.subtext
            text: "top  →  bottom"
        }
    }

    // ── the side: what's showing, and acting out a state ──
    Column {
        id: side
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 16
        width: 176
        spacing: 8
        Row {
            spacing: 6
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 3.5
                color: root.live ? Theme.tone("error") : Theme.subtext
                SequentialAnimation on opacity { running: root.live; loops: Animation.Infinite; NumberAnimation { to: 0.3; duration: 900 } NumberAnimation { to: 1; duration: 900 } }
            }
            Text {
                font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium; color: Theme.subtext
                text: "LIVE · " + (root.page === "popups" ? "POP-UPS" : root.page === "bar" ? "THE BAR" : "ISLAND: " + ({ rest: "RESTING", activity: "POP-UP", open: "OPEN", media: "MUSIC", tucked: "TUCKED", launcher: "LAUNCHER", overview: "OVERVIEW", update: "UPDATES", passkey: "PASSWORD", voice: "VOICE" }[IslandShape.state] ?? IslandShape.state.toUpperCase()))
            }
        }
        Text { visible: root.page !== "bar"; topPadding: 2; font.family: Theme.font; font.pixelSize: Theme.caption; color: Theme.subtext; text: "Show it:" }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: root.page === "island" ? [["rest", "Resting"], ["notif", "Alert"], ["volume", "Level"], ["toast", "Toast"], ["media", "Music"], ["dashboard", "Open"]]
                    : root.page === "popups" ? [["popup", "One pop-up"], ["popups", "A stack"]]
                    : root.page === "motion" ? [["dashboard", "Open / close"], ["volume", "Level"], ["notif", "Alert"]]
                    : root.page === "look" ? [["rest", "Resting"], ["toast", "Toast"], ["dashboard", "Open"]]
                    : []
                Rectangle {
                    id: tb
                    required property var modelData
                    width: tl.implicitWidth + 20; height: 26; radius: 13
                    color: Qt.alpha(Theme.tone("action"), tma.containsMouse ? 0.28 : 0.16)
                    Text { id: tl; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium; color: Theme.tone("action"); text: tb.modelData[1] }
                    MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Look.tryIt(tb.modelData[0]) }
                }
            }
        }
        Text {
            visible: root.page === "bar"
            width: parent.width; wrapMode: Text.Wrap
            font.family: Theme.font; font.pixelSize: Theme.caption; color: Theme.subtext
            text: "Your bar as it is now, turned on its side. Hidden buttons leave it as you toggle them."
        }
    }
}
