pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings (config/Settings.qml, saved to ~/.config/bead/settings.json).
// A rail of sections on the left (the highlight slides between them); the
// section's rows on the right, in two columns, settling in one after another.
// Changes apply at once.
Item {
    id: root

    property int section: 0
    readonly property var sections: [
        { t: "Idle", g: "bedtime", d: "When the screen locks, blanks and sleeps" },
        { t: "Looks", g: "palette", d: "Colours, the bar and where the island lives" },
        { t: "Assistant", g: "graphic_eq", d: "Claude in the launcher, voice and dictation" },
        { t: "System", g: "deployed_code", d: "Updates, weather units and the settings file" }
    ]
    readonly property real colW: (pane.width - 40 - 24) / 2

    IpcHandler {
        target: "settings"
        function section(n: int): void { root.section = Math.max(0, Math.min(root.sections.length - 1, n)); }
    }

    // ── pieces ──
    // a labelled row with something on the right
    component Line: Item {
        id: line
        property string label: ""
        property string hint: ""
        default property alias trailing: slot.data
        width: root.colW
        height: 44
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - slot.width - 8
            Text { width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.text; text: line.label }
            Label { visible: line.hint !== ""; width: parent.width; elide: Text.ElideRight; font.pixelSize: 10; text: line.hint }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }
    component Btn: Rectangle {
        id: b
        property string glyph: ""
        signal hit()
        width: 24; height: 24; radius: 12
        color: Qt.alpha(Theme.text, bma.pressed ? 0.16 : bma.containsMouse ? 0.11 : 0.06)
        Icon { anchors.centerIn: parent; name: b.glyph; size: 15; color: Theme.text }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.hit() }
    }
    // minutes: −  value  +  (0 shows "Never")
    component Minutes: Row {
        id: mins
        property real value: 0
        signal chose(real v)
        readonly property list<real> stops: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        // to the next stop up or down (a value between stops snaps to one)
        function step(d: int): void {
            const next = d > 0 ? stops.find(x => x > value) : [...stops].reverse().find(x => x < value);
            if (next !== undefined) chose(next);
        }
        spacing: 2
        Btn { glyph: "remove"; onHit: mins.step(-1) }
        // the value rolls: up when it grows, down when it shrinks
        Item {
            id: roll
            width: 52
            height: 24
            clip: true
            anchors.verticalCenter: parent.verticalCenter
            function label(v: real): string { return v <= 0 ? "Never" : v < 60 ? v + " min" : (v / 60) + " h"; }
            property real shown: mins.value
            property real dir: 1
            property real t: 1 // 0 → 1 over a change
            Connections {
                target: mins
                function onValueChanged(): void {
                    roll.dir = mins.value > roll.shown ? 1 : -1;
                    oldText.text = roll.label(roll.shown);
                    roll.shown = mins.value;
                    rollAnim.restart();
                }
            }
            NumberAnimation { id: rollAnim; target: roll; property: "t"; from: 0; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            Text {
                id: oldText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -roll.dir * 18 * roll.t
                opacity: 1 - Math.min(1, roll.t * 1.6)
                visible: roll.t < 1
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Theme.text
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: roll.dir * 18 * (1 - roll.t)
                opacity: Math.min(1, roll.t * 1.4)
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: mins.value > 0 ? Theme.text : Theme.subtext
                text: roll.label(roll.shown)
            }
        }
        Btn { glyph: "add"; onHit: mins.step(1) }
        WheelHandler { onWheel: e => mins.step(e.angleDelta.y > 0 ? 1 : -1) }
    }
    // a segmented choice
    component Choice: Rectangle {
        id: ch
        property list<var> options: []   // { v, t }
        property string value: ""
        signal chose(string v)
        width: seg.width + 4
        height: 26
        radius: 13
        color: Qt.alpha(Theme.text, 0.06)
        Rectangle { // the pill slides to the chosen one
            readonly property Item at: seg.children[ch.options.findIndex(o => o.v === ch.value)] ?? null
            visible: !!at
            x: 2 + (at?.x ?? 0)
            y: 2
            width: at?.width ?? 0
            height: 22
            radius: 11
            color: Theme.tone("action")
            Behavior on x { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
        }
        Row {
            id: seg
            x: 2; y: 2
            Repeater {
                model: ch.options
                Item {
                    id: opt
                    required property var modelData
                    width: optText.implicitWidth + 18
                    height: 22
                    Text {
                        id: optText
                        anchors.centerIn: parent
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: ch.value === opt.modelData.v ? Theme.frame : Theme.text
                        Behavior on color { ColorAnimation { duration: 150 } }
                        text: opt.modelData.t
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.chose(opt.modelData.v) }
                }
            }
        }
    }

    // a small round-cornered button with words
    component Action: Rectangle {
        id: act
        property string text: ""
        property string glyph: ""
        property bool accent: false
        signal hit()
        width: actRow.implicitWidth + 22
        height: 28
        radius: 14
        color: accent ? Theme.tone("action") : Qt.alpha(Theme.text, aMa.pressed ? 0.16 : aMa.containsMouse ? 0.11 : 0.06)
        scale: aMa.pressed ? 0.94 : 1
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
        Row {
            id: actRow
            anchors.centerIn: parent
            spacing: 5
            Icon { visible: act.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; name: act.glyph; size: 15; color: act.accent ? Theme.frame : Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                color: act.accent ? Theme.frame : Theme.text
                text: act.text
            }
        }
        MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.hit() }
    }
    // a keyboard key
    component Key: Rectangle {
        property string text: ""
        width: Math.max(24, kt.implicitWidth + 12)
        height: 22
        radius: 6
        color: Qt.alpha(Theme.text, 0.08)
        border.width: 1
        border.color: Qt.alpha(Theme.text, 0.1)
        Text { id: kt; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.text; text: parent.text }
    }

    // ── the rail ──
    Rectangle {
        id: rail
        width: 208
        height: parent.height
        radius: 18
        color: Qt.alpha(Theme.text, 0.04)
        Rectangle { // the highlight, sliding to the chosen section
            x: 8
            y: 8 + root.section * 52
            width: parent.width - 16
            height: 48
            radius: 14
            color: Qt.alpha(Theme.text, 0.09)
            Behavior on y { SpringAnimation { spring: 5; damping: 0.36; epsilon: 0.2 } }
            Rectangle { // and a little bar on its edge
                x: 0; anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 20; radius: 1.5
                color: Theme.tone("action")
            }
        }
        Column {
            x: 8; y: 8
            width: parent.width - 16
            spacing: 4
            Repeater {
                model: root.sections
                Item {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool on: root.section === index
                    width: parent.width
                    height: 48
                    Icon {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        name: tab.modelData.g; size: 19; fill: tab.on ? 1 : 0
                        color: tab.on ? Theme.tone("action") : Theme.subtext
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        x: 46; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font; font.pixelSize: 13
                        font.weight: tab.on ? Font.DemiBold : Font.Medium
                        color: tab.on ? Theme.text : Theme.subtext
                        Behavior on color { ColorAnimation { duration: 150 } }
                        text: tab.modelData.t
                    }
                    // a dot when there's something to look at (updates waiting)
                    Rectangle {
                        visible: tab.index === 3 && Updates.count > 0
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7; radius: 3.5
                        color: Theme.tone("action")
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.section = tab.index }
                }
            }
        }
        WheelHandler { onWheel: e => root.section = Math.max(0, Math.min(root.sections.length - 1, root.section + (e.angleDelta.y > 0 ? -1 : 1))) }
    }

    // ── the pane ──
    Rectangle {
        id: pane
        x: rail.width + 12
        width: parent.width - x
        height: parent.height
        radius: 18
        color: Qt.alpha(Theme.text, 0.04)

        // section title
        Column {
            id: heading
            x: 20; y: 16
            spacing: 1
            Row {
                height: 22
                Repeater {
                    model: root.sections[root.section].t.split("")
                    Text {
                        id: letter
                        required property string modelData
                        required property int index
                        readonly property real p: Math.max(0, Math.min(1, rows.enter * 3 - index * 0.16))
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: Theme.text
                        text: modelData
                        opacity: p
                        transform: Translate { y: 9 * (1 - letter.p) * (1 - letter.p) }
                    }
                }
            }
            Label {
                id: desc
                font.pixelSize: 11
                text: root.sections[root.section].d
                readonly property real p: Math.max(0, Math.min(1, rows.enter * 2 - 0.35))
                opacity: p
                transform: Translate { x: -12 * (1 - desc.p) }
            }
        }

        // the rows of each section, two columns; a change replays the entrance
        Item {
            id: rows
            x: 20
            y: 66
            width: parent.width - 40
            height: parent.height - y - 14
            property real enter: 1
            Connections {
                target: root
                function onSectionChanged(): void { rows.enter = 0; enterAnim.restart(); }
            }
            NumberAnimation { id: enterAnim; target: rows; property: "enter"; to: 1; duration: 520; easing.type: Easing.OutCubic }

            // each row comes in a beat after the one before
            component In: Item {
                id: inItem
                property int order: 0
                readonly property real p: Math.max(0, Math.min(1, rows.enter * 2.2 - order * 0.18))
                opacity: p
                transform: Translate { y: 10 * (1 - inItem.p) }
            }

            // ── idle ──
            Grid {
                visible: root.section === 0
                columns: 2
                columnSpacing: 24
                rowSpacing: 2
                In { order: 0; width: root.colW; height: 44; Line { label: "Lock the screen"; Minutes { value: Settings.lockAfter; onChose: v => Settings.lockAfter = v } } }
                In { order: 1; width: root.colW; height: 44; Line { label: "Stay awake for media"; hint: "Nothing happens while audio plays"; Toggle { checked: Settings.pauseForMedia; onToggled: Settings.pauseForMedia = !Settings.pauseForMedia } } }
                In { order: 2; width: root.colW; height: 44; Line { label: "Turn the screen off"; Minutes { value: Settings.screenOffAfter; onChose: v => Settings.screenOffAfter = v } } }
                In { order: 3; width: root.colW; height: 44; Line { label: "Keep awake"; hint: "Never lock, blank or sleep (until you turn it off)"; Toggle { checked: Idle.keepAwake; onToggled: Idle.keepAwake = !Idle.keepAwake } } }
                In { order: 4; width: root.colW; height: 44; Line { label: "Suspend"; Minutes { value: Settings.suspendAfter; onChose: v => Settings.suspendAfter = v } } }
            }
            // the timeline: what happens when, on one line
            In {
                visible: root.section === 0
                order: 5
                x: root.colW + 24
                y: 2 * 46 + 6
                width: root.colW
                height: 64
                readonly property var steps: [
                    { m: Settings.lockAfter, t: "Lock", g: "lock" },
                    { m: Settings.screenOffAfter, t: "Screen off", g: "monitor" },
                    { m: Settings.suspendAfter, t: "Suspend", g: "bedtime" }
                ].filter(x => x.m > 0)
                readonly property real span: Math.max(1, ...steps.map(x => x.m)) * 1.08
                Rectangle {
                    id: tl
                    y: 30
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.alpha(Theme.text, 0.08)
                    Rectangle { // filled up to the last thing that happens
                        width: parent.width * (parent.parent.steps.length ? Math.max(...parent.parent.steps.map(x => x.m)) / parent.parent.span : 0) * rows.enter
                        height: parent.height; radius: 2
                        color: Qt.alpha(Theme.tone("action"), Idle.keepAwake ? 0.25 : 0.7)
                    }
                }
                Label { y: 42; font.pixelSize: 10; text: "Idle" }
                Repeater {
                    model: parent.steps
                    Item {
                        id: st
                        required property var modelData
                        x: tl.width * modelData.m / parent.span
                        Behavior on x { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.3 } }
                        Rectangle { x: -6; y: 26; width: 12; height: 12; radius: 6; color: Theme.tone("action"); border.width: 3; border.color: Theme.fill }
                        Icon { x: -8; y: 4; name: st.modelData.g; size: 16; color: Theme.subtext }
                        Label { x: -width / 2; y: 42; font.pixelSize: 10; font.features: { "tnum": 1 }; text: st.modelData.m < 60 ? st.modelData.m + " min" : st.modelData.m / 60 + " h" }
                    }
                }
            }

            // ── looks ──
            Grid {
                visible: root.section === 1
                columns: 2
                columnSpacing: 24
                rowSpacing: 2
                In {
                    order: 0; width: root.colW; height: 44
                    Line {
                        label: "Colours"
                        hint: Settings.theme === "sileo" ? "sileo's own palette" : "From the wallpaper"
                        Choice { options: [{ v: "wallpaper", t: "Wallpaper" }, { v: "sileo", t: "Sileo" }]; value: Settings.theme; onChose: v => Settings.theme = v }
                    }
                }
                In {
                    order: 1; width: root.colW; height: 44
                    Line {
                        label: "Main monitor"
                        hint: "Island and lock screen"
                        Choice { options: Quickshell.screens.map(s => ({ v: s.name, t: s.name })); value: Settings.home; onChose: v => Settings.islandScreen = v }
                    }
                }
                In {
                    order: 2; width: root.colW; height: 44
                    Line { label: "Window title in the bar"; hint: "Down the side, under the workspaces"; Toggle { checked: Settings.showTitle; onToggled: Settings.showTitle = !Settings.showTitle } }
                }
                In {
                    order: 3; width: root.colW; height: 44
                    Line { label: "Wallpaper"; hint: "Or pick one on the Wallpapers tab"; Action { text: "Shuffle"; glyph: "shuffle"; onHit: Wallpaper.random("all") } }
                }
            }
            // the palette in use
            In {
                visible: root.section === 1
                order: 4
                y: 2 * 46 + 22
                width: rows.width
                height: 60
                Label { font.pixelSize: 10; text: "Palette" }
                Row {
                    y: 20
                    spacing: 8
                    Repeater {
                        model: [Theme.tone("action"), Theme.text, Theme.subtext, Theme.frame, Theme.tone("success"), Theme.tone("warning"), Theme.tone("error")]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: 34; height: 34; radius: 17
                            color: modelData
                            border.width: 1
                            border.color: Qt.alpha(Theme.text, 0.12)
                            scale: Math.max(0, Math.min(1, rows.enter * 2.4 - 0.8 - index * 0.12))
                        }
                    }
                }
            }

            // ── assistant ──
            Grid {
                visible: root.section === 2
                columns: 2
                columnSpacing: 24
                rowSpacing: 2
                In {
                    order: 0; width: root.colW; height: 44
                    Line {
                        label: "Claude model"
                        hint: "For ? asks and spoken questions"
                        Choice { options: [{ v: "haiku", t: "Haiku" }, { v: "sonnet", t: "Sonnet" }, { v: "opus", t: "Opus" }]; value: Settings.askModel; onChose: v => Settings.askModel = v }
                    }
                }
                In {
                    order: 1; width: root.colW; height: 44
                    Line {
                        label: "Voice models"
                        hint: Voice.warm ? (Voice.serverReady ? "Loaded · unload after 4 min idle" : "Loading…") : "Not loaded · start with a voice command"
                        Action { visible: Voice.warm; text: "Unload"; glyph: "eject"; onHit: Voice.unload() }
                    }
                }
                In {
                    order: 2; width: root.colW; height: 44
                    Line {
                        label: "Voice command"
                        hint: "Hold, speak, let go"
                        Row { spacing: 4; Key { text: "Super" } Key { text: "Space" } }
                    }
                }
                In {
                    order: 3; width: root.colW; height: 44
                    Line {
                        label: "Dictation"
                        hint: "Types into whatever field has focus"
                        Row { spacing: 4; Key { text: "Super" } Key { text: "A" } }
                    }
                }
                In {
                    order: 4; width: root.colW; height: 44
                    Line {
                        label: "Microphone"
                        hint: Audio.micMuted ? "Muted: voice can't hear you" : "Listening is only ever while you hold the key"
                        Toggle { checked: !Audio.micMuted; onToggled: Audio.toggleMicMute() }
                    }
                }
            }

            // ── system ──
            Grid {
                visible: root.section === 3
                columns: 2
                columnSpacing: 24
                rowSpacing: 2
                In {
                    order: 0; width: root.colW; height: 44
                    Line {
                        label: Updates.checking ? "Checking for updates…" : Updates.count > 0 ? Updates.count + (Updates.count === 1 ? " update" : " updates") : "Up to date"
                        hint: Updates.count > 0 ? Updates.repo.length + " repo · " + Updates.aur.length + " AUR" : "Looks every 3 hours"
                        Row {
                            spacing: 6
                            Action { text: "Check"; glyph: "refresh"; onHit: Updates.check() }
                            Action { visible: Updates.count > 0; accent: true; text: "Update"; glyph: "download"; onHit: Updates.update() }
                        }
                    }
                }
                In {
                    order: 1; width: root.colW; height: 44
                    Line {
                        label: "Weather units"
                        Choice { options: [{ v: "auto", t: "Auto" }, { v: "celsius", t: "°C" }, { v: "fahrenheit", t: "°F" }]; value: Settings.units; onChose: v => Settings.units = v }
                    }
                }
                In {
                    order: 2; width: root.colW; height: 44
                    Line {
                        label: "Settings file"
                        hint: "~/.config/bead/settings.json · edits apply live"
                        Action { text: "Open"; glyph: "open_in_new"; onHit: Quickshell.execDetached(["xdg-open", (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/settings.json"]) }
                    }
                }
                In {
                    order: 3; width: root.colW; height: 44
                    Line {
                        label: "Restart bead"
                        hint: "Reloads the shell"
                        Action { text: "Restart"; glyph: "restart_alt"; onHit: Quickshell.execDetached(["bead", "restart"]) }
                    }
                }
            }
            // the waiting updates, a few by name
            In {
                visible: root.section === 3 && Updates.count > 0
                order: 4
                y: 2 * 46 + 4
                width: rows.width
                height: rows.height - y
                clip: true
                Label { font.pixelSize: 10; text: "Waiting · " + Updates.count + (wait.contentHeight > wait.height ? " · scroll for more" : "") }
                Flickable {
                    id: wait
                    y: 18
                    width: parent.width
                    // whole rows of chips only (24 tall, 6 apart): none cut in half
                    height: Math.max(24, Math.floor((parent.height - y + 6) / 30) * 30 - 6)
                    contentHeight: flow.height
                    clip: true
                    interactive: false
                    // a wheel notch moves one row, and it settles on a row
                    WheelHandler {
                        onWheel: e => {
                            const to = Math.round(wait.contentY / 30) * 30 + (e.angleDelta.y > 0 ? -30 : 30);
                            wait.contentY = Math.max(0, Math.min(wait.contentHeight - wait.height, to));
                        }
                    }
                    Behavior on contentY { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Flow {
                    id: flow
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [...Updates.repo, ...Updates.aur]
                        Rectangle {
                            required property string modelData
                            width: pk.implicitWidth + 16; height: 24; radius: 12
                            color: Qt.alpha(Theme.text, 0.06)
                            Text { id: pk; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 10; color: Theme.text; text: parent.modelData.split(" ")[0] }
                        }
                    }
                }
                }
            }
        }
    }
}
