pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// The island as keyhold's passkey prompt: site and account, a password field,
// Approve / Deny. Enter approves, Esc denies. While the password is checked it
// says so; a wrong one shakes and says how many tries are left. Approved or
// cancelled, it shows a short result before the island shrinks back.
Item {
    id: root

    readonly property bool result: Passkey.st === "success" || Passkey.st === "cancelled"
    readonly property real wantW: result ? resultRow.implicitWidth + 48 : 400
    readonly property real wantH: result ? 46 : (Passkey.st === "error" ? 190 : 170)

    function focusField(): void { field.forceActiveFocus(); }

    // ── asking ──
    Item {
        id: ask
        anchors.fill: parent
        opacity: root.result ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }

        property real shakeX: 0
        SequentialAnimation {
            id: shake
            NumberAnimation { target: ask; property: "shakeX"; to: -9; duration: 50 }
            NumberAnimation { target: ask; property: "shakeX"; to: 8; duration: 70 }
            NumberAnimation { target: ask; property: "shakeX"; to: -5; duration: 60 }
            NumberAnimation { target: ask; property: "shakeX"; to: 3; duration: 60 }
            NumberAnimation { target: ask; property: "shakeX"; to: 0; duration: 60 }
        }
        Connections { target: Passkey; function onShake() { shake.restart(); } }

        Column {
            x: 22 + ask.shakeX
            y: 16
            width: parent.width - 44
            spacing: 10

            Row {
                spacing: 10
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: Qt.alpha(Theme.tone("action"), 0.15)
                    Icon { anchors.centerIn: parent; name: "passkey"; size: 18; fill: 1; color: Theme.tone("action") }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: Passkey.registering ? "Create a passkey" : "Sign in with a passkey"
                    }
                    Label {
                        font.pixelSize: 11
                        textFormat: Text.StyledText
                        text: (Passkey.registering ? "for " : "to ")
                            + "<font color='" + Theme.text + "'>" + (Passkey.req?.rpId ?? "") + "</font>"
                            + (Passkey.req?.user ? " as " + Passkey.req.user : "")
                    }
                }
            }

            // password
            Rectangle {
                width: parent.width
                height: 38
                radius: 19
                color: Qt.alpha(Theme.text, 0.06)
                border.width: 1
                border.color: Passkey.st === "error" ? Qt.alpha(Theme.tone("error"), 0.7)
                    : field.activeFocus ? Qt.alpha(Theme.tone("action"), 0.5) : "transparent"
                Behavior on border.color { ColorAnimation { duration: 150 } }
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                    enabled: Passkey.st !== "checking"
                    clip: true
                    Keys.onReturnPressed: { Passkey.submit(text); text = ""; }
                    Keys.onEnterPressed: { Passkey.submit(text); text = ""; }
                    Keys.onEscapePressed: Passkey.deny()
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !field.text && !field.preeditText
                        text: Passkey.st === "checking" ? "Checking…" : "Your password"
                    }
                }
            }

            Label {
                visible: Passkey.st === "error"
                font.pixelSize: 11
                color: Theme.tone("error")
                text: Passkey.errorText
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                Repeater {
                    model: [{ t: "Deny", main: false }, { t: Passkey.registering ? "Create" : "Approve", main: true }]
                    Rectangle {
                        id: b
                        required property var modelData
                        width: bt.implicitWidth + 32
                        height: 32
                        radius: 16
                        opacity: Passkey.st === "checking" ? 0.5 : 1
                        color: modelData.main ? Theme.tone("action") : Qt.alpha(Theme.text, bma.containsMouse ? 0.12 : 0.07)
                        scale: bma.pressed ? 0.94 : 1
                        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: bt
                            anchors.centerIn: parent
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: b.modelData.main ? Theme.frame : Theme.text
                            text: b.modelData.t
                        }
                        MouseArea {
                            id: bma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!b.modelData.main) Passkey.deny();
                                else { Passkey.submit(field.text); field.text = ""; }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── result ──
    Row {
        id: resultRow
        anchors.centerIn: parent
        spacing: 10
        opacity: root.result ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220 } }
        readonly property bool ok: Passkey.st === "success"
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: resultRow.ok ? "check_circle" : "cancel"
            size: 20
            fill: 1
            color: resultRow.ok ? Theme.tone("success") : Theme.subtext
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.text
            text: resultRow.ok ? (Passkey.registering ? "Passkey created" : "Signed in") : "Cancelled"
        }
    }
}
