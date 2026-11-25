pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../config/sizecheck.js" as SizeCheck
import "../../config/look.js" as L
import "../../services/focus.js" as FJ
import "../../services/widgets.js" as WJ
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
    function go(id: string): void { closeMenu(); SettingsApp.query = ""; SettingsApp.page = id; scroller.contentY = 0; }

    readonly property var pages: [
        { id: "wifi", s: "Connections", t: "Wi-Fi", g: "wifi", d: "Networks, and joining one", k: "network internet wireless password" },
        { id: "bluetooth", s: "Connections", t: "Bluetooth", g: "bluetooth", d: "Pairing and connecting devices", k: "headphones pair device speaker" },
        { id: "sound", s: "Device", t: "Sound", g: "volume_up", d: "Speakers, microphones and volume", k: "audio output input mic speaker headphones volume mute" },
        { id: "displays", s: "Device", t: "Displays", g: "monitor", d: "Layout, resolution, scale and brightness", k: "monitor screen resolution refresh rate brightness scale" },
        { id: "wallpaper", s: "Personal", t: "Wallpaper", g: "wallpaper", d: "Stills and live wallpapers", k: "background image picture" },
        { id: "appearance", s: "Personal", t: "Appearance", g: "palette", d: "Colours, size, the bar and the island", k: "theme tint colour color size scale bar title monitor island" },
        { id: "notifications", s: "Personal", t: "Notifications", g: "notifications", d: "Do Not Disturb and the history", k: "dnd quiet alerts history whatsapp telegram messages" },
        { id: "night", s: "Personal", t: "Night light", g: "nightlight", d: "A warmer screen in the evening", k: "warm blue light temperature sunset hyprsunset" },
        { id: "focus", s: "Customise", t: "Focus modes", g: "self_improvement", d: "Work, Game, Night: a look, Do Not Disturb and more, together", k: "focus mode work game night schedule dnd do not disturb automatic" },
        { id: "widgets", s: "Customise", t: "Widgets", g: "widgets", d: "A server, a build or a number, on the island and the dashboard", k: "widget island server github ci number toggle command pin" },
        { id: "presets", s: "Customise", t: "Presets & sharing", g: "style", d: "Whole looks in one tap; save, copy and paste them", k: "preset theme look share import export minimal showcase calm snappy focus reset" },
        ...L.PAGES.map(p => ({ id: p.id, s: "Customise", t: p.t, g: p.g, d: p.d, k: "customise customize " + L.SCHEMA.filter(o => o.page === p.id).map(o => o.label).join(" ").toLowerCase() })),
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
    property string lookNote: ""   // what Presets & sharing just did
    // the open dropdown's menu (one at a time)
    property Item menuFor: null
    function openMenu(d: Item): void { menuFor = d; ddMenu.place(); }
    function closeMenu(): void { menuFor = null; }
    // the window's been up a moment: rows created from now on animate in
    property bool settled: false
    Timer { running: win.visible; interval: 700; onTriggered: win.settled = true }
    Connections { target: Look; function onImported(name: string, error: string) { win.lookNote = error || "Added and applied “" + name + "”"; } }
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
        // right-click: () => [menu rows] (ContextMenu), or null for none
        property var menu: null
        TapHandler { acceptedButtons: Qt.RightButton; enabled: !!st.menu; onTapped: ep => Menus.open(st, ep.position.x, ep.position.y, st.menu()) }
        readonly property bool match: !win.searching || win.matches(label, hint, words)
        // arriving after the window's up (a saved preset, a network, a device): it
        // grows in; leave() shrinks it away before it's removed
        property real grow: 1
        Behavior on grow { id: growB; NumberAnimation { duration: Motion.ms(300); easing.type: Easing.OutCubic } }
        Component.onCompleted: if (win.settled) { growB.enabled = false; grow = 0; growB.enabled = true; grow = 1; }
        property var _after: null
        function leave(after: var): void { _after = after; grow = 0; leaveTimer.start(); }
        Timer { id: leaveTimer; interval: Motion.ms(300) + 20; onTriggered: if (st._after) st._after() }
        opacity: grow
        clip: grow < 1
        visible: match
        width: parent?.width ?? 0
        // as tall as its words or its controls (chips can wrap to a few lines)
        height: (visible ? Math.max(56, col.implicitHeight + 20, slot.height + 20) : 0) * grow
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
            Text { width: parent.width; wrapMode: Text.WordWrap; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.Medium; color: Theme.text; text: st.label }
            Label { visible: st.hint !== ""; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: Theme.caption; text: st.hint }
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
            font.family: Theme.font; font.pixelSize: Theme.small; font.weight: Font.Medium
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
                Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.Medium; color: Theme.text; text: pg.info.t }
                Label { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.caption; text: pg.info.d }
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
            font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.Medium
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
        Text { width: 52; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; font.family: Theme.font; font.pixelSize: Theme.small; font.features: { "tnum": 1 }; color: Theme.subtext; text: lv.shown }
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

    // ── Customise: rows drawn from config/look.js ──
    // a text field
    component Field: Rectangle {
        id: fd
        property alias text: fin.text
        property string placeholder: ""
        signal accepted()
        width: 180; height: 30; radius: 15
        color: Qt.alpha(Theme.text, fin.activeFocus ? 0.1 : 0.06)
        border.width: fin.activeFocus ? 1.5 : 0
        border.color: Theme.tone("action")
        TextInput {
            TextMenu {}   // right-click: cut, copy, paste
            id: fin
            x: 12; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font; font.pixelSize: Theme.small
            color: Theme.text
            clip: true
            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
            onAccepted: fd.accepted()
            Label { visible: !fin.text; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.small; text: fd.placeholder }
        }
    }
    // a dropdown: the choice now, and a menu (the window's, below) to change it.
    // multi: value is a list and the menu ticks several, staying open
    component Dropdown: Rectangle {
        id: dd
        property var options: []        // [{ v, t, g? }]
        property var value
        property bool multi: false
        property string placeholder: "Choose"
        property int menuWidth: 0
        signal chose(var v)              // the value; with multi, the new list
        readonly property var picked: multi ? options.filter(o => (value ?? []).includes(o.v)) : options.filter(o => o.v === value)
        readonly property string label: picked.length ? (multi && picked.length > 2 ? picked.length + " chosen" : picked.map(o => o.t).join(", ")) : placeholder
        readonly property bool open: win.menuFor === dd
        width: Math.min(240, Math.max(150, ddRow.implicitWidth + 44)); height: 30; radius: 15
        color: Qt.alpha(Theme.text, open ? 0.12 : dda.containsMouse ? 0.1 : 0.06)
        border.width: open ? 1.5 : 0
        border.color: Theme.tone("action")
        Behavior on color { ColorAnimation { duration: Motion.ms(120) } }
        Row {
            id: ddRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Icon { visible: !dd.multi && !!dd.picked[0]?.g; anchors.verticalCenter: parent.verticalCenter; name: dd.picked[0]?.g ?? ""; size: 15; color: Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 170)
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: Theme.small; font.weight: Font.Medium
                color: dd.picked.length ? Theme.text : Theme.subtext
                text: dd.label
            }
        }
        Icon {
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            name: "expand_more"; size: 16; color: Theme.subtext
            rotation: dd.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Motion.ms(180); easing.type: Easing.OutCubic } }
        }
        MouseArea { id: dda; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dd.open ? win.closeMenu() : win.openMenu(dd) }
    }
    // a chip that's on or off
    component Chip: Rectangle {
        id: cp
        property string text: ""
        property string glyph: ""
        property bool on: false
        signal hit()
        width: cr.implicitWidth + (text ? 20 : 12); height: 26; radius: 13
        color: on ? Theme.tone("action") : Qt.alpha(Theme.text, cma.containsMouse ? 0.11 : 0.06)
        Behavior on color { ColorAnimation { duration: Motion.ms(140) } }
        Row {
            id: cr; anchors.centerIn: parent; spacing: 5
            Icon { visible: cp.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; name: cp.glyph; size: 15; fill: cp.on ? 1 : 0; color: cp.on ? Theme.frame : Theme.text }
            Text { visible: cp.text !== ""; anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium; color: cp.on ? Theme.frame : Theme.text; text: cp.text }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cp.hit() }
    }
    // a small button with words
    component Word: Rectangle {
        id: wd
        property string text: ""
        property string glyph: ""
        property bool accent: false
        signal hit()
        width: wr.implicitWidth + 24; height: 30; radius: 15
        color: accent ? Qt.alpha(Theme.tone("action"), wma.containsMouse ? 0.3 : 0.2) : Qt.alpha(Theme.text, wma.containsMouse ? 0.11 : 0.06)
        Row {
            id: wr; anchors.centerIn: parent; spacing: 6
            Icon { visible: wd.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; name: wd.glyph; size: 15; color: wd.accent ? Theme.tone("action") : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: Theme.small; font.weight: Font.Medium; color: wd.accent ? Theme.tone("action") : Theme.text; text: wd.text }
        }
        MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wd.hit() }
    }
    function shownValue(o: var, x: var): string {
        if (o.unit === "%") return Math.round(x * 100) + "%";
        if (o.unit === "×") return x.toFixed(1) + "×";
        if (o.unit === "ms") return x >= 1000 ? (x / 1000).toFixed(x % 1000 ? 2 : 0).replace(/0$/, "") + " s" : x + " ms";
        return x + (o.unit ? " " + o.unit : "");
    }
    // the fonts worth offering: these, when installed
    readonly property var fontPicks: ["Inter", "Noto Sans", "Rubik", "Outfit", "Manrope", "Cantarell", "Fira Sans", "Ubuntu", "JetBrains Mono", "DejaVu Sans"].filter(f => Qt.fontFamilies().includes(f)).slice(0, 4)
    // one option: its control by type, and a reset while it differs from the default
    component Opt: Setting {
        id: op
        required property var o
        readonly property var val: Look.v[o.k]
        readonly property bool changed: JSON.stringify(val) !== JSON.stringify(o.def)
        menu: () => [
            { t: "Reset to default", g: "restart_alt", enabled: op.changed, act: () => Look.set(op.o.k, op.o.def) },
            { t: "Copy value", g: "content_copy", act: () => { Quickshell.clipboardText = typeof op.val === "object" ? JSON.stringify(op.val) : String(op.val); } },
            { sep: true },
            { t: "Reset this page", g: "settings_backup_restore", danger: true, act: () => Look.resetPage(op.o.page) }
        ]
        label: o.label
        hint: o.hint
        words: o.group + " " + o.k + " customise customize " + (o.choices ? o.choices.map(c => c.t).join(" ") : "")
        Row {
            spacing: 10
            Btn { visible: op.changed; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; glyph: "restart_alt"; onHit: Look.set(op.o.k, op.o.def) }
            Toggle { visible: op.o.type === "bool"; anchors.verticalCenter: parent.verticalCenter; checked: op.o.type === "bool" && op.val; onToggled: Look.set(op.o.k, !op.val) }
            Choice { visible: op.o.type === "choice"; anchors.verticalCenter: parent.verticalCenter; options: op.o.choices ?? []; value: op.o.type === "choice" ? op.val : ""; onChose: v => Look.set(op.o.k, v) }
            Row {
                visible: op.o.type === "num"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Slider {
                    width: 200; anchors.verticalCenter: parent.verticalCenter
                    value: op.o.type === "num" ? (op.val - op.o.min) / (op.o.max - op.o.min) : 0
                    onMoved: f => Look.set(op.o.k, op.o.min + f * (op.o.max - op.o.min))
                    onNudged: d => Look.set(op.o.k, op.val + d * op.o.step)
                }
                Text { width: 58; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; font.family: Theme.font; font.pixelSize: Theme.small; font.features: { "tnum": 1 }; color: Theme.subtext; text: op.o.type === "num" ? win.shownValue(op.o, op.val) : "" }
            }
            // a colour: the wallpaper's, a swatch, or your own hex
            Row {
                visible: op.o.type === "color"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Rectangle {
                    width: 46; height: 22; radius: 11
                    color: op.val === "" ? Theme.tone("action") : Qt.alpha(Theme.text, 0.06)
                    Text { anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: Theme.tiny; font.weight: Font.Medium; color: op.val === "" ? Theme.frame : Theme.text; text: "Auto" }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Look.set(op.o.k, "") }
                }
                Repeater {
                    model: op.o.type === "color" ? L.SWATCHES : []
                    Rectangle {
                        id: sw
                        required property string modelData
                        anchors.verticalCenter: parent?.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: modelData
                        border.width: op.val === modelData ? 2 : 0
                        border.color: Theme.text
                        scale: swa.containsMouse ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        MouseArea { id: swa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Look.set(op.o.k, sw.modelData) }
                    }
                }
                Field { width: 84; height: 22; placeholder: "#hex"; text: op.o.type === "color" ? op.val : ""; onAccepted: Look.set(op.o.k, /^#?[0-9a-fA-F]{6}$/.test(text) ? (text[0] === "#" ? text : "#" + text) : op.val) }
            }
            // a font: a few installed ones, or any by name
            Row {
                visible: op.o.type === "font"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Dropdown {
                    menuWidth: 260
                    // every installed font, each shown in itself
                    options: op.o.type === "font" ? Qt.fontFamilies().filter(f => !/^(Noto (Color )?Emoji|Material)/.test(f)).map(f => ({ v: f, t: f, font: f })) : []
                    value: op.o.type === "font" ? op.val : ""
                    onChose: v => Look.set(op.o.k, v)
                }
            }
        }
    }
    // a Customise page: its preview, its options in their groups, and a reset
    component LookPageBody: Column {
        id: lp
        required property string pid
        // while searching: whether any of its rows match (the Page shows it then)
        readonly property bool shown: children.some(c => c.shown === true)
        width: parent?.width ?? 0
        spacing: 22
        LookPreview { visible: !win.searching; page: lp.pid }
        Repeater {
            model: [...new Set(L.SCHEMA.filter(o => o.page === lp.pid && o.type !== "apps").map(o => o.group))]
            Group {
                id: lg
                required property string modelData
                title: modelData
                Repeater {
                    model: L.SCHEMA.filter(o => o.page === lp.pid && o.group === lg.modelData && o.type !== "apps")
                    Opt { required property var modelData; required property int index; o: modelData; last: index === L.SCHEMA.filter(o => o.page === lp.pid && o.group === lg.modelData && o.type !== "apps").length - 1 }
                }
            }
        }
    }

    // ── keys: Esc closes (or clears the search), Ctrl+F searches, Ctrl+Up/Down change page ──
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape && win.menuFor) { win.closeMenu(); e.accepted = true; return; }
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
                TextMenu {}   // right-click: cut, copy, paste
                id: search
                x: 40; width: parent.width - 40 - 34
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font; font.pixelSize: Theme.body
                color: Theme.text
                selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                clip: true
                text: SettingsApp.query
                onTextEdited: { SettingsApp.query = text; scroller.contentY = 0; }
                Keys.onEscapePressed: e => { if (win.searching) SettingsApp.query = ""; else SettingsApp.open = false; }
                Label { visible: !search.text; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.body; text: "Search settings" }
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
                            font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium
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
                                font.family: Theme.font; font.pixelSize: Theme.body
                                font.weight: entry.on ? Font.Medium : Font.Medium
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
        onContentYChanged: win.closeMenu()
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
                    Text { font.family: Theme.font; font.pixelSize: Theme.heading; font.weight: Font.DemiBold; color: Theme.text; text: win.searching ? "Search" : win.cur.t }
                    Label { font.pixelSize: Theme.small; text: win.searching ? "Settings matching “" + SettingsApp.query.trim() + "”" : win.cur.d }
                }
            }

            // ── Focus modes (services/Focus.qml) ──
            Page {
                pid: "focus"
                Repeater {
                    // by id: editing a mode keeps its rows (and an open menu) in place
                    model: ScriptModel { values: Focus.modes.map(m => m.id) }
                    Group {
                        id: fm
                        required property string modelData
                        readonly property var m: Focus.modes.find(x => x.id === modelData) ?? FJ.clean({ id: modelData, name: modelData })
                        readonly property bool isOn: Focus.active === m.id
                        title: m.name + (isOn ? "  ·  ON" : "")
                        // right-click anywhere on the mode
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: ep => Menus.open(parent, ep.position.x, ep.position.y, [
                                { t: fm.isOn ? "Leave " + fm.m.name : "Turn on " + fm.m.name, g: fm.isOn ? "do_not_disturb_off" : fm.m.icon, act: () => Focus.toggle(fm.m.id) },
                                { t: "Duplicate", g: "content_copy", act: () => Focus.duplicate(fm.m.id) },
                                { sep: true },
                                { t: "Remove", g: "delete", danger: true, act: () => Focus.remove(fm.m.id) }
                            ])
                        }
                        Setting {
                            label: fm.isOn ? m.name + " is on" : "Turn on now"
                            hint: fm.isOn ? (Focus.reason === "schedule" ? "By its schedule" : Focus.reason === "app" ? "An app of its is open" : "You turned it on") + " · " + Focus.summary(fm.m)
                                : (Focus.when(fm.m) ? "On by itself: " + Focus.when(fm.m) : "Only by hand") + " · " + Focus.summary(fm.m)
                            words: "focus mode " + fm.m.name
                            Toggle { checked: fm.isOn; onToggled: Focus.toggle(fm.m.id) }
                        }
                        Setting {
                            label: "Name and icon"; words: "focus name icon"
                            Row {
                                spacing: 8
                                Field { anchors.verticalCenter: parent.verticalCenter; width: 120; text: fm.m.name; onAccepted: if (text.trim()) Focus.update(fm.m.id, { name: text }) }
                                Dropdown {
                                    anchors.verticalCenter: parent.verticalCenter
                                    options: FJ.ICONS.map(g => ({ v: g, g: g, t: ({ work: "Work", sports_esports: "Games", bedtime: "Night", menu_book: "Reading", code: "Code", brush: "Drawing", headphones: "Music", self_improvement: "Calm", school: "Study", videocam: "Video" })[g] ?? g }))
                                    value: fm.m.icon
                                    onChose: v => Focus.update(fm.m.id, { icon: v })
                                }
                            }
                        }
                        Setting {
                            label: "Look"; hint: "A Customise preset while it's on"; words: "focus preset look"
                            Dropdown {
                                options: [{ v: "", t: "Keep mine" }, ...L.PRESETS.filter(p => p.id !== "bead").map(p => ({ v: p.id, t: p.name })), ...Object.keys(Look.presets).map(k => ({ v: k, t: k + " (yours)" }))]
                                value: fm.m.preset
                                onChose: v => Focus.update(fm.m.id, { preset: v })
                            }
                        }
                        Setting {
                            label: "Do Not Disturb"; hint: "Pop-ups held (urgent ones still show)"; words: "focus dnd quiet"
                            Toggle { checked: fm.m.dnd; onToggled: Focus.update(fm.m.id, { dnd: !fm.m.dnd }) }
                        }
                        Setting {
                            visible: fm.m.dnd && match
                            label: "Let through"; hint: Notifs.apps.length ? "These still pop up" : "Apps show here once they've sent a notification"; words: "focus allow apps through"
                            Dropdown {
                                multi: true
                                placeholder: "None"
                                menuWidth: 240
                                // the apps (named as they send), with any already allowed in another spelling
                                options: [...new Set([...Notifs.apps, ...fm.m.allow.filter(a => !Notifs.apps.some(n => n.toLowerCase() === a.toLowerCase()))])].map(a => ({ v: a, t: a }))
                                value: options.filter(o => fm.m.allow.some(a => a.toLowerCase() === o.v.toLowerCase())).map(o => o.v)
                                onChose: list => Focus.update(fm.m.id, { allow: list })
                            }
                        }
                        Setting {
                            label: "Night light"; words: "focus night light warm"
                            Choice { options: [{ v: "", t: "Keep" }, { v: "on", t: "On" }, { v: "off", t: "Off" }]; value: fm.m.nightLight; onChose: v => Focus.update(fm.m.id, { nightLight: v }) }
                        }
                        Setting {
                            label: "Wallpaper"; hint: fm.m.wallpaper ? (fm.m.wallpaper.id ? "A live wallpaper" : fm.m.wallpaper.path.replace(/^.*\//, "")) : "Keeps yours"; words: "focus wallpaper background"
                            Row {
                                spacing: 6
                                Word { text: "Use the current one"; glyph: "wallpaper"; onHit: Focus.update(fm.m.id, { wallpaper: Wallpaper.kind === "live" ? { id: Wallpaper.current } : { path: Wallpaper.current } }) }
                                Word { visible: !!fm.m.wallpaper; text: "Keep mine"; onHit: Focus.update(fm.m.id, { wallpaper: null }) }
                            }
                        }
                        Setting {
                            label: "Schedule"; hint: fm.m.schedule.on ? "From–to, on these days (overnight works)" : "Off"; words: "focus schedule time days automatic"
                            Row {
                                spacing: 8
                                Row {
                                    visible: fm.m.schedule.on
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Repeater {
                                        model: FJ.DAYS
                                        Chip {
                                            required property var modelData
                                            text: modelData.t; on: fm.m.schedule.days.includes(modelData.v)
                                            onHit: Focus.update(fm.m.id, { schedule: Object.assign({}, fm.m.schedule, { days: on ? fm.m.schedule.days.filter(d => d !== modelData.v) : [...fm.m.schedule.days, modelData.v] }) })
                                        }
                                    }
                                }
                                Field { visible: fm.m.schedule.on; anchors.verticalCenter: parent.verticalCenter; width: 62; text: fm.m.schedule.from
                                    onAccepted: if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) Focus.update(fm.m.id, { schedule: Object.assign({}, fm.m.schedule, { from: text }) }) }
                                Field { visible: fm.m.schedule.on; anchors.verticalCenter: parent.verticalCenter; width: 62; text: fm.m.schedule.to
                                    onAccepted: if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) Focus.update(fm.m.id, { schedule: Object.assign({}, fm.m.schedule, { to: text }) }) }
                                Toggle { anchors.verticalCenter: parent.verticalCenter; checked: fm.m.schedule.on; onToggled: Focus.update(fm.m.id, { schedule: Object.assign({}, fm.m.schedule, { on: !fm.m.schedule.on }) }) }
                            }
                        }
                        Setting {
                            label: "While an app is open"; hint: "Pick open apps, or type a window class (* matches anything)"; words: "focus app open game automatic"
                            Row {
                                spacing: 8
                                Field { anchors.verticalCenter: parent.verticalCenter; width: 130; placeholder: "or type: steam_app_*"; onAccepted: if (text.trim()) { Focus.update(fm.m.id, { apps: [...fm.m.apps, text.trim()] }); text = ""; } }
                                Dropdown {
                                    anchors.verticalCenter: parent.verticalCenter
                                    multi: true
                                    placeholder: "None"
                                    menuWidth: 240
                                    // what's open now, and what it already has
                                    options: [...new Set([...fm.m.apps, ...Focus.classes])].map(c => ({ v: c, t: c }))
                                    value: fm.m.apps
                                    onChose: list => Focus.update(fm.m.id, { apps: list })
                                }
                            }
                        }
                        Setting {
                            label: "Remove this mode"; words: "focus delete remove"; last: true
                            Word { text: "Remove"; glyph: "delete"; onHit: Focus.remove(fm.m.id) }
                        }
                    }
                }
                Group {
                    title: "More"
                    Setting {
                        label: "New mode"; hint: "Starts empty: pick what it changes"; words: "focus add new mode"
                        Row {
                            spacing: 8
                            Field { id: newMode; anchors.verticalCenter: parent.verticalCenter; placeholder: "Name, e.g. Reading"; onAccepted: addMode.hit() }
                            Word { id: addMode; anchors.verticalCenter: parent.verticalCenter; text: "Add"; glyph: "add"; accent: true; onHit: { if (newMode.text.trim()) { Focus.add(newMode.text); newMode.text = ""; } } }
                        }
                    }
                    Setting {
                        label: "Back to Work, Game and Night"; hint: "Your modes are replaced by bead's three"; words: "focus defaults reset"; last: true
                        Word { text: "Restore"; glyph: "restart_alt"; onHit: Focus.restoreDefaults() }
                    }
                }
            }

            // ── Widgets (services/Widgets.qml) ──
            Page {
                pid: "widgets"
                Repeater {
                    // by id: editing one keeps its rows in place
                    model: ScriptModel { values: Widgets.config.map(w => w.id) }
                    Group {
                        id: wg
                        required property string modelData
                        readonly property var w: Widgets.items.find(x => x.id === modelData) ?? ({ id: modelData, label: modelData, icon: "widgets", fields: {}, value: "", tone: "", every: 60, template: "command" })
                        readonly property var tpl: WJ.template(w.template)
                        title: w.label
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: ep => Menus.open(parent, ep.position.x, ep.position.y, [
                                { t: wg.w.pinned ? "Take off the island" : "Keep on the island", g: "keep", act: () => Widgets.setPinned(wg.w.id, !wg.w.pinned) },
                                { t: "Check now", g: "refresh", act: () => Widgets.refresh(wg.w.id) },
                                { t: "Move up", g: "arrow_upward", act: () => Widgets.move(wg.w.id, -1) },
                                { t: "Move down", g: "arrow_downward", act: () => Widgets.move(wg.w.id, 1) },
                                { sep: true },
                                { t: "Remove", g: "delete", danger: true, act: () => Widgets.remove(wg.w.id) }
                            ])
                        }
                        Setting {
                            label: "On the island"
                            hint: (wg.tpl?.name ?? "") + " · showing " + (wg.w.value || "…")
                                + (wg.w.pinned && Widgets.chips.shown.every(c => c.id !== wg.w.id) ? " · the island shows " + Widgets.maxPinned + " at most" : "")
                            words: "widget pin island " + wg.w.label
                            Toggle { checked: wg.w.pinned; onToggled: Widgets.setPinned(wg.w.id, !wg.w.pinned) }
                        }
                        Setting {
                            label: "Name"; words: "widget name label"
                            Field { width: 200; text: wg.w.label; onAccepted: if (text.trim()) Widgets.update(wg.w.id, { label: text }) }
                        }
                        Repeater {
                            model: wg.tpl?.fields ?? []
                            Setting {
                                id: wf
                                required property var modelData
                                label: modelData.label; hint: modelData.choices ? "" : modelData.optional ? "Optional · Enter saves" : "Enter saves"; words: "widget " + modelData.label
                                Loader {
                                    sourceComponent: wf.modelData.choices ? wChoice : wField
                                    Component {
                                        id: wField
                                        Field {
                                            width: 300
                                            placeholder: wf.modelData.placeholder
                                            text: wg.w.fields[wf.modelData.key] ?? ""
                                            onAccepted: Widgets.update(wg.w.id, { fields: Object.assign({}, wg.w.fields, { [wf.modelData.key]: text }) })
                                        }
                                    }
                                    Component {
                                        id: wChoice
                                        Dropdown {
                                            options: wf.modelData.choices
                                            value: wg.w.fields[wf.modelData.key] ?? ""
                                            onChose: v => Widgets.update(wg.w.id, { fields: Object.assign({}, wg.w.fields, { [wf.modelData.key]: v }) })
                                        }
                                    }
                                }
                            }
                        }
                        Setting {
                            label: "Check every"; hint: "Seconds (5 at least)"; words: "widget interval every seconds"
                            Field { width: 70; text: String(wg.w.every); onAccepted: { const n = parseInt(text); if (n >= 5) Widgets.update(wg.w.id, { every: n }); } }
                        }
                        Setting {
                            label: "Remove this widget"; words: "widget delete remove"; last: true
                            Row {
                                spacing: 6
                                Word { text: "Check now"; glyph: "refresh"; onHit: Widgets.refresh(wg.w.id) }
                                Word { text: "Remove"; glyph: "delete"; onHit: Widgets.remove(wg.w.id) }
                            }
                        }
                    }
                }
                Group {
                    id: nw
                    title: "New widget"
                    property string tid: "server"
                    property var draft: ({})
                    property string name: ""
                    readonly property var tpl: WJ.template(tid)
                    onTidChanged: { draft = {}; Widgets.preview = null; }
                    function clear(): void { draft = {}; name = ""; Widgets.preview = null; tid = ""; tid = "server"; }
                    Setting {
                        label: "Kind"; hint: nw.tpl.hint; words: "widget new add template kind server github number toggle command"
                        Dropdown {
                            options: WJ.TEMPLATES.map(t => ({ v: t.id, t: t.name, g: t.icon }))
                            value: nw.tid
                            onChose: v => nw.tid = v
                        }
                    }
                    Repeater {
                        model: nw.tpl.fields
                        Setting {
                            id: nf
                            required property var modelData
                            label: modelData.label; hint: modelData.optional ? "Optional" : ""; words: "widget new " + modelData.label
                            Loader {
                                sourceComponent: nf.modelData.choices ? nChoice : nField
                                Component {
                                    id: nField
                                    Field {
                                        width: 300
                                        placeholder: nf.modelData.placeholder
                                        text: nw.draft[nf.modelData.key] ?? ""
                                        onTextChanged: if ((nw.draft[nf.modelData.key] ?? "") !== text) nw.draft = Object.assign({}, nw.draft, { [nf.modelData.key]: text })
                                        onAccepted: Widgets.test(nw.tid, nw.draft)
                                    }
                                }
                                Component {
                                    id: nChoice
                                    Dropdown {
                                        options: nf.modelData.choices
                                        value: nw.draft[nf.modelData.key] ?? nf.modelData.choices[0].v
                                        onChose: v => nw.draft = Object.assign({}, nw.draft, { [nf.modelData.key]: v })
                                    }
                                }
                            }
                        }
                    }
                    Setting {
                        label: "Name"; hint: "Optional"; words: "widget new name"
                        Field { width: 200; placeholder: nw.tpl.name; text: nw.name; onTextChanged: nw.name = text }
                    }
                    Setting {
                        label: "Preview"
                        hint: Widgets.previewing ? "Checking…" : Widgets.preview ? "What it shows now" : "Try it to see what it shows"
                        words: "widget preview try test"
                        Row {
                            spacing: 10
                            // the chip, as the island will show it
                            Rectangle {
                                visible: Widgets.preview !== null
                                anchors.verticalCenter: parent.verticalCenter
                                width: pv.width + 24; height: 30; radius: 15
                                color: Theme.frame
                                Row {
                                    id: pv
                                    anchors.centerIn: parent
                                    spacing: 5
                                    readonly property var p: Widgets.preview ?? ({ value: "", tone: "" })
                                    Icon { anchors.verticalCenter: parent.verticalCenter; name: pv.p.icon || nw.tpl.icon; size: 16; fill: 1; color: pv.p.tone ? Theme.tone(pv.p.tone) : Theme.subtext }
                                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: Theme.small; font.weight: Font.Medium; color: Theme.text; text: pv.p.value }
                                }
                            }
                            Word { anchors.verticalCenter: parent.verticalCenter; text: "Try it"; glyph: "play_arrow"; onHit: Widgets.test(nw.tid, nw.draft) }
                        }
                    }
                    Setting {
                        label: "Add it"; hint: Widgets.chips.shown.length < Widgets.maxPinned ? "It goes on the island too" : "The island is full: it goes on the dashboard"; words: "widget new add create"; last: true
                        Word {
                            text: "Add"; glyph: "add"; accent: true
                            onHit: {
                                const fields = Object.assign({}, ...nw.tpl.fields.filter(f => f.choices).map(f => ({ [f.key]: f.choices[0].v })), nw.draft);
                                if (Widgets.add(nw.tid, fields, nw.name, Widgets.chips.shown.length < Widgets.maxPinned)) nw.clear();
                                else Widgets.preview = { value: "fill in the fields", tone: "warning" };
                            }
                        }
                    }
                }
            }

            // ── Customise (config/look.js) ──
            Page {
                pid: "presets"
                Group {
                    title: "Presets"
                    Repeater {
                        model: L.PRESETS
                        Pick {
                            required property var modelData
                            label: modelData.name; hint: modelData.d; words: "preset look"
                            on: Look.active === modelData.id
                            onPicked: Look.apply(modelData.id)
                        }
                    }
                    Repeater {
                        model: Object.keys(Look.presets)
                        Setting {
                            id: mine
                            required property string modelData
                            label: modelData; hint: "Saved · " + Object.keys(Look.presets[modelData] ?? {}).length + " changes"; words: "preset saved mine"
                            clickable: true
                            onClicked: Look.apply(modelData)
                            Row {
                                spacing: 8
                                Btn { anchors.verticalCenter: parent.verticalCenter; glyph: "content_copy"; onHit: { Look.apply(mine.modelData); Look.copyLook(mine.modelData); win.lookNote = "Copied “" + mine.modelData + "”: paste it anywhere to share it"; } }
                                Btn { anchors.verticalCenter: parent.verticalCenter; glyph: "delete"; onHit: { const n = mine.modelData; mine.leave(() => Look.deletePreset(n)); } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24; height: 24; radius: 12
                                    color: Look.active === mine.modelData ? Theme.tone("action") : "transparent"
                                    border.width: Look.active === mine.modelData ? 0 : 2
                                    border.color: Qt.alpha(Theme.text, 0.25)
                                    Icon { anchors.centerIn: parent; visible: Look.active === mine.modelData; name: "check"; size: 16; color: Theme.frame }
                                }
                            }
                        }
                    }
                }
                Group {
                    title: "Your look"
                    Setting {
                        label: "Save as a preset"; hint: Look.active ? "This is “" + (L.PRESETS.find(p => p.id === Look.active)?.name ?? Look.active) + "”" : L.changed(Look.v).length + " changes from bead's defaults"; words: "save preset name"
                        Row {
                            spacing: 8
                            Field { id: presetName; anchors.verticalCenter: parent.verticalCenter; placeholder: "Name"; onAccepted: saveBtn.hit() }
                            Word { id: saveBtn; anchors.verticalCenter: parent.verticalCenter; text: "Save"; glyph: "bookmark_add"; accent: true
                                onHit: { const e = Look.savePreset(presetName.text); win.lookNote = e || "Saved “" + presetName.text.trim() + "”"; if (!e) presetName.text = ""; } }
                        }
                    }
                    Setting {
                        label: "Share it"; hint: "As text on the clipboard, or a file in " + Look.exportDir.replace(Quickshell.env("HOME"), "~"); words: "export copy share file"
                        Row {
                            spacing: 8
                            Word { text: "Copy"; glyph: "content_copy"; onHit: { Look.copyLook(""); win.lookNote = "Copied: paste it to a friend, or into their Settings"; } }
                            Word { text: "Save file"; glyph: "download"; onHit: win.lookNote = "Saved " + Look.exportFile("").replace(Quickshell.env("HOME"), "~") }
                        }
                    }
                    Setting {
                        label: "Use a shared look"; hint: "Copy one someone shared, then paste it here: it's saved as a preset and applied"; words: "import paste clipboard"
                        Word { text: "Paste"; glyph: "content_paste"; accent: true; onHit: Look.importClipboard() }
                    }
                    Setting {
                        label: "Start over"; hint: "Every Customise page back to bead's defaults (your saved presets stay)"; words: "reset defaults"; last: true
                        Word { text: "Reset all"; glyph: "restart_alt"; onHit: { Look.resetAll(); win.lookNote = "Back to bead's defaults"; } }
                    }
                }
                Text {
                    visible: win.lookNote !== "" && !win.searching
                    leftPadding: 4
                    font.family: Theme.font; font.pixelSize: Theme.small; color: Theme.tone("action")
                    text: win.lookNote
                }
            }
            Repeater {
                model: L.PAGES
                Page {
                    id: cp
                    required property var modelData
                    pid: modelData.id
                    LookPageBody { pid: cp.modelData.id }
                    // pop-ups: a rule for each app that has sent one
                    Group {
                        visible: cp.modelData.id === "popups" && shown
                        title: "Per app"
                        Setting {
                            visible: match && Notifs.apps.length === 0
                            label: "No apps yet"; hint: "Apps show here once they've sent a notification"; words: "per app rules"; last: true
                        }
                        Repeater {
                            model: ScriptModel { values: cp.modelData.id === "popups" ? Notifs.apps : [] }
                            Setting {
                                id: ar
                                required property string modelData
                                required property int index
                                label: modelData; hint: ({ normal: "Pop-up and island", corner: "Only the corner pop-up", island: "Only on the island", sticky: "Stays until dismissed", quiet: "Only in the history" })[Notifs.rule({ appName: modelData })]
                                words: "per app rule notifications " + modelData
                                last: index === Notifs.apps.length - 1
                                Dropdown { options: L.APP_RULES; value: Notifs.rule({ appName: ar.modelData }); onChose: v => Notifs.setRule(ar.modelData, v) }
                            }
                        }
                    }
                    Row {
                        visible: !win.searching
                        spacing: 10
                        Word { text: "Reset this page"; glyph: "restart_alt"; onHit: Look.resetPage(cp.modelData.id) }
                        Label { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.small
                            text: { const n = L.changed(Look.v, cp.modelData.id).length; return n ? n + (n === 1 ? " change" : " changes") + " from bead's defaults" : "All at bead's defaults"; } }
                    }
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
                                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium; color: Theme.text; text: "The island" }
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
                        label: "WhatsApp"; hint: "An inbox in the bar, from WhatsApp's notifications (its app, or web.whatsapp.com)"; words: "messages chat whatsapp inbox"
                        Toggle { checked: Settings.whatsapp; onToggled: Settings.whatsapp = !Settings.whatsapp }
                    }
                    Setting {
                        label: "Telegram"; hint: "An inbox in the bar, from Telegram's notifications; reply right from it"; words: "messages chat telegram inbox"
                        Toggle { checked: Settings.telegram; onToggled: Settings.telegram = !Settings.telegram }
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
                    font.pixelSize: Theme.caption
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
                                    Text { id: pk; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: Theme.caption; color: Theme.text; text: parent.modelData.split(" ")[0] }
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
                Label { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.body; text: "No setting matches that" }
            }
        }
    }

    // ── a dropdown's ddMenu, over everything; a click outside or scrolling closes it ──
    Item {
        anchors.fill: parent
        z: 100
        visible: win.menuFor !== null
        MouseArea { anchors.fill: parent; onClicked: win.closeMenu(); onWheel: win.closeMenu() }
        Rectangle {
            id: ddMenu
            readonly property var src: win.menuFor
            readonly property var opts: src?.options ?? []
            readonly property real rowH: 32
            function place(): void {
                if (!src) return;
                const p = src.mapToItem(win.contentItem, 0, 0);
                const h = Math.min(opts.length * rowH + 12, 300);
                width = Math.max(src.width, src.menuWidth, 180);
                height = h;
                x = Math.min(p.x + src.width - width, win.width - width - 12);
                x = Math.max(12, x);
                y = p.y + src.height + 6 + h < win.height - 8 ? p.y + src.height + 6 : Math.max(8, p.y - h - 6);
                ddList.positionViewAtIndex(Math.max(0, opts.findIndex(o => src.multi ? false : o.v === src.value)), ListView.Center);
                pop.restart();
            }
            radius: 14
            color: Qt.tint(Theme.frame, Qt.alpha(Theme.text, 0.07))
            border.width: 1
            border.color: Qt.alpha(Theme.text, 0.1)
            transformOrigin: Item.Top
            ParallelAnimation {
                id: pop
                NumberAnimation { target: ddMenu; property: "opacity"; from: 0; to: 1; duration: Motion.ms(140) }
                NumberAnimation { target: ddMenu; property: "scale"; from: 0.94; to: 1; duration: Motion.ms(200); easing.type: Easing.OutBack }
            }
            MouseArea { anchors.fill: parent }   // clicks between rows stay in the ddMenu
            ListView {
                id: ddList
                anchors.fill: parent; anchors.margins: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ddMenu.opts
                delegate: Rectangle {
                    id: mi
                    required property var modelData
                    readonly property bool ticked: ddMenu.src ? (ddMenu.src.multi ? (ddMenu.src.value ?? []).includes(modelData.v) : ddMenu.src.value === modelData.v) : false
                    width: ddList.width; height: ddMenu.rowH; radius: 9
                    color: Qt.alpha(Theme.text, mia.containsMouse ? 0.08 : 0)
                    Row {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Icon { visible: !!mi.modelData.g; anchors.verticalCenter: parent.verticalCenter; name: mi.modelData.g ?? ""; size: 16; color: Theme.text }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: mi.width - 54 - (mi.modelData.g ? 24 : 0)
                            elide: Text.ElideRight
                            font.family: mi.modelData.font ?? Theme.font; font.pixelSize: Theme.small
                            font.weight: mi.ticked ? Font.Medium : Font.Normal
                            color: Theme.text
                            text: mi.modelData.t
                        }
                    }
                    Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; visible: mi.ticked; name: "check"; size: 16; color: Theme.tone("action") }
                    MouseArea {
                        id: mia; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const d = ddMenu.src;
                            if (!d) return;
                            if (d.multi) {
                                const cur = Array.from(d.value ?? []);
                                d.chose(mi.ticked ? cur.filter(x => x !== mi.modelData.v) : [...cur, mi.modelData.v]);
                            } else { d.chose(mi.modelData.v); win.closeMenu(); }
                        }
                    }
                }
            }
        }
    }
}
