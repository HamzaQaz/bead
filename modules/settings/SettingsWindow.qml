pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../config/sizecheck.js" as SizeCheck
import "../island/keys.js" as KeySheet
import qs.components
import qs.config
import qs.services
import qs.modules.bar
import qs.modules.dashboard

// bead's Settings: a window of its own, like a desktop's settings app. A
// sidebar of pages in four groups, with a search across every setting; the
// page on the right, in cards of rows. Changes apply at once (most are
// config/Settings.qml, saved to ~/.config/bead/settings.json).
FloatingWindow {
    id: win

    title: "bead Settings"
    implicitWidth: 1060
    implicitHeight: 720
    color: Theme.frame
    visible: true
    onVisibleChanged: if (!visible) SettingsApp.open = false

    readonly property bool searching: SettingsApp.query.trim().length > 0
    function matches(...texts): bool {
        const words = SettingsApp.query.trim().toLowerCase().split(/\s+/).filter(Boolean);
        const hay = texts.join(" ").toLowerCase();
        return words.every(w => hay.includes(w));
    }
    function go(id: string): void { SettingsApp.query = ""; SettingsApp.page = id; scroller.contentY = 0; }

    readonly property var pages: [
        { id: "wifi", s: "Connections", t: "Wi-Fi", g: "wifi", d: "Networks, and joining one", k: "network internet wireless password" },
        { id: "bluetooth", s: "Connections", t: "Bluetooth", g: "bluetooth", d: "Pairing and connecting devices", k: "headphones pair device speaker" },
        { id: "sound", s: "Device", t: "Sound", g: "volume_up", d: "Speakers, microphones and volume", k: "audio output input mic speaker headphones volume mute" },
        { id: "displays", s: "Device", t: "Displays", g: "monitor", d: "Layout, resolution, scale and brightness", k: "monitor screen resolution refresh rate brightness scale" },
        { id: "wallpaper", s: "Personal", t: "Wallpaper", g: "wallpaper", d: "Stills and live wallpapers", k: "background image picture" },
        { id: "appearance", s: "Personal", t: "Appearance", g: "palette", d: "Colours, size, the bar and the island", k: "theme tint colour color size scale bar title monitor island" },
        { id: "notifications", s: "Personal", t: "Notifications", g: "notifications", d: "Do Not Disturb and the history", k: "dnd quiet alerts history" },
        { id: "night", s: "Personal", t: "Night light", g: "nightlight", d: "A warmer screen in the evening", k: "warm blue light temperature sunset hyprsunset" },
        { id: "power", s: "System", t: "Power & idle", g: "bedtime", d: "Locking, sleeping, and game mode", k: "lock suspend sleep screen off idle game shutdown reboot log out" },
        { id: "assistant", s: "System", t: "Assistant & voice", g: "graphic_eq", d: "Claude, voice commands and dictation", k: "ai pearl claude model voice dictation microphone" },
        { id: "keyboard", s: "System", t: "Keyboard shortcuts", g: "keyboard", d: "bead's keys", k: "keybinds shortcuts hotkeys keys" },
        { id: "region", s: "System", t: "Weather & units", g: "partly_cloudy_day", d: "How temperatures show", k: "celsius fahrenheit units weather" },
        { id: "updates", s: "System", t: "Updates", g: "system_update", d: "The system's packages", k: "pacman aur flatpak upgrade packages" },
        { id: "about", s: "System", t: "About bead", g: "info", d: "Version, health and the settings file", k: "version doctor restart welcome release changelog" }
    ]
    readonly property var cur: pages.find(p => p.id === SettingsApp.page) ?? pages[5]

    // Size: picking one only shows it; Apply restarts bead with it, and the
    // island then asks whether to keep it (config/sizecheck.js)
    property string sizePick: ""
    function applySize(): void {
        if (!sizePick) return;
        Settings.scaleWas = Settings.scale;
        Settings.scale = Number(sizePick);
        sizePick = "";
        Quickshell.execDetached(["setsid", "-f", "sh", "-c", 'sleep 0.8; exec "$1" restart', "sh", Paths.cmd("bead")]);
    }
    readonly property string settingsFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/settings.json"

    // bead's keys (data/keys.json, as strand writes them into Hyprland's config)
    property var keys: []
    FileView {
        path: Paths.share + "/data/keys.json"
        printErrors: false
        onLoaded: { try { win.keys = JSON.parse(text()); } catch (e) { win.keys = []; } }
    }

    Component.onCompleted: { Doctor.check(); Release.check(); }

    // ── pieces ──
    // a setting: a label (and a hint) with its control on the right
    component Setting: Item {
        id: st
        property string label: ""
        property string hint: ""
        property string words: ""
        property bool last: false
        property bool clickable: false   // the whole row is a button (a choice among devices)
        signal clicked()
        default property alias trailing: slot.data
        readonly property bool match: !win.searching || win.matches(label, hint, words)
        visible: match
        width: parent?.width ?? 0
        height: visible ? Math.max(56, col.implicitHeight + 20) : 0
        Rectangle {
            visible: st.clickable
            anchors.fill: parent; anchors.margins: 4
            radius: 12
            color: Qt.alpha(Theme.text, rowMa.containsMouse ? 0.05 : 0)
            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.clicked() }
        }
        Column {
            id: col
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36 - slot.width - 12
            spacing: 2
            Text { width: parent.width; wrapMode: Text.WordWrap; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.text; text: st.label }
            Label { visible: st.hint !== ""; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11; text: st.hint }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
        Rectangle { visible: !st.last; x: 18; width: parent.width - 36; height: 1; anchors.bottom: parent.bottom; color: Qt.alpha(Theme.text, 0.06) }
    }
    // a card of settings, with a small title over it
    component Group: Column {
        id: grp
        property string title: ""
        default property alias content: box.data
        readonly property bool shown: !win.searching || box.children.some(c => c.match === undefined ? false : c.match)
        visible: shown
        width: parent?.width ?? 0
        spacing: 8
        Text {
            visible: grp.title !== ""
            leftPadding: 4
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            color: Theme.subtext
            text: grp.title
        }
        Rectangle {
            width: parent.width
            height: box.height
            radius: 16
            color: Qt.alpha(Theme.text, 0.045)
            border.width: 1
            border.color: Qt.alpha(Theme.text, 0.05)
            Column { id: box; width: parent.width }
        }
    }
    // a page: its groups; while searching, every page shows what matches
    component Page: Column {
        id: pg
        property string pid: ""
        readonly property var info: win.pages.find(p => p.id === pid)
        readonly property bool titleHit: win.searching && win.matches(info.t, info.d, info.k)
        readonly property bool hasHits: children.some(c => c.shown === true)
        visible: win.searching ? (titleHit || hasHits) : SettingsApp.page === pid
        width: parent?.width ?? 0
        spacing: 22
        // while searching: the page's name, a way to open it
        Rectangle {
            visible: win.searching
            width: parent.width
            height: 44
            radius: 14
            color: Qt.alpha(Theme.text, hit.containsMouse ? 0.08 : 0.04)
            Row {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Icon { anchors.verticalCenter: parent.verticalCenter; name: pg.info.g; size: 19; color: Theme.tone("action") }
                Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; text: pg.info.t }
                Label { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; text: pg.info.d }
            }
            Icon { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; name: "chevron_right"; size: 18; color: Theme.subtext }
            MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.go(pg.pid) }
        }
    }
    // something bigger than a row (a panel of bead's own), in a card; hidden while searching
    component Panel: Rectangle {
        default property alias content: inner.data
        readonly property bool shown: !win.searching
        visible: shown
        width: parent?.width ?? 0
        height: inner.childrenRect.height + 32
        radius: 16
        color: Qt.alpha(Theme.text, 0.045)
        border.width: 1
        border.color: Qt.alpha(Theme.text, 0.05)
        Item { id: inner; x: 16; y: 16; width: parent.width - 32 }
    }
    component Btn: Rectangle {
        id: b
        property string glyph: ""
        signal hit()
        width: 28; height: 28; radius: 14
        color: Qt.alpha(Theme.text, bma.pressed ? 0.16 : bma.containsMouse ? 0.11 : 0.06)
        Icon { anchors.centerIn: parent; name: b.glyph; size: 16; color: Theme.text }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.hit() }
    }
    // minutes: −  value  +  (0 is "Never")
    component Minutes: Row {
        id: mins
        property real value: 0
        signal chose(real v)
        readonly property list<real> stops: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        function step(d: int): void {
            const next = d > 0 ? stops.find(x => x > value) : [...stops].reverse().find(x => x < value);
            if (next !== undefined) chose(next);
        }
        spacing: 4
        Btn { glyph: "remove"; onHit: mins.step(-1) }
        Text {
            width: 62
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: mins.value > 0 ? Theme.text : Theme.subtext
            text: mins.value <= 0 ? "Never" : mins.value < 60 ? mins.value + " min" : (mins.value / 60) + " h"
        }
        Btn { glyph: "add"; onHit: mins.step(1) }
        WheelHandler { onWheel: e => mins.step(e.angleDelta.y > 0 ? 1 : -1) }
    }
    // a slider with its value beside it
    component Level: Row {
        id: lv
        property real value: 0
        property string shown: Math.round(value * 100) + "%"
        property bool dim: false
        signal moved(real v)
        spacing: 12
        Slider { width: 220; anchors.verticalCenter: parent.verticalCenter; value: lv.value; dim: lv.dim; onMoved: v => lv.moved(v); onNudged: d => lv.moved(Math.max(0, Math.min(1, lv.value + d * 0.05))) }
        Text { width: 52; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }; color: Theme.subtext; text: lv.shown }
    }
    // a choice among a list (devices): the one in use has a check
    component Pick: Setting {
        id: pk
        property bool on: false
        signal picked()
        clickable: true
        onClicked: picked()
        Rectangle {
            width: 24; height: 24; radius: 12
            color: pk.on ? Theme.tone("action") : "transparent"
            border.width: pk.on ? 0 : 2
            border.color: Qt.alpha(Theme.text, 0.25)
            Icon { anchors.centerIn: parent; visible: pk.on; name: "check"; size: 16; color: Theme.frame }
        }
    }

    // ── keys: Esc closes (or clears the search), Ctrl+F searches, Ctrl+Up/Down change page ──
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { if (win.searching) SettingsApp.query = ""; else SettingsApp.open = false; e.accepted = true; }
            else if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) { search.forceActiveFocus(); e.accepted = true; }
            else if ((e.key === Qt.Key_Down || e.key === Qt.Key_Up) && (e.modifiers & Qt.ControlModifier)) {
                const i = win.pages.findIndex(p => p.id === SettingsApp.page);
                win.go(win.pages[Math.max(0, Math.min(win.pages.length - 1, i + (e.key === Qt.Key_Down ? 1 : -1)))].id);
                e.accepted = true;
            }
        }
    }

    // ── the sidebar ──
    Rectangle {
        id: side
        width: 268
        height: parent.height
        color: Qt.alpha(Theme.text, 0.03)

        // search
        Rectangle {
            id: field
            x: 14; y: 16
            width: parent.width - 28
            height: 40
            radius: 20
            color: Qt.alpha(Theme.text, search.activeFocus ? 0.09 : 0.06)
            border.width: search.activeFocus ? 1.5 : 0
            border.color: Theme.tone("action")
            Icon { x: 13; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.subtext }
            TextInput {
                id: search
                x: 40; width: parent.width - 40 - 34
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font; font.pixelSize: 13
                color: Theme.text
                selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                clip: true
                text: SettingsApp.query
                onTextEdited: { SettingsApp.query = text; scroller.contentY = 0; }
                Keys.onEscapePressed: e => { if (win.searching) SettingsApp.query = ""; else SettingsApp.open = false; }
                Label { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13; text: "Search settings" }
            }
            Btn {
                visible: win.searching
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                glyph: "close"
                onHit: SettingsApp.query = ""
            }
        }

        Flickable {
            y: field.y + field.height + 12
            width: parent.width
            height: parent.height - y - 12
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: list
                x: 10
                width: parent.width - 20
                Repeater {
                    model: win.pages
                    Column {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool on: !win.searching && SettingsApp.page === modelData.id
                        readonly property bool head: index === 0 || win.pages[index - 1].s !== modelData.s
                        width: list.width
                        Text {
                            visible: entry.head
                            topPadding: entry.index === 0 ? 4 : 14
                            bottomPadding: 6
                            leftPadding: 12
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                            color: Qt.alpha(Theme.text, 0.45)
                            text: entry.modelData.s.toUpperCase()
                        }
                        Rectangle {
                            width: parent.width
                            height: 40
                            radius: 12
                            color: entry.on ? Qt.alpha(Theme.tone("action"), 0.16) : Qt.alpha(Theme.text, ema.containsMouse ? 0.05 : 0)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26; radius: 8
                                color: entry.on ? Theme.tone("action") : Qt.alpha(Theme.text, 0.08)
                                Icon { anchors.centerIn: parent; name: entry.modelData.g; size: 16; fill: entry.on ? 1 : 0; color: entry.on ? Theme.frame : Theme.text }
                            }
                            Text {
                                x: 46; anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.font; font.pixelSize: 13
                                font.weight: entry.on ? Font.DemiBold : Font.Medium
                                color: Theme.text
                                text: entry.modelData.t
                            }
                            // something to look at: updates waiting, or something bead needs
                            Rectangle {
                                visible: (entry.modelData.id === "updates" && Updates.count > 0)
                                    || (entry.modelData.id === "about" && (Release.available || Doctor.problems.some(c => c.need === "core")))
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                color: Theme.tone("action")
                            }
                            MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.go(entry.modelData.id) }
                        }
                    }
                }
            }
        }
    }

    // ── the page ──
    Flickable {
        id: scroller
        x: side.width
        width: parent.width - side.width
        height: parent.height
        contentHeight: body.height + 64
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            x: 40; y: 32
            width: Math.min(760, scroller.width - 80)
            spacing: 22

            // heading
            Row {
                spacing: 16
                Rectangle {
                    width: 48; height: 48; radius: 14
                    color: Theme.tone("action")
                    Icon { anchors.centerIn: parent; name: win.searching ? "search" : win.cur.g; size: 26; fill: 1; color: Theme.frame }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; color: Theme.text; text: win.searching ? "Search" : win.cur.t }
                    Label { font.pixelSize: 12; text: win.searching ? "Settings matching “" + SettingsApp.query.trim() + "”" : win.cur.d }
                }
            }

            // ── Wi-Fi ──
            Page {
                pid: "wifi"
                Panel { WifiPanel { width: parent.width; active: SettingsApp.page === "wifi" && !win.searching } }
            }

            // ── Bluetooth ──
            Page {
                pid: "bluetooth"
                Panel { BluetoothPanel { width: parent.width; active: SettingsApp.page === "bluetooth" && !win.searching } }
            }

            // ── Sound ──
            Page {
                pid: "sound"
                Group {
                    title: "Output"
                    Setting {
                        label: "Volume"; hint: Audio.sink?.description || Audio.sink?.name || "No speakers"; words: "speaker loud"
                        Row {
                            spacing: 10
                            Btn { anchors.verticalCenter: parent.verticalCenter; glyph: Audio.muted ? "volume_off" : "volume_up"; onHit: Audio.toggleMute() }
                            Level { value: Math.min(1, Audio.volume); shown: Math.round(Audio.volume * 100) + "%"; dim: Audio.muted; onMoved: v => Audio.setVolume(v) }
                        }
                    }
                    Repeater {
                        model: Audio.sinks
                        Pick {
                            required property var modelData
                            required property int index
                            label: modelData.description || modelData.nickname || modelData.name
                            hint: "Play sound here"; words: "output device speakers headphones"
                            on: Audio.sink === modelData
                            last: index === Audio.sinks.length - 1
                            onPicked: Audio.useSink(modelData)
                        }
                    }
                }
                Group {
                    title: "Input"
                    Setting {
                        label: "Microphone"; hint: Audio.micMuted ? "Muted" : (Audio.source?.description || "On"); words: "mic mute record"
                        Toggle { checked: !Audio.micMuted; onToggled: Audio.toggleMicMute() }
                    }
                    Setting {
                        label: "Input volume"; words: "mic level gain"
                        Level { value: Math.min(1, Audio.micVolume); dim: Audio.micMuted; onMoved: v => Audio.setMicVolume(v) }
                    }
                    Repeater {
                        model: Audio.sources
                        Pick {
                            required property var modelData
                            required property int index
                            label: modelData.description || modelData.nickname || modelData.name
                            hint: "Listen here"; words: "input device microphone"
                            on: Audio.source === modelData
                            last: index === Audio.sources.length - 1
                            onPicked: Audio.useSource(modelData)
                        }
                    }
                }
            }

            // ── Displays ──
            Page {
                pid: "displays"
                Group {
                    title: "Brightness"
                    visible: shown && Quickshell.screens.some(s => Brightness.has(s))
                    Repeater {
                        model: Quickshell.screens.filter(s => Brightness.has(s))
                        Setting {
                            required property var modelData
                            label: modelData.name; hint: modelData.model || ""; words: "brightness screen monitor"
                            Level { value: Brightness.value(modelData); onMoved: v => Brightness.set(modelData, v) }
                        }
                    }
                }
                Panel {
                    DisplaysTab { width: parent.width; height: 470 }
                }
            }

            // ── Wallpaper ──
            Page {
                pid: "wallpaper"
                Group {
                    Setting {
                        label: "Shuffle"; hint: "A different one of yours, or bead's"; words: "random wallpaper"
                        Action { text: "Shuffle"; glyph: "shuffle"; onHit: Wallpaper.random("all") }
                    }
                    Setting {
                        label: "Your wallpapers folder"; hint: Wallpaper.stillDir.replace(Quickshell.env("HOME"), "~") + " · drop pictures here"; words: "add own folder pictures"; last: true
                        Action { text: "Open"; glyph: "folder_open"; onHit: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Wallpaper.stillDir]) }
                    }
                }
                Panel {
                    WallpapersTab { width: parent.width; height: 520 }
                }
            }

            // ── Appearance ──
            Page {
                pid: "appearance"
                Group {
                    title: "Colour"
                    Setting {
                        label: "Colours"; hint: Settings.theme === "sileo" ? "sileo's own palette" : "Drawn from the wallpaper"; words: "theme palette"
                        Choice { options: [{ v: "wallpaper", t: "Wallpaper" }, { v: "sileo", t: "Sileo" }]; value: Settings.theme; onChose: v => Settings.theme = v }
                    }
                    Setting {
                        label: "Tint"; hint: Settings.theme === "sileo" ? "Only with wallpaper colours" : "How much colour to take"; words: "vibrant muted mono"
                        opacity: Settings.theme === "sileo" ? 0.45 : 1
                        Choice { options: [{ v: "vibrant", t: "Vibrant" }, { v: "muted", t: "Muted" }, { v: "mono", t: "Mono" }]; value: Settings.tint; onChose: v => Settings.tint = v }
                    }
                    Setting {
                        label: "Palette"; hint: "The colours in use now"; words: "colours"; last: true
                        Row {
                            spacing: 8
                            Repeater {
                                model: [Theme.tone("action"), Theme.text, Theme.subtext, Theme.fill, Theme.tone("success"), Theme.tone("warning"), Theme.tone("error")]
                                Rectangle {
                                    required property var modelData
                                    width: 22; height: 22; radius: 11
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.text, 0.12)
                                }
                            }
                        }
                    }
                }
                Group {
                    title: "Size"
                    Setting {
                        label: "Interface size"; words: "scale zoom bigger smaller"; last: win.sizePick === ""
                        hint: win.sizePick ? SizeCheck.changeHint(Settings.scale, Number(win.sizePick)) : "Pick one to preview it; applying restarts bead"
                        Choice {
                            options: [{ v: "1", t: "100%" }, { v: "1.15", t: "115%" }, { v: "1.35", t: "135%" }, { v: "1.5", t: "150%" }]
                            value: win.sizePick || String(Settings.scale)
                            onChose: v => win.sizePick = SizeCheck.pick(v, Settings.scale)
                        }
                    }
                    Setting {
                        visible: match && win.sizePick !== ""
                        label: "Preview"; words: "size"; last: true
                        Row {
                            spacing: 14
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 112; height: 26; radius: 13
                                color: Theme.fill
                                border.width: 1
                                border.color: Qt.alpha(Theme.text, 0.1)
                                scale: win.sizePick ? Number(win.sizePick) / Settings.scale : 1
                                Behavior on scale { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.002 } }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "music_note"; size: 14; fill: 1; color: Theme.tone("action") }
                                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.text; text: "The island" }
                                }
                            }
                            Action { accent: true; text: "Apply · restarts bead"; glyph: "restart_alt"; onHit: win.applySize() }
                        }
                    }
                }
                Group {
                    title: "Bar and island"
                    Setting {
                        label: "Window title in the bar"; hint: "Down the side, under the workspaces"; words: "bar title"
                        Toggle { checked: Settings.showTitle; onToggled: Settings.showTitle = !Settings.showTitle }
                    }
                    Setting {
                        label: "Workspaces per monitor"
                        hint: Settings.workspaceGroups ? "Each monitor has its own 1–10 (the main one 1–10, the next 11–20)" : "One set of workspaces across monitors"
                        words: "workspace monitor screen group bar keys"
                        Toggle { checked: Settings.workspaceGroups; onToggled: Settings.workspaceGroups = !Settings.workspaceGroups }
                    }
                    Setting {
                        label: "Main monitor"; hint: "Where the island and the lock screen live"; words: "screen island lock primary"
                        Choice { options: Quickshell.screens.map(s => ({ v: s.name, t: s.name })); value: Settings.home; onChose: v => Settings.islandScreen = v }
                    }
                    Setting {
                        label: "Clipboard hints"; hint: "After copying a colour, an address or a tracking number, the island offers what's next"; words: "copy island clip"; last: true
                        Toggle { checked: Settings.clipHints; onToggled: Settings.clipHints = !Settings.clipHints }
                    }
                }
            }

            // ── Notifications ──
            Page {
                pid: "notifications"
                Group {
                    Setting {
                        label: "Do Not Disturb"; hint: Notifs.dnd ? "On: notifications wait quietly in the history" : "Off"; words: "dnd quiet silence"
                        Toggle { checked: Notifs.dnd; onToggled: Notifs.dnd = !Notifs.dnd }
                    }
                    Setting {
                        label: "History"; hint: Notifs.entries.length ? Notifs.entries.length + (Notifs.entries.length === 1 ? " notification" : " notifications") : "Empty"; words: "clear past old"; last: true
                        Row {
                            spacing: 8
                            Action { text: "Show"; glyph: "history"; onHit: Notifs.panelOpen = true }
                            Action { visible: Notifs.entries.length > 0; text: "Clear"; glyph: "clear_all"; onHit: Notifs.clear() }
                        }
                    }
                }
            }

            // ── Night light ──
            Page {
                pid: "night"
                Group {
                    Setting {
                        label: "Night light"; words: "warm schedule sunset"
                        hint: !NightLight.available ? "Needs hyprsunset (bead doctor can install it)"
                            : Settings.nightLight === "sunset" ? "From sunset to sunrise" + (NightLight.warm ? " · warm now" : "")
                            : Settings.nightLight === "on" ? "Warm all the time" : "Off"
                        opacity: NightLight.available ? 1 : 0.5
                        Choice { options: [{ v: "off", t: "Off" }, { v: "sunset", t: "At sunset" }, { v: "on", t: "On" }]; value: Settings.nightLight; onChose: v => Settings.nightLight = v }
                    }
                    Setting {
                        label: "Warmth"; hint: "Lower is warmer"; words: "temperature kelvin colour"; last: true
                        opacity: Settings.nightLight === "off" ? 0.5 : 1
                        Level {
                            value: 1 - (Settings.nightTemp - 2500) / 3500
                            shown: Math.round(Settings.nightTemp) + " K"
                            onMoved: v => Settings.nightTemp = Math.round((2500 + (1 - v) * 3500) / 100) * 100
                        }
                    }
                }
            }

            // ── Power & idle ──
            Page {
                pid: "power"
                Group {
                    title: "When idle"
                    Setting { label: "Lock the screen"; hint: "After this long without input"; words: "idle timeout"; Minutes { value: Settings.lockAfter; onChose: v => Settings.lockAfter = v } }
                    Setting {
                        label: "Lock at login"
                        hint: Settings.lockAtLogin === "auto" ? "When the computer logs in by itself" : Settings.lockAtLogin === "on" ? "Every time you log in" : "Never"
                        words: "autologin startup boot reboot password"
                        Choice { options: [{ v: "auto", t: "Auto" }, { v: "on", t: "Always" }, { v: "off", t: "Never" }]; value: Settings.lockAtLogin; onChose: v => Settings.lockAtLogin = v }
                    }
                    Setting { label: "Turn the screen off"; words: "idle blank dpms display"; Minutes { value: Settings.screenOffAfter; onChose: v => Settings.screenOffAfter = v } }
                    Setting { label: "Suspend"; words: "idle sleep"; Minutes { value: Settings.suspendAfter; onChose: v => Settings.suspendAfter = v } }
                    Setting {
                        label: "Stay awake for media"; hint: "Nothing happens while audio plays"; words: "video music playing"
                        Toggle { checked: Settings.pauseForMedia; onToggled: Settings.pauseForMedia = !Settings.pauseForMedia }
                    }
                    Setting {
                        label: "Keep awake"; hint: "Never lock, blank or sleep, until you turn it off"; words: "caffeine inhibit"; last: true
                        Toggle { checked: Idle.keepAwake; onToggled: Idle.keepAwake = !Idle.keepAwake }
                    }
                }
                Group {
                    title: "Games"
                    Setting {
                        label: "Game mode"; hint: GameMode.active ? "On now: " + GameMode.game : "No blur or animations while a game is fullscreen"; words: "performance fps"; last: true
                        Toggle { checked: Settings.gameMode; onToggled: Settings.gameMode = !Settings.gameMode }
                    }
                }
                Group {
                    id: session
                    title: "Session"
                    property string arming: ""   // a second click does it (log out, reboot, shut down)
                    Timer { id: disarm; interval: 4000; onTriggered: session.arming = "" }
                    Repeater {
                        model: Session.actions
                        Setting {
                            required property var modelData
                            required property int index
                            label: modelData.title
                            hint: session.arming === modelData.id ? "Click again to " + modelData.title.toLowerCase() : modelData.sub
                            words: "power session"
                            last: index === Session.actions.length - 1
                            Action {
                                glyph: modelData.glyph
                                accent: session.arming === modelData.id
                                text: session.arming === modelData.id ? "Confirm" : modelData.title
                                onHit: {
                                    if (modelData.confirm && session.arming !== modelData.id) { session.arming = modelData.id; disarm.restart(); return; }
                                    session.arming = "";
                                    SettingsApp.open = false;
                                    Session.run(modelData);
                                }
                            }
                        }
                    }
                }
            }

            // ── Assistant & voice ──
            Page {
                pid: "assistant"
                Group {
                    title: "Pearl"
                    Setting {
                        label: "Answers with"; words: "ask claude api key local"
                        hint: Settings.askVia === "api" ? "Your key, in ~/.config/bead/anthropic-key"
                            : Settings.askVia === "local" ? "Offline and small: the voice model"
                            : "Your Claude Code login"
                        Choice { options: [{ v: "claude", t: "Claude Code" }, { v: "api", t: "API key" }, { v: "local", t: "Local" }]; value: Settings.askVia; onChose: v => Settings.askVia = v }
                    }
                    Setting {
                        label: "Claude model"; hint: "For ? asks and spoken questions"; words: "haiku sonnet opus"; last: true
                        opacity: Settings.askVia === "local" ? 0.4 : 1
                        enabled: Settings.askVia !== "local"
                        Choice { options: [{ v: "haiku", t: "Haiku" }, { v: "sonnet", t: "Sonnet" }, { v: "opus", t: "Opus" }]; value: Settings.askModel; onChose: v => Settings.askModel = v }
                    }
                }
                Group {
                    title: "Voice"
                    Setting {
                        label: "Voice command"; hint: "Hold, speak, let go"; words: "murmur speak"
                        Row { spacing: 4; Key { text: "Super" } Key { text: "Space" } }
                    }
                    Setting {
                        label: "Dictation"; hint: "Types into whatever has focus"; words: "speech type"
                        Row { spacing: 4; Key { text: "Super" } Key { text: "A" } }
                    }
                    Setting {
                        label: "Your voice actions"; words: "custom commands automations"
                        hint: Voice.customError ? "Skipped: " + Voice.customError
                            : Voice.custom.length ? Voice.custom.map(c => c.name.replace(/_/g, " ")).join(" · ")
                            : "Add your own commands and automations"
                        Action {
                            text: "Edit"; glyph: "edit"
                            onHit: {
                                Voice.ensureCustom();
                                Quickshell.execDetached([Paths.cmd("bead-term"), "--", "sh", "-c", 'exec "${VISUAL:-${EDITOR:-nano}}" "$1"', "sh", Voice.customPath]);
                            }
                        }
                    }
                    Setting {
                        label: "Voice models"; words: "gpu memory unload whisper"; last: true
                        hint: Voice.warm ? (Voice.serverReady ? "Loaded · unloaded after 4 min idle" : "Loading…") : "Not loaded · they load with a voice command"
                        Action { visible: Voice.warm; text: "Unload"; glyph: "eject"; onHit: Voice.unload() }
                    }
                }
            }

            // ── Keyboard shortcuts ──
            Page {
                pid: "keyboard"
                Repeater {
                    model: [...new Set(win.keys.map(k => k.group))]
                    Group {
                        id: kg
                        required property string modelData
                        title: modelData
                        Repeater {
                            model: win.keys.filter(k => k.group === kg.modelData)
                            Setting {
                                required property var modelData
                                required property int index
                                label: KeySheet.title(modelData.what)
                                words: modelData.keys + " " + modelData.group + " shortcut key"
                                last: index === win.keys.filter(k => k.group === kg.modelData).length - 1
                                Row {
                                    spacing: 4
                                    Repeater { model: KeySheet.caps(modelData.keys); Key { required property string modelData; text: modelData } }
                                }
                            }
                        }
                    }
                }
                Label {
                    visible: !win.searching
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    text: "These are bead's own keys, as the installer set them up. Ones you've changed or added in Hyprland's config aren't listed."
                }
            }

            // ── Weather & units ──
            Page {
                pid: "region"
                Group {
                    Setting {
                        label: "Temperature"; hint: "Auto follows your locale"; words: "celsius fahrenheit units weather"; last: true
                        Choice { options: [{ v: "auto", t: "Auto" }, { v: "celsius", t: "°C" }, { v: "fahrenheit", t: "°F" }]; value: Settings.units; onChose: v => Settings.units = v }
                    }
                }
            }

            // ── Updates ──
            Page {
                pid: "updates"
                Group {
                    Setting {
                        label: Updates.checking ? "Checking for updates…" : Updates.count > 0 ? Updates.count + (Updates.count === 1 ? " update" : " updates") : "Up to date"
                        hint: Updates.count > 0 ? Updates.repo.length + " repo · " + Updates.aur.length + " AUR · " + Updates.flatpak.length + " Flatpak" + (Updates.restart ? " · restart after" : "") : "Checks every 3 hours"
                        words: "upgrade packages pacman"
                        last: Updates.count === 0
                        Row {
                            spacing: 8
                            Action { text: "Check"; glyph: "refresh"; onHit: Updates.check() }
                            Action { visible: Updates.count > 0; accent: true; text: "Update"; glyph: "download"; onHit: Updates.update() }
                        }
                    }
                    Item {
                        visible: Updates.count > 0 && !win.searching
                        width: parent.width
                        height: visible ? chips.height + 28 : 0
                        Flow {
                            id: chips
                            x: 18; y: 14
                            width: parent.width - 36
                            spacing: 6
                            Repeater {
                                model: Updates.items.map(u => u.name)
                                Rectangle {
                                    required property string modelData
                                    width: pk.implicitWidth + 18; height: 26; radius: 13
                                    color: Qt.alpha(Theme.text, 0.06)
                                    Text { id: pk; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 11; color: Theme.text; text: parent.modelData.split(" ")[0] }
                                }
                            }
                        }
                    }
                }
            }

            // ── About ──
            Page {
                pid: "about"
                Group {
                    Setting {
                        label: "bead " + Release.version; words: "version release update changelog"
                        hint: Release.checking ? "Looking for a new release…"
                            : Release.available ? Release.newest + " is out"
                            : Release.state === "dev" ? "A development checkout"
                            : Release.state === "package" ? "From a package: updates come with it"
                            : Release.state === "offline" ? "Couldn't look for a new release"
                            : Release.state === "uptodate" ? "The newest" : ""
                        Row {
                            spacing: 8
                            Action { visible: Release.available; accent: true; text: "Update"; glyph: "upgrade"; onHit: Release.update() }
                            Action { text: "What's new"; glyph: "new_releases"; onHit: Release.whatsNew() }
                        }
                    }
                    Setting {
                        readonly property int core: Doctor.problems.filter(c => c.need === "core").length
                        label: !Doctor.checks.length ? "Checking what bead needs…" : core ? core + " missing" : "Everything bead needs is here"
                        hint: Doctor.installing ? "Installing…" : Doctor.problems.length ? Doctor.problems.map(c => c.what.replace(/ \(.*\)$/, "")).join(" · ") : ""
                        words: "doctor health missing packages"
                        Row {
                            spacing: 8
                            Action { text: "Check"; glyph: "health_and_safety"; onHit: Doctor.check() }
                            Action { visible: Doctor.packages.length > 0 && !Doctor.installing; accent: true; text: "Install"; glyph: "download"; onHit: Doctor.install(Doctor.packages) }
                        }
                    }
                    Setting {
                        label: "Settings file"; hint: win.settingsFile.replace(Quickshell.env("HOME"), "~") + " · edits apply live"; words: "json config"
                        Action { text: "Open"; glyph: "open_in_new"; onHit: Quickshell.execDetached(["xdg-open", win.settingsFile]) }
                    }
                    Setting {
                        label: "The welcome"; hint: "The first-run tour, again"; words: "intro tour"
                        Action { text: "Show"; glyph: "waving_hand"; onHit: { SettingsApp.open = false; Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "welcome", "open"]); } }
                    }
                    Setting {
                        label: "Restart bead"; hint: "If something looks stuck"; words: "reload"; last: true
                        Action { text: "Restart"; glyph: "restart_alt"; onHit: Quickshell.execDetached([Paths.cmd("bead"), "restart"]) }
                    }
                }
            }

            // nothing found
            Column {
                visible: win.searching && !body.children.some(c => c.pid !== undefined && c.visible)
                width: parent.width
                topPadding: 40
                spacing: 6
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "search_off"; size: 36; color: Theme.subtext }
                Label { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 13; text: "No setting matches that" }
            }
        }
    }
}
