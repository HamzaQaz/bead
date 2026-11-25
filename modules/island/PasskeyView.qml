pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import qs.components
import qs.config
import qs.services

// The island as a password prompt: keyhold's passkeys (services/Passkey.qml)
// and admin rights asked through polkit (services/Polkit.qml).
//
// Like signing in: your face with a badge for what's asking, what it's for,
// a password field (show/hide, a Caps Lock warning), Deny / Allow. Enter
// allows, Esc denies. While checking, a ring runs round your face; a wrong
// password shakes it red; the right one turns it green with a tick, then the
// island shrinks back.
Item {
    id: root
    // whichever is asking (an admin prompt first: it's blocking something),
    // kept after it's done: the island is still fading out, and switching
    // then flashed the other one ("Sign in with a passkey" after an admin prompt)
    property var src: Passkey
    function pick(): void { if (Polkit.active) src = Polkit; else if (Passkey.active) src = Passkey; }
    Connections { target: Polkit; function onActiveChanged(): void { root.pick(); } }
    Connections { target: Passkey; function onActiveChanged(): void { root.pick(); } }
    Component.onCompleted: pick()
    // the last real state, held while the island fades out (src.st is "" by then)
    property string st: ""
    readonly property string liveSt: src.st
    onLiveStChanged: if (liveSt) st = liveSt
    readonly property bool result: st === "success" || st === "cancelled"
    readonly property bool checking: st === "checking"
    readonly property bool wrong: st === "error"

    readonly property real wantW: 360
    readonly property real wantH: content.implicitHeight + 36

    function focusField(): void { field.forceActiveFocus(); }
    function go(): void { if (!checking) { root.src.submit(field.text); field.text = ""; } }

    property real shakeX: 0
    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeX"; to: -10; duration: 50 }
        NumberAnimation { target: root; property: "shakeX"; to: 9; duration: 70 }
        NumberAnimation { target: root; property: "shakeX"; to: -6; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 3; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 60 }
    }
    Connections { target: Passkey; function onShake() { shake.restart(); } }
    Connections { target: Polkit; function onShake() { shake.restart(); } }
    // a fresh prompt: start clean
    onSrcChanged: { field.text = ""; reveal = false; }
    property bool reveal: false

    readonly property color ringTone: st === "success" ? Theme.tone("success") : wrong ? Theme.tone("error") : Theme.tone("action")

    Column {
        id: content
        x: 24 + root.shakeX
        y: 20
        width: parent.width - 48
        spacing: 14

        // ── your face, and what's asking ──
        Item {
            id: faceBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76; height: 76
            // the ring: still while asking, running while checking, red when wrong, green when done
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                rotation: spin
                property real spin: 0
                NumberAnimation on spin { running: root.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                ShapePath {
                    strokeColor: root.ringTone
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 38; centerY: 38; radiusX: 36; radiusY: 36
                        startAngle: -90
                        sweepAngle: root.checking ? 110 : 360
                        Behavior on sweepAngle { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    }
                }
                opacity: root.checking || root.wrong || root.st === "success" ? 1 : 0.35
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Item {
                anchors.centerIn: parent
                width: 62; height: 62
                scale: root.st === "success" ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                Image {
                    id: face
                    anchors.fill: parent
                    source: "file://" + Quickshell.env("HOME") + "/.face"
                    sourceSize: Qt.size(124, 124)
                    visible: false
                }
                Rectangle { id: faceMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: parent; source: face; maskEnabled: true; maskSource: faceMask; visible: face.status === Image.Ready }
                Rectangle {
                    anchors.fill: parent; radius: width / 2
                    visible: face.status !== Image.Ready
                    color: Qt.alpha(Theme.tone("action"), 0.18)
                    Text {
                        anchors.centerIn: parent
                        font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold
                        color: Theme.tone("action")
                        text: (Session.firstName || "?").charAt(0).toUpperCase()
                    }
                }
            }
            // the badge: what's asking; a tick once it's done
            Rectangle {
                x: parent.width - width - 2; y: parent.height - height - 2
                width: 26; height: 26; radius: 13
                color: root.st === "success" ? Theme.tone("success") : root.wrong ? Theme.tone("error") : Theme.tone("action")
                Behavior on color { ColorAnimation { duration: 200 } }
                border.width: 3
                border.color: Theme.frame
                Icon {
                    anchors.centerIn: parent
                    name: root.st === "success" ? "check" : root.st === "cancelled" ? "close" : root.src.icon
                    size: 14; fill: 1
                    color: Theme.frame
                }
            }
        }

        Column {
            width: parent.width
            spacing: 3
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Theme.text
                text: root.result ? root.src.doneText : root.src.title
            }
            Text {
                width: parent.width
                visible: !root.result
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.subtext
                text: root.src.subtitle
            }
            // a passkey's account
            Text {
                width: parent.width
                visible: !root.result && !!root.src.detail && root.src === Passkey
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 11
                color: Qt.alpha(Theme.subtext, 0.8)
                text: root.src.detail
            }
        }

        // ── the password ──
        Rectangle {
            width: parent.width
            height: 42
            radius: 21
            visible: !root.result
            color: Qt.alpha(Theme.text, field.activeFocus ? 0.08 : 0.05)
            border.width: 1.5
            border.color: root.wrong ? Qt.alpha(Theme.tone("error"), 0.8)
                : field.activeFocus ? Qt.alpha(Theme.tone("action"), 0.6) : Qt.alpha(Theme.text, 0.08)
            Behavior on border.color { ColorAnimation { duration: 160 } }
            Behavior on color { ColorAnimation { duration: 160 } }
            Icon {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"; size: 17; fill: 1
                color: root.wrong ? Theme.tone("error") : Theme.subtext
            }
            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                verticalAlignment: TextInput.AlignVCenter
                echoMode: root.reveal ? TextInput.Normal : TextInput.Password
                passwordCharacter: "●"
                passwordMaskDelay: 0
                font.family: Theme.font
                font.pixelSize: root.reveal ? 14 : 11
                font.letterSpacing: root.reveal ? 0 : 3
                color: Theme.text
                selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                enabled: !root.checking
                clip: true
                cursorDelegate: Rectangle { width: 2; radius: 1; color: Theme.tone("action"); visible: field.cursorVisible }
                onTextChanged: if (root.wrong && text) root.src.errorText = ""
                Keys.onReturnPressed: root.go()
                Keys.onEnterPressed: root.go()
                Keys.onEscapePressed: root.src.deny()
            }
            Text {
                anchors.left: field.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !field.text && !field.preeditText
                font.family: Theme.font
                font.pixelSize: 13
                color: Qt.alpha(Theme.subtext, 0.8)
                text: root.checking ? "Checking…" : "Password for " + (Session.firstName || "you")
            }
            // show / hide
            Icon {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text.length > 0
                name: root.reveal ? "visibility_off" : "visibility"
                size: 17
                color: eyeMa.containsMouse ? Theme.text : Theme.subtext
                MouseArea { id: eyeMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.reveal = !root.reveal; field.forceActiveFocus(); } }
            }
        }

        // what's wrong: the password, or Caps Lock
        Item {
            width: parent.width
            height: note.text ? 16 : 0
            visible: !root.result
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Row {
                anchors.centerIn: parent
                spacing: 5
                opacity: note.text ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Icon { anchors.verticalCenter: parent.verticalCenter; name: root.wrong && root.src.errorText ? "error" : "keyboard_capslock"; size: 14; fill: 1; color: note.color }
                Text {
                    id: note
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: root.wrong && root.src.errorText ? Theme.tone("error") : Theme.tone("warning")
                    text: root.wrong && root.src.errorText ? root.src.errorText : CapsLock.on ? "Caps Lock is on" : ""
                }
            }
        }

        // ── Deny / Allow ──
        Row {
            id: buttons
            width: parent.width
            spacing: 10
            visible: !root.result
            Repeater {
                model: [{ t: "Deny", main: false }, { t: root.src.approveText, main: true }]
                Rectangle {
                    id: b
                    required property var modelData
                    width: (buttons.width - buttons.spacing) / 2
                    height: 36
                    radius: 18
                    color: modelData.main ? (bma.containsMouse ? Qt.lighter(Theme.tone("action"), 1.1) : Theme.tone("action"))
                        : Qt.alpha(Theme.text, bma.containsMouse ? 0.12 : 0.07)
                    opacity: root.checking && !modelData.main ? 0.5 : 1
                    scale: bma.pressed ? 0.95 : 1
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        opacity: b.modelData.main && root.checking ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: b.modelData.main ? Theme.frame : Theme.text
                        text: b.modelData.t
                    }
                    // checking: a small spinner in place of the word
                    Icon {
                        anchors.centerIn: parent
                        visible: b.modelData.main
                        opacity: root.checking ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        name: "progress_activity"; size: 18
                        color: Theme.frame
                        RotationAnimation on rotation { running: root.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                    }
                    MouseArea {
                        id: bma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.checking
                        onClicked: b.modelData.main ? root.go() : root.src.deny()
                    }
                }
            }
        }
    }
}
