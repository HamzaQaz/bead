pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// What the lock screen shows: your wallpaper (the windows fade away); a big
// clock and the date; a password pill (dots pop in as you type, it shakes on
// a wrong password); weather, notifications and what's playing.
Item {
    id: root
    required property ShellScreen screen
    // the lock UI goes on the main monitor (the island's); others just blur.
    // Every screen keeps a password field, since keyboard focus lands on
    // whichever monitor is focused.
    readonly property bool main: screen?.name === Settings.home

    // ── motion: one clock (enter, 0-1 over 1.1 s) staged per element, and
    // one for leaving on success (0-1), so everything moves as a sequence ──
    property real enter: 0
    property real leave: 0
    NumberAnimation on enter { from: 0; to: 1; duration: 1100; running: true }
    NumberAnimation { id: leaveAnim; target: root; property: "leave"; from: 0; to: 1; duration: 440 }
    Component.onCompleted: field.forceActiveFocus()
    Connections {
        target: Lock
        function onStChanged() { if (Lock.st === "success") leaveAnim.restart(); }
    }
    function ease(t: real): real { t = Math.max(0, Math.min(1, t)); return 1 - Math.pow(1 - t, 4); }
    // how far in an element is: it enters between a and b (fractions of the
    // entrance), and everything leaves together
    function stage(a: real, b: real): real { return ease((enter - a) / (b - a)) * (1 - ease(leave * 1.15)); }
    readonly property real bg: ease(enter / 0.6) * (1 - ease(leave))

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // ── background: your windows fade away to the wallpaper (Caelestia's
    // still of it), lightly blurred; they fade back in as you unlock. No
    // wallpaper file: the screen itself, blurred enough to hide text. ──
    property string wallPath: ""
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/caelestia/wallpaper/path.txt"
        blockLoading: true
        printErrors: false
        onLoaded: root.wallPath = text().trim()
    }
    ScreencopyView {
        id: copy
        anchors.fill: parent
        captureSource: root.screen
        live: false
    }
    Image {
        id: wall
        anchors.fill: parent
        visible: false
        source: root.wallPath ? "file://" + root.wallPath : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        sourceSize: Qt.size(root.width, root.height)
    }
    readonly property bool hasWall: wall.status === Image.Ready
    MultiEffect {
        anchors.fill: parent
        source: root.hasWall ? wall : copy
        opacity: root.hasWall ? root.bg : 1
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: root.hasWall ? 32 : 64
        blur: root.hasWall ? 0.35 : 0.85 * root.bg
        brightness: -0.06 * root.bg
    }
    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.frame, 0.12 * root.bg) }

    // ── the password, typed into an invisible field ──
    TextInput {
        id: field
        visible: false
        focus: true
        echoMode: TextInput.Password
        enabled: Lock.st !== "checking" && Lock.st !== "success"
        onTextChanged: { Lock.password = text; if (text && Lock.st === "error") Lock.st = "idle"; }
        Keys.onReturnPressed: Lock.submit()
        Keys.onEnterPressed: Lock.submit()
        Keys.onEscapePressed: { if (Lock.preview && !Lock.locked) Lock.leave(); else text = ""; }
        Connections {
            target: Lock
            function onPasswordChanged() { if (!Lock.password && field.text) field.text = ""; }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

    Item {
        id: content
        anchors.fill: parent
        visible: root.main
        // a soft shadow keeps text readable over a lighter screen
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowBlur: 0.8
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }

        // ── clock and date ──
        Column {
            id: clockCol
            readonly property real t: root.stage(0.08, 0.75)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.22 - 28 * (1 - t)
            opacity: t
            scale: 0.94 + 0.06 * t
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font
                font.pixelSize: 118
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Theme.text
                text: Qt.formatTime(clock.date, "hh:mm")
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font
                font.pixelSize: 20
                font.weight: Font.Medium
                color: Qt.alpha(Theme.text, 0.85)
                text: Qt.formatDate(clock.date, "dddd, d MMMM")
            }
            // what's running: a call (mute from here), a recording, a timer
            Item { width: 1; height: 16; visible: lockLive.visible }
            LiveActivities {
                id: lockLive
                anchors.horizontalCenter: parent.horizontalCenter
                // one centred line: as wide as the chips that show
                width: {
                    let w = -spacing;
                    for (const c of children) if (c.visible) w += c.implicitWidth + spacing;
                    return Math.max(1, w);
                }
            }
        }

        // ── password ──
        Column {
            readonly property real t: root.stage(0.22, 0.88)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.56 + 22 * (1 - t)
            opacity: t
            spacing: 12

            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340
                height: 56
                radius: 28
                color: Qt.alpha(Theme.frame, 0.8)
                border.width: 1.5
                border.color: Lock.st === "error" ? Theme.tone("error")
                    : field.activeFocus ? Qt.alpha(Theme.tone("action"), 0.45) : "transparent"
                Behavior on border.color { ColorAnimation { duration: 180 } }

                property real shakeX: 0
                transform: Translate { x: pill.shakeX }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: pill; property: "shakeX"; to: -11; duration: 60; easing.type: Easing.OutSine }
                    NumberAnimation { target: pill; property: "shakeX"; to: 9; duration: 90; easing.type: Easing.InOutSine }
                    NumberAnimation { target: pill; property: "shakeX"; to: -5; duration: 80; easing.type: Easing.InOutSine }
                    NumberAnimation { target: pill; property: "shakeX"; to: 2; duration: 70; easing.type: Easing.InOutSine }
                    NumberAnimation { target: pill; property: "shakeX"; to: 0; duration: 60; easing.type: Easing.OutSine }
                }
                Connections { target: Lock; function onShake() { shake.restart(); } }

                // you
                ClippingRectangle {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 18
                    color: Qt.alpha(Theme.tone("action"), 0.2)
                    Text {
                        anchors.centerIn: parent
                        visible: face.status !== Image.Ready
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Theme.tone("action")
                        text: Session.user.charAt(0).toUpperCase()
                    }
                    Image {
                        id: face
                        anchors.fill: parent
                        source: "file://" + Quickshell.env("HOME") + "/.face"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(72, 72)
                    }
                }

                // dots, or what's going on
                Item {
                    x: 56
                    width: parent.width - 56 - 56
                    height: parent.height
                    clip: true
                    Label {
                        anchors.centerIn: parent
                        opacity: !Lock.password || Lock.st === "checking" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        font.pixelSize: 14
                        text: Lock.st === "checking" ? "Checking…"
                            : Lock.preview && !Lock.locked ? "Preview · Enter or Esc to close" : "Enter password"
                    }
                    // a fixed row of slots: each dot grows in or out on its own and
                    // the row glides to stay centred (no rebuilding per key)
                    Row {
                        anchors.centerIn: parent
                        opacity: Lock.st === "checking" ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Repeater {
                            model: 18
                            Item {
                                id: slot
                                required property int index
                                readonly property bool on: index < Lock.password.length
                                width: on ? 16 : 0
                                height: 16
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 9; height: 9; radius: 4.5
                                    color: Theme.text
                                    scale: slot.on ? 1 : 0.2
                                    opacity: slot.on ? 1 : 0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }
                }

                // go
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 18
                    color: Lock.password || Lock.st === "checking" ? Theme.tone("action") : Qt.alpha(Theme.text, 0.08)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Icon {
                        id: goIcon
                        anchors.fill: parent
                        name: Lock.st === "checking" ? "progress_activity" : Lock.st === "success" ? "lock_open" : "arrow_forward"
                        ref: Lock.st === "checking" ? "circle" : "" // spin about the arc's centre
                        size: 19
                        color: Lock.password || Lock.st === "checking" ? Theme.frame : Theme.subtext
                        RotationAnimation on rotation {
                            running: Lock.st === "checking"
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                            onRunningChanged: if (!running) goIcon.rotation = 0
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Lock.submit() }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 16
                font.pixelSize: 13
                color: Theme.tone("error")
                opacity: Lock.st === "error" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                text: Lock.errorText
            }
        }

        // ── top corners: weather, notifications ──
        Row {
            x: 40; y: 34 - 14 * (1 - opacity)
            opacity: root.stage(0.35, 1)
            spacing: 10
            visible: Weather.ready
            Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: 26; fill: 1; color: Theme.tone("action") }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; color: Theme.text; text: Math.round(Weather.temp) + "°" }
                Label { font.pixelSize: 12; text: Weather.describe(Weather.code) }
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 40
            y: 36 - 14 * (1 - opacity)
            opacity: root.stage(0.38, 1)
            visible: Notifs.entries.length > 0
            width: notifRow.implicitWidth + 28
            height: notifRow.implicitHeight + 16
            radius: 18
            color: Qt.alpha(Theme.frame, 0.7)
            Row {
                id: notifRow
                anchors.centerIn: parent
                spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "notifications"; size: 17; fill: 1 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: Notifs.entries.length + (Notifs.entries.length === 1 ? " notification" : " notifications")
                    }
                    Label { // which apps, never what they said
                        font.pixelSize: 11
                        text: {
                            const by = {};
                            for (const e of Notifs.entries) { const a = e.appName || "Other"; by[a] = (by[a] ?? 0) + 1; }
                            const apps = Object.keys(by).sort((x, y) => by[y] - by[x]);
                            return apps.slice(0, 3).map(a => a + " " + by[a]).join("  ·  ") + (apps.length > 3 ? "  ·  +" + (apps.length - 3) : "");
                        }
                    }
                }
            }
        }

        // ── what's playing ──
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48 - 26 * (1 - opacity)
            opacity: root.stage(0.42, 1)
            visible: !!root.player && !!root.player.trackTitle
            width: 380
            height: 76
            radius: 22
            color: Qt.alpha(Theme.frame, 0.75)
            ClippingRectangle {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 52; height: 52; radius: 12
                color: Qt.alpha(Theme.text, 0.08)
                Icon { anchors.centerIn: parent; name: "music_note"; size: 22; color: Theme.subtext; visible: art.status !== Image.Ready }
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(104, 104)
                }
            }
            Column {
                x: 76
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 76 - controls.width - 20
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.text
                    text: root.player?.trackTitle ?? ""
                }
                Label { width: parent.width; elide: Text.ElideRight; text: root.player?.trackArtist ?? "" }
            }
            // how far into the track
            Rectangle {
                visible: (root.player?.length ?? 0) > 0
                x: 76
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 9
                width: parent.width - 76 - 18
                height: 3
                radius: 1.5
                color: Qt.alpha(Theme.text, 0.12)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: Theme.text
                    width: parent.width * Math.max(0, Math.min(1, (root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1)))
                    Behavior on width { NumberAnimation { duration: 900 } }
                }
                // MPRIS doesn't push the position: ask for it while playing
                Timer {
                    interval: 1000
                    repeat: true
                    running: parent.visible && Lock.shown && !!root.player?.isPlaying
                    onTriggered: root.player?.positionChanged()
                }
            }
            Row {
                id: controls
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: [
                        { g: "skip_previous", ok: root.player?.canGoPrevious, go: () => root.player.previous() },
                        { g: root.player?.isPlaying ? "pause" : "play_arrow", ok: root.player?.canTogglePlaying, go: () => root.player.togglePlaying(), main: true },
                        { g: "skip_next", ok: root.player?.canGoNext, go: () => root.player.next() }
                    ]
                    Rectangle {
                        id: cb
                        required property var modelData
                        width: 34; height: 34; radius: 17
                        opacity: modelData.ok ? 1 : 0.35
                        color: modelData.main ? Theme.tone("action") : Qt.alpha(Theme.text, cma.containsMouse ? 0.1 : 0)
                        Icon { anchors.fill: parent; name: cb.modelData.g; size: 20; fill: 1; color: cb.modelData.main ? Theme.frame : Theme.text }
                        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (cb.modelData.ok) cb.modelData.go() }
                    }
                }
            }
        }
    }
}
