pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.components
import qs.config
import qs.services

// The island while you give a voice command (hold Super+Space):
//   listening     a waveform of your voice, the words appearing underneath
//   transcribing  the bars collapse into the middle and melt into a goo blob
//   thinking      the blob wobbles faster while the model picks an action
//   done          the blob swells, then the island becomes the result
//   a question    (Voice.ask: "Which server?") the options as chips under the
//                 words; it listens without the key, or tap one
Item {
    id: root
    property bool active: false

    readonly property real wantW: 420
    readonly property real wantH: Voice.question ? 160 : 116
    readonly property string phase: Voice.state
    readonly property bool listening: phase === "listening"
    readonly property bool asking: Voice.question !== null

    // ── the waveform: the last ~2.4 s of your level, newest in the middle,
    // spreading out to both sides ──
    readonly property int bars: 33
    property var history: []
    // auto-gain: scale to the loudest you've been lately, so a quiet mic
    // still fills the card
    property real gain: 0.2
    Timer {
        interval: 50
        repeat: true
        running: root.active && root.listening
        onTriggered: {
            const h = root.history.slice(-(Math.ceil(root.bars / 2) - 1));
            // a breath of motion even in silence, so it reads as live
            root.gain = Math.max(0.2, Voice.level, root.gain * 0.985);
            h.push(Math.max(Math.min(1, Voice.level / root.gain), 0.05 + 0.04 * Math.random()));
            root.history = h;
        }
    }
    onActiveChanged: if (active) { history = []; gain = 0.2; known = gatherKnown(); }

    // ── the words it'll act on, lit up as you say them: apps, open windows,
    // your SSH hosts and phrases, workspace numbers ──
    property var known: []   // squashed names ("curseforge", "homelab")
    function squash(t: string): string { return String(t).toLowerCase().replace(/[^a-z0-9]/g, ""); }
    function gatherKnown(): var {
        const out = new Set();
        for (const e of DesktopEntries.applications.values) if (e.name && !e.noDisplay) out.add(squash(e.name));
        for (const t of Hyprland.toplevels.values) out.add(squash(String(t.wayland?.appId ?? "").split(".").pop()));
        for (const h of Voice.sshHosts) out.add(squash(h));
        for (const c of Voice.custom) for (const p of c.phrases) out.add(squash(p));
        out.delete("");
        return [...out].filter(k => k.length >= 2);
    }
    // the words as rich text: runs of 1-3 words that are (or sound like) a known name
    function marked(t: string): string {
        const esc = x => x.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const words = t.split(" ");
        const lit = new Array(words.length).fill(false);
        const isKnown = g => g.length >= 2 && (known.includes(g)
            || (g.length >= 5 && known.some(k => Math.abs(k.length - g.length) <= 3 && Apps.similar(g, k) >= 0.8)));
        for (let n = 3; n >= 1; n--) for (let i = 0; i + n <= words.length; i++) {
            if (lit.slice(i, i + n).some(x => x)) continue;
            const g = squash(words.slice(i, i + n).join(""));
            // short single words ("on", "it") only when they're exactly a name
            if (n === 1 && g.length < 4 && !Voice.sshHosts.some(h => squash(h) === g)) continue;
            if (isKnown(g)) for (let j = i; j < i + n; j++) lit[j] = true;
        }
        // "workspace 5", "window three"
        const ws = /^(workspace|window|desktop|screen)$/i;
        for (let i = 0; i + 1 < words.length; i++)
            if (ws.test(words[i]) && /^(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\W*$/i.test(words[i + 1])) lit[i] = lit[i + 1] = true;
        const accent = Theme.tone("action");
        let html = "", on = false;
        for (let i = 0; i < words.length; i++) {
            if (lit[i] && !on) { html += "<font color=\"" + accent + "\"><b>"; on = true; }
            if (!lit[i] && on) { html += "</b></font>"; on = false; }
            html += esc(words[i]) + (i < words.length - 1 ? " " : "");
        }
        return html + (on ? "</b></font>" : "");
    }

    // 0 while listening → 1 once released: the bars gather and the blob takes over
    property real collapse: listening || !active || (asking && phase === "") ? 0 : 1
    Behavior on collapse { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }

    Item {
        id: stage
        x: 22
        y: 12
        width: parent.width - 44
        height: 54

        Repeater {
            model: root.bars
            Rectangle {
                id: bar
                required property int index
                // distance from the middle bar: 0 = newest sample
                readonly property int k: Math.abs(index - (root.bars - 1) / 2)
                readonly property real v: root.history.length > k ? root.history[root.history.length - 1 - k] : 0.04
                // taper towards the edges, so it reads as a voice, not a meter
                readonly property real taper: Math.pow(1 - k / ((root.bars - 1) / 2 + 1), 0.6)
                readonly property real fullX: index * (stage.width / root.bars) + (stage.width / root.bars - width) / 2
                width: 3.5
                radius: 1.75
                // gather into the middle as it collapses
                x: fullX + (stage.width / 2 - width / 2 - fullX) * root.collapse
                height: Math.max(4, (stage.height - 8) * Math.min(1, v) * taper) * (1 - root.collapse * 0.8)
                y: (stage.height - height) / 2
                color: Theme.tone("action")
                opacity: (0.35 + 0.65 * taper) * (1 - Math.max(0, root.collapse - 0.55) / 0.45)
                Behavior on height { enabled: root.listening; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }

        // the goo blob, melting in as the bars arrive in the middle
        ShaderEffect {
            id: blob
            anchors.centerIn: parent
            width: 150
            height: stage.height + 16
            visible: opacity > 0.01
            opacity: Math.min(1, Math.max(0, (root.collapse - 0.35) / 0.4)) * (root.phase === "done" ? 0 : 1)
            Behavior on opacity { NumberAnimation { duration: root.phase === "done" ? 260 : 120 } }
            fragmentShader: Qt.resolvedUrl("../../shaders/blob.frag.qsb")
            property size size: Qt.size(width, height)
            property real time: 0
            property real merge: Math.min(1, Math.max(0, (root.collapse - 0.3) / 0.7))
            property real energy: root.phase === "thinking" ? 1 : 0
            Behavior on energy { NumberAnimation { duration: 400 } }
            property real pop: root.phase === "done" ? 1 : 0
            Behavior on pop { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property color fill: Theme.tone("action")
            property color glow: Qt.alpha(Theme.tone("action"), 0.35)
            NumberAnimation on time {
                running: blob.visible
                from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite
            }
        }
    }

    // ── the words: live while you talk, then what was heard ──
    Text {
        id: words
        x: 28
        width: parent.width - 56
        y: stage.y + stage.height + 8
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideLeft // the newest words stay in view
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Voice.partial ? Font.Medium : Font.Normal
        color: Voice.partial ? Theme.text : Theme.subtext
        textFormat: Text.StyledText
        text: Voice.partial ? root.marked(Voice.partial) : (root.asking ? Voice.question.prompt : root.listening ? "Listening…" : "")
        Behavior on color { ColorAnimation { duration: 200 } }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: words.y + words.height + 2
        font.pixelSize: 11
        opacity: root.listening || root.asking ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }
        text: root.phase === "transcribing" ? "Catching the last words…" : root.phase === "thinking" ? "Working out what to do…" : ""
    }

    // the question's options: say one, or tap it
    Row {
        id: chips
        visible: root.asking
        anchors.horizontalCenter: parent.horizontalCenter
        y: words.y + words.height + 10
        spacing: 6
        Repeater {
            model: root.asking ? Voice.question.options.slice(0, 6) : []
            Rectangle {
                id: chip
                required property string modelData
                required property int index
                height: 28
                width: chipText.implicitWidth + 24
                radius: 14
                color: chipHover.hovered ? Qt.alpha(Theme.tone("action"), 0.3) : Qt.alpha(Theme.text, 0.08)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    text: chip.modelData
                }
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Voice.answer(chip.modelData) }
            }
        }
    }

    TapHandler { enabled: !root.asking; onTapped: root.listening ? Voice.stop() : Voice.cancel() }
}
