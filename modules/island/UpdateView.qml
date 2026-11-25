pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services
import "../../services/sysupdate.js" as U
import "../../services/reboot.js" as R

// The island as the system updater (services/Updates.qml): first the AUR
// packages, each with a link to its changes, to look at before anything is
// built; then the app being updated with its icon, how far along it is, and
// the output on demand ("Details"); then how it went. Hide keeps it running
// (the bar's updates button brings it back). Passwords are asked in the
// island's password prompt (services/Polkit.qml), between these.
Item {
    id: root
    readonly property real wantW: 400
    readonly property real wantH: body.implicitHeight + 32
    property bool details: false
    // the restart: picking a custom time
    property bool picking: false
    property int pickH: 3
    property int pickM: 0
    onPhaseChanged: picking = false
    function nudge(by: int): void { const t = R.step(pickH, pickM, by); pickH = t[0]; pickM = t[1]; }
    readonly property string phase: Updates.phase

    // the app a package belongs to: its desktop entry's icon, else a glyph
    function entry(name: string): var {
        if (!name) return null;
        return DesktopEntries.heuristicLookup(name) ?? DesktopEntries.heuristicLookup(U.pretty(name)) ?? null;
    }
    readonly property var app: Updates.job ? null : entry(Updates.current)
    readonly property string appIcon: Updates.job ? (Updates.job.icon || "") : app?.icon ? Apps.iconPath(app.icon) : ""
    // installing one app (the App Store): what it's doing, in words
    readonly property var ij: Updates.job
    readonly property string ijFrom: !ij ? "" : ij.source === "flathub" ? "Flathub" : ij.source === "aur" ? "the AUR" : "the repos"
    // a rollback (the update history's Undo) is a job too, worded as one
    readonly property bool rb: ij?.source === "rollback"

    component Btn: Rectangle {
        id: b
        property string text: ""
        property string glyph: ""
        property bool main: false
        signal hit()
        width: row.implicitWidth + 28
        height: 30
        radius: 15
        color: main ? Theme.tone("action") : Qt.alpha(Theme.text, bma.containsMouse ? 0.12 : 0.07)
        scale: bma.pressed ? 0.95 : 1
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: !!b.glyph; anchors.verticalCenter: parent.verticalCenter; name: b.glyph; size: 15; fill: 1; color: b.main ? Theme.frame : Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: b.main ? Theme.frame : Theme.text
                text: b.text
            }
        }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.hit() }
    }
    component Title: Text {
        font.family: Theme.font
        font.pixelSize: 15
        font.weight: Font.Bold
        color: Theme.text
        elide: Text.ElideRight
    }
    component Sub: Text {
        font.family: Theme.font
        font.pixelSize: 12
        color: Theme.subtext
        elide: Text.ElideRight
    }

    Column {
        id: body
        x: 22
        y: 16
        width: parent.width - 44
        spacing: 12

        // ── review: the AUR changes, then go ──
        Column {
            width: parent.width
            spacing: 10
            visible: root.phase === "review"
            Row {
                spacing: 12
                Rectangle {
                    width: 40; height: 40; radius: 20
                    color: Qt.alpha(Theme.tone("action"), 0.15)
                    Icon { anchors.centerIn: parent; name: "system_update_alt"; size: 22; fill: 1; color: Theme.tone("action") }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: body.width - 52
                    Title { width: parent.width; text: "Update " + Updates.count + (Updates.count === 1 ? " package" : " packages") }
                    Sub {
                        width: parent.width
                        text: Updates.trustChecking ? "Checking the " + Updates.aurNames.length + " from the AUR…"
                            : Updates.trustWorst === "danger" ? "One from the AUR looks unsafe: read why before updating"
                            : Updates.trustWorst === "caution" ? "Some from the AUR are worth a look first"
                            : Updates.aurNames.length + " from the AUR are built from their recipes: they look fine"
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: Updates.aurNames.slice(0, 5)
                    Rectangle {
                        id: aurRow
                        required property string modelData
                        // bead's check of it (services/trust.js): a tag, and why when it's not fine
                        readonly property var t: Updates.trust[modelData] ?? null
                        readonly property string level: t?.level ?? ""
                        readonly property color tone: level === "danger" ? Theme.tone("error") : level === "caution" ? Theme.tone("warning") : Theme.tone("success")
                        width: body.width
                        height: level && level !== "ok" ? 30 + why.implicitHeight + 6 : 30
                        radius: 10
                        color: Qt.alpha(Theme.text, arMa.containsMouse ? 0.08 : 0.04)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: aurName
                            x: 12
                            y: 15 - height / 2
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Theme.text
                            text: aurRow.modelData
                        }
                        Rectangle {
                            visible: aurRow.level !== ""
                            x: 12 + aurName.implicitWidth + 8
                            y: 15 - height / 2
                            width: tag.implicitWidth + 12; height: 17; radius: 8.5
                            color: Qt.alpha(aurRow.tone, 0.16)
                            Text {
                                id: tag
                                anchors.centerIn: parent
                                font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                                color: aurRow.tone
                                text: aurRow.level === "danger" ? "Risky" : aurRow.level === "caution" ? "Check it" : "Looks fine"
                            }
                        }
                        Text {
                            id: why
                            visible: aurRow.level !== "" && aurRow.level !== "ok"
                            x: 12; y: 28
                            width: parent.width - 24
                            wrapMode: Text.Wrap
                            font.family: Theme.font; font.pixelSize: 11
                            color: aurRow.tone
                            text: (aurRow.t?.reasons ?? []).join(" · ")
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            y: 15 - height / 2
                            spacing: 4
                            Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 11; color: Theme.tone("action"); text: "Changes" }
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "open_in_new"; size: 13; color: Theme.tone("action") }
                        }
                        MouseArea { id: arMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(Updates.aurLink(aurRow.modelData)) }
                    }
                }
                Sub { visible: Updates.aurNames.length > 5; x: 12; text: "and " + (Updates.aurNames.length - 5) + " more" }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Btn { text: "Cancel"; onHit: Updates.cancel() }
                // something risky: skipping the AUR is the main choice, updating it all is "anyway"
                Btn { visible: Updates.trustWorst === "danger" && Updates.count > Updates.aurNames.length; text: "Skip the AUR"; glyph: "download"; main: true; onHit: Updates.start(false) }
                Btn { text: Updates.trustWorst === "danger" ? "Update anyway" : "Update"; glyph: "download"; main: Updates.trustWorst !== "danger"; onHit: Updates.start() }
            }
        }

        // ── running: the app, how far along, the output ──
        Column {
            width: parent.width
            spacing: 12
            visible: root.phase === "running"
            Row {
                spacing: 14
                Item {
                    id: iconBox
                    width: 44; height: 44
                    // a new app pops in
                    property string shownFor: ""
                    Connections {
                        target: Updates
                        function onCurrentChanged(): void { if (Updates.current && Updates.current !== iconBox.shownFor) { iconBox.shownFor = Updates.current; pop.restart(); } }
                    }
                    SequentialAnimation {
                        id: pop
                        NumberAnimation { target: iconBox; property: "scale"; to: 0.75; duration: 90; easing.type: Easing.InQuad }
                        NumberAnimation { target: iconBox; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: Qt.alpha(Theme.tone("action"), 0.13)
                        visible: !img.visible
                        Icon {
                            anchors.centerIn: parent
                            name: Updates.stage === "flatpak" ? "deployed_code_update" : Updates.doing === "downloading" ? "download" : Updates.doing === "building" ? "construction" : "deployed_code"
                            size: 22; fill: 1
                            color: Theme.tone("action")
                        }
                    }
                    IconImage {
                        id: img
                        anchors.fill: parent
                        source: root.appIcon
                        visible: !!root.appIcon && status === Image.Ready
                        asynchronous: true
                    }
                }
                Column {
                    anchors.verticalCenter: iconBox.verticalCenter
                    width: body.width - 58
                    spacing: 2
                    Title {
                        width: parent.width
                        text: root.rb ? (Updates.inst.phase === "auth" ? "Waiting for your password" : "Rolling back " + root.ij.title)
                            : root.ij ? ({ auth: "Waiting for your password", download: "Downloading ", build: "Building ", install: "Installing " }[Updates.inst.phase] ?? "Installing ") + (Updates.inst.phase === "auth" ? "" : root.ij.title)
                            : !Updates.current ? (Updates.stage === "aur" ? "Building from the AUR…" : Updates.stage === "flatpak" ? "Updating Flatpaks…" : "Getting ready…")
                            : (Updates.doing === "downloading" ? "Downloading " : Updates.doing === "building" ? "Building " : Updates.doing === "installing" ? "Installing " : "Updating ")
                              + (root.app?.name || U.pretty(Updates.current))
                    }
                    Sub {
                        width: parent.width
                        text: root.rb ? (Updates.inst.phase === "auth" ? "To roll back " + root.ij.title
                                : "From the package cache" + (Updates.inst.n > 1 ? " · " + Updates.inst.n + " packages" : "") + " · " + Math.round(Updates.progress * 100) + "%")
                            : root.ij ? (Updates.inst.phase === "auth" ? "To install " + root.ij.title + " from " + root.ijFrom
                                : "From " + root.ijFrom + (Updates.inst.n > 1 ? " · " + Updates.inst.n + " packages" : "") + " · " + Math.round(Updates.progress * 100) + "%")
                            : (Updates.stage === "aur" ? "AUR" : Updates.stage === "flatpak" ? "Flatpak" : "Packages")
                            + (Updates.stepN > 0 ? " · " + Updates.stepI + " of " + Updates.stepN : "")
                            + " · " + Math.round(Updates.progress * 100) + "%"
                    }
                }
            }
            // the bar: glides to each new value, and a sheen runs along it
            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Qt.alpha(Theme.text, 0.08)
                clip: true
                Rectangle {
                    id: fill
                    height: parent.height
                    radius: 3
                    width: Math.max(height, parent.width * Updates.progress)
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    color: Theme.tone("action")
                    Rectangle {
                        width: 40; height: parent.height
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.alpha("white", 0.35) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        NumberAnimation on x { running: root.phase === "running"; loops: Animation.Infinite; from: -40; to: fill.width; duration: 1400 }
                    }
                }
            }
            // the output, like a terminal: the last lines, following along
            Rectangle {
                width: parent.width
                height: root.details ? 150 : 0
                visible: height > 0.5
                Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                radius: 12
                color: Qt.alpha("black", 0.35)
                clip: true
                ListView {
                    id: logView
                    anchors.fill: parent
                    anchors.margins: 10
                    model: Updates.log
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: positionViewAtEnd()
                    delegate: Text {
                        required property string modelData
                        width: logView.width
                        elide: Text.ElideRight
                        font.family: "monospace"
                        font.pixelSize: 10
                        color: /^error|ERROR/.test(modelData) ? Theme.tone("error") : Qt.alpha(Theme.text, 0.75)
                        text: modelData
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Btn { text: root.details ? "Less" : "Details"; glyph: "terminal"; onHit: root.details = !root.details }
                Btn { text: "Hide"; onHit: Updates.hide() }
            }
        }

        // ── how it went ──
        Column {
            width: parent.width
            spacing: 12
            visible: root.phase === "done" || root.phase === "failed"
            readonly property bool ok: root.phase === "done"
            Row {
                spacing: 14
                Rectangle {
                    id: resIcon
                    width: 44; height: 44; radius: 22
                    color: Qt.alpha(parent.parent.ok ? Theme.tone("success") : Theme.tone("error"), 0.15)
                    scale: parent.parent.visible ? 1 : 0.5
                    Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                    Icon { anchors.centerIn: parent; name: resIcon.parent.parent.ok ? "check_circle" : "error"; size: 24; fill: 1; color: resIcon.parent.parent.ok ? Theme.tone("success") : Theme.tone("error") }
                }
                Column {
                    anchors.verticalCenter: resIcon.verticalCenter
                    width: body.width - 58
                    spacing: 2
                    Title {
                        width: parent.width
                        text: root.rb ? (parent.parent.parent.ok ? "Rolled back " + root.ij.title : "Couldn't roll back " + root.ij.title)
                            : root.ij ? (parent.parent.parent.ok ? root.ij.title + " is installed" : "Couldn't install " + root.ij.title)
                            : !parent.parent.parent.ok ? "The update stopped"
                            : Updates.rebootAt ? "Restart scheduled"
                            : Updates.needsRestart ? "Restart to finish" : "All up to date"
                    }
                    Sub {
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        text: root.rb ? (parent.parent.parent.ok ? (root.ij.held ? "Held at the older version: updates skip it until a newer one is out" : "The older versions are back") : Updates.error || "It stopped")
                            : root.ij ? (parent.parent.parent.ok ? "From " + root.ijFrom : Updates.error || "It stopped")
                            : parent.parent.parent.ok
                            ? (Updates.rebootAt ? Updates.rebootLabel + " · a reminder comes 5 minutes before"
                               : Updates.needsRestart ? "Updated " + (Updates.updated.filter(n => /^(linux|systemd|glibc|nvidia|mesa|amd-ucode|intel-ucode|dbus|wayland|hyprland)/.test(n)).slice(0, 3).join(", ") || "core system packages") + ": they take effect after a restart"
                               : Updates.updated.length + (Updates.updated.length === 1 ? " package updated" : " packages updated"))
                            : (Updates.failedStage ? (Updates.failedStage === "aur" ? "AUR" : Updates.failedStage === "flatpak" ? "Flatpak" : "Packages") + ": " : "") + Updates.error
                    }
                }
            }
            // a restart wanted: now, tonight, or a time you pick
            readonly property bool asks: root.phase === "done" && Updates.needsRestart && !Updates.rebootAt
            Row {
                visible: parent.asks && !root.picking
                width: parent.width
                spacing: 8
                Btn { text: "Restart now"; glyph: "restart_alt"; main: true; onHit: Updates.rebootNow() }
                Btn { text: "Tonight 3:00"; glyph: "bedtime"; onHit: Updates.scheduleReboot(3, 0) }
                Btn { text: "Pick a time"; glyph: "schedule"; onHit: { const t = R.step(new Date().getHours(), 0, 60); root.pickH = t[0]; root.pickM = t[1]; root.picking = true; } }
            }
            // the custom time: − 23:15 +, in 15-minute steps (or scroll)
            Row {
                visible: parent.asks && root.picking
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Btn { glyph: "remove"; onHit: root.nudge(-15) }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 26
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        text: root.pickH + ":" + String(root.pickM).padStart(2, "0")
                        WheelHandler { onWheel: e => root.nudge(e.angleDelta.y > 0 ? 15 : -15) }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.subtext
                        text: R.label(R.next(root.pickH, root.pickM, new Date()), new Date())
                    }
                }
                Btn { glyph: "add"; onHit: root.nudge(15) }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Btn { visible: root.phase === "done" && !!root.ij && !root.rb; text: "Open"; glyph: "open_in_new"; main: true; onHit: { const j = root.ij; Updates.hide(); Store.openApp(j); } }
                Btn { visible: root.phase === "failed" && !root.ij; text: "Open in a terminal"; glyph: "terminal"; onHit: Updates.terminal() }
                Btn { visible: parent.parent.asks && root.picking; text: "Back"; onHit: root.picking = false }
                Btn { visible: parent.parent.asks && root.picking; text: "Schedule"; glyph: "schedule"; main: true; onHit: { Updates.scheduleReboot(root.pickH, root.pickM); root.picking = false; } }
                Btn { visible: root.phase === "done" && !!Updates.rebootAt; text: "Cancel restart"; onHit: Updates.cancelReboot() }
                Btn { visible: root.phase === "done" && !!Updates.rebootAt; text: "Restart now"; glyph: "restart_alt"; onHit: Updates.rebootNow() }
                Btn { visible: !(parent.parent.asks && root.picking); text: parent.parent.asks ? "Later" : "Close"; main: root.phase === "done" && !parent.parent.asks && !Updates.rebootAt && !root.ij; onHit: Updates.hide() }
            }
        }
    }
}
