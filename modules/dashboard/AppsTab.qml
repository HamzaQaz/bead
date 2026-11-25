pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services
import "../../services/pkgs.js" as Pkgs
import "../../services/demo.js" as DemoData

// Apps: what's installed, by when you last opened it (from the launcher),
// size or name; open one, or uninstall it (bead's installer: a second click
// within 4 s confirms). Beside it, the updates waiting and a way into the
// launcher's "+" search to install more.
Item {
    id: root

    property string sortBy: "used"
    // demo mode: a few well-known apps, not everything you have
    readonly property var apps: Pkgs.sortApps((Demo.on ? Apps.all.filter(e => DemoData.apps.includes(e.name)) : Apps.all).map(e => Packages.appInfo(e)), sortBy)
    property real now: Date.now()
    onVisibleChanged: if (visible) { now = Date.now(); Packages.refreshInstalled(); }

    property string armed: ""   // the app whose Uninstall was pressed once
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }
    function uninstall(a: var): void {
        if (Demo.on) return;
        if (armed !== a.e.id) { armed = a.e.id; disarm.restart(); return; }
        armed = "";
        Packages.ownerOf(a.e.id, o => { o.title = a.name; Packages.remove(o); });
    }

    // ── installed ──
    Card {
        id: list
        width: parent.width - side.width - 14
        height: parent.height

        Row {
            x: 18; y: 14
            spacing: 10
            Label { text: "Apps · " + root.apps.length; font.pixelSize: 13; color: Theme.text; anchors.verticalCenter: parent.verticalCenter }
        }
        Choice {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 10
            options: [{ v: "used", t: "Last opened" }, { v: "size", t: "Size" }, { v: "name", t: "Name" }]
            value: root.sortBy
            onChose: v => root.sortBy = v
        }

        ListView {
            id: view
            x: 8; y: 48
            width: parent.width - 16
            height: parent.height - 56
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.apps
            delegate: Rectangle {
                id: app
                required property var modelData
                readonly property bool armed: root.armed === modelData.e.id
                width: view.width
                height: 46
                radius: 12
                color: Qt.alpha(Theme.text, hov.hovered ? 0.05 : 0)
                HoverHandler { id: hov }

                Image {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    sourceSize: Qt.size(56, 56)
                    source: Apps.iconPath(app.modelData.e.icon)
                    asynchronous: true
                }
                Column {
                    x: 50
                    width: parent.width - 50 - acts.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.text
                        text: app.modelData.name
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 10
                        color: Theme.subtext
                        text: [app.modelData.source === "flathub" ? "Flatpak" : app.modelData.pkg, Pkgs.size(app.modelData.size),
                               Pkgs.ago(app.modelData.used, root.now)].filter(Boolean).join(" · ")
                    }
                }
                Row {
                    id: acts
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    // quiet until the mouse is on the row (still there for the keyboard ring)
                    opacity: hov.hovered || app.armed ? 1 : 0.4
                    Action { text: "Open"; glyph: "open_in_new"; onHit: Apps.launch(app.modelData.e) }
                    Action {
                        visible: app.modelData.source !== ""
                        text: app.armed ? "Uninstall?" : "Uninstall"
                        glyph: "delete"
                        accent: app.armed
                        onHit: root.uninstall(app.modelData)
                    }
                }
            }
        }
    }

    // ── updates, and getting more ──
    Card {
        id: side
        anchors.right: parent.right
        width: 250
        height: parent.height

        Column {
            x: 18; y: 16
            width: parent.width - 36
            spacing: 10
            Row {
                spacing: 8
                Icon { name: "system_update_alt"; size: 18; fill: 1; color: Updates.restart ? Theme.tone("warning") : Theme.tone("action"); anchors.verticalCenter: parent.verticalCenter }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 13
                    color: Theme.text
                    text: Updates.checking ? "Checking…" : !Updates.checked ? "Not checked yet" : Updates.count === 0 ? "Up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates")
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 11
                color: Updates.restart ? Theme.tone("warning") : Theme.subtext
                text: !Updates.checked ? "Looks a couple of minutes after start, then every 3 hours." : Updates.count === 0 ? "Looks every 3 hours."
                    : [Updates.repo.length ? Updates.repo.length + " repo" : "", Updates.aur.length ? Updates.aur.length + " AUR" : "", Updates.flatpak.length ? Updates.flatpak.length + " Flatpak" : ""].filter(Boolean).join(" · ")
                      + (Updates.restart ? ". Restart after: " + Updates.items.filter(u => u.restart).map(u => u.name).join(", ") : "")
            }
            Row {
                spacing: 8
                Action { text: "Check"; glyph: "refresh"; onHit: Updates.check() }
                Action { visible: Updates.count > 0; accent: true; text: "Update"; glyph: "download"; onHit: Updates.update() }
            }
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.text, 0.07) }
            Label { text: "Get more"; font.pixelSize: 13; color: Theme.text }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.subtext
                text: "The App Store: the repos, Flathub and the AUR in one search, with picks by category."
            }
            Action {
                text: "App Store"
                glyph: "storefront"
                accent: true
                onHit: {
                    Store.show("");
                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "dashboard", "close"]);
                }
            }
        }
    }
}
