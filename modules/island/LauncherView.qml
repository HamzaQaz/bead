pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// The island as a launcher: type to fuzzy-search apps (the ones you launch
// most float up), do maths (qalc: "2^10", "5 usd to eur"; Enter copies the
// answer), or start with ">" for actions (lock, suspend, log out, reboot,
// shut down, do not disturb, hide island, clear notifications, "timer 10m",
// stopwatch), or "?" to ask Claude (services/Ask.qml): the answer streams in
// below; Enter on an edited question asks a follow-up. Log out / reboot /
// shut down need a second Enter.
// Keys: Up/Down (Tab, Ctrl+J/K/N/P), Enter, Esc.
Item {
    id: root

    signal close()

    readonly property int rowH: 46
    readonly property int maxRows: 7
    readonly property int shown: Math.min(results.length, maxRows)
    readonly property bool asking: query.trim().startsWith("?")
    readonly property string askText: query.trim().slice(1).trim()
    readonly property bool answering: asking && Ask.active
    readonly property real wantW: answering ? 640 : 600
    readonly property real wantH: 58 + (answering ? answer.height + 16 : results.length ? shown * rowH + 14 : 52)

    property string query: ""
    property int current: 0
    property string confirming: ""   // action id waiting for a second Enter

    function reset(seed: string): void {
        Ask.clear();
        field.text = seed ?? "";
        current = 0;
        confirming = "";
        calc.result = "";
    }
    function focusField(): void { field.forceActiveFocus(); }

    // Claude's markdown -> rich text: code blocks in a monospace box, `inline
    // code`, **bold**, *italic*, headings, lists, paragraphs (Qt's own markdown
    // mode shows code as plain text). Also fine on a half-streamed answer.
    function md(src: string): string {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const codeBg = Qt.alpha(Theme.text, 0.08);
        const bg = "rgba(" + Math.round(codeBg.r * 255) + "," + Math.round(codeBg.g * 255) + "," + Math.round(codeBg.b * 255) + "," + codeBg.a.toFixed(2) + ")";
        const inline = t => esc(t)
            .replace(/`([^`]+)`/g, `<span style="font-family:monospace; background-color:${bg};">&nbsp;$1&nbsp;</span>`)
            .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
            .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>");
        const out = [];
        let code = null, list = null, para = [];
        const flushPara = () => { if (para.length) out.push("<p>" + para.map(inline).join("<br>") + "</p>"); para = []; };
        const flushList = () => { if (list) out.push(`<${list.tag}>` + list.items.map(i => "<li>" + inline(i) + "</li>").join("") + `</${list.tag}>`); list = null; };
        for (const line of src.split("\n")) {
            if (code !== null) {
                if (/^\s*```/.test(line)) { out.push(`<table width="100%" cellpadding="8" style="background-color:${bg};"><tr><td><pre style="font-family:monospace;">${esc(code.join("\n"))}</pre></td></tr></table>`); code = null; }
                else code.push(line);
                continue;
            }
            if (/^\s*```/.test(line)) { flushPara(); flushList(); code = []; continue; }
            const li = /^\s*(?:[-*•]|(\d+)[.)])\s+(.*)$/.exec(line);
            if (li) {
                flushPara();
                const tag = li[1] ? "ol" : "ul";
                if (!list || list.tag !== tag) { flushList(); list = { tag: tag, items: [] }; }
                list.items.push(li[2]);
                continue;
            }
            const h = /^#{1,6}\s+(.*)$/.exec(line);
            if (h) { flushPara(); flushList(); out.push("<p><b>" + inline(h[1]) + "</b></p>"); continue; }
            if (!line.trim()) { flushPara(); flushList(); continue; }
            flushList();
            para.push(line);
        }
        if (code !== null) out.push(`<pre style="font-family:monospace;">${esc(code.join("\n"))}</pre>`); // still streaming
        flushPara(); flushList();
        return out.join("");
    }

    // ── maths ──
    readonly property bool mathy: /^=/.test(query.trim()) || /^[\d(.\-+√]/.test(query.trim())
    readonly property string expr: query.trim().replace(/^=\s*/, "")
    QtObject {
        id: calc
        property string result: ""
    }
    onExprChanged: { calc.result = ""; if (mathy && expr) calcTimer.restart(); }
    Timer { id: calcTimer; interval: 140; onTriggered: { qalc.running = false; qalc.command = ["qalc", "-t", "--", root.expr]; qalc.running = true; } }
    Process {
        id: qalc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                calc.result = t && !/^error/i.test(t) && t !== root.expr ? t : "";
            }
        }
    }

    // ── actions ──
    readonly property list<var> actions: [
        ...Session.actions,
        { id: "dnd", title: Notifs.dnd ? "Turn off Do Not Disturb" : "Do Not Disturb", sub: "Hold notification popups", glyph: Notifs.dnd ? "notifications_active" : "notifications_off" },
        { id: "clear", title: "Clear notifications", sub: Notifs.entries.length + " in history", glyph: "clear_all" },
        { id: "island", title: "Hide / show the island", sub: "Same as Super+I", glyph: "visibility" },
        { id: "stopwatch", title: "Start a stopwatch", sub: "Rides on the island", glyph: "timer" }
    ]
    function runAction(a: var): void {
        switch (a.id) {
        case "dnd": Notifs.dnd = !Notifs.dnd; break;
        case "clear": Notifs.clear(); break;
        case "island": islandToggle.running = true; break;
        case "stopwatch": Countdown.startStopwatch(); break;
        case "timer": Countdown.startTimer(a.ms); break;
        default: Quickshell.execDetached(a.cmd);
        }
    }
    Process { id: islandToggle; command: ["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "island", "toggle"] }

    // ── results ──
    readonly property list<var> results: {
        const q = query.trim();
        if (q.startsWith("?")) return askText ? [{ kind: "ask", q: askText }] : [];
        if (q.startsWith(">")) {
            const a = q.slice(1).trim().toLowerCase();
            const out = [];
            const t = /^timer\s+(.+)$/.exec(a);
            if (t && Countdown.parse(t[1]) > 0)
                out.push({ kind: "action", a: { id: "timer", ms: Countdown.parse(t[1]), title: "Start a " + t[1].trim() + " timer", sub: "Rides on the island", glyph: "timer" } });
            const scored = actions.map((x, i) => ({ x: x, i: i, s: a ? Apps.score(a, x.title.toLowerCase()) : 1 })).filter(x => x.s > 0);
            scored.sort((p, q2) => q2.s - p.s || p.i - q2.i); // keep the list order on ties
            return out.concat(scored.map(x => ({ kind: "action", a: x.x })));
        }
        const out = [];
        if (mathy && calc.result) out.push({ kind: "calc" });
        return out.concat(Apps.search(q).slice(0, 40).map(e => ({ kind: "app", e: e })));
    }
    onResultsChanged: { current = 0; confirming = ""; }

    function move(d: int): void {
        if (!results.length) return;
        current = (current + d + results.length) % results.length;
        confirming = "";
        list.positionViewAtIndex(current, ListView.Contain);
    }
    function activate(i: int): void {
        const r = results[i];
        if (!r) return;
        if (r.kind === "ask") Ask.ask(r.q);
        else if (r.kind === "app") { Apps.launch(r.e); close(); }
        else if (r.kind === "calc") { Quickshell.execDetached(["wl-copy", calc.result]); close(); }
        else {
            if (r.a.confirm && confirming !== r.a.id) { current = i; confirming = r.a.id; return; }
            close();
            runAction(r.a);
        }
    }

    // ── search box ──
    Item {
        id: bar
        x: 18
        y: 10
        width: parent.width - 36
        height: 40
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.alpha(Theme.text, 0.06)
        }
        Icon {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            name: root.asking ? "auto_awesome" : root.query.trim().startsWith(">") ? "bolt" : root.mathy ? "calculate" : "search"
            color: root.asking ? Theme.tone("action") : Theme.subtext
            size: 20
        }
        TextInput {
            id: field
            x: 44
            width: parent.width - 44 - 16
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: 15
            color: Theme.text
            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
            clip: true
            onTextChanged: root.query = text
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                if (root.answering) { // the answer is showing: arrows scroll it, Enter asks again
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { answer.scroll(e.key === Qt.Key_Down ? 60 : -60); e.accepted = true; return; }
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (root.askText && (root.askText !== Ask.question || Ask.st === "error")) Ask.ask(root.askText);
                        e.accepted = true;
                        return;
                    }
                }
                if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N)) { root.move(1); e.accepted = true; }
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P)) { root.move(-1); e.accepted = true; }
                else if (e.key === Qt.Key_PageDown) { root.move(Math.min(root.maxRows, root.results.length - 1 - root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_PageUp) { root.move(-Math.min(root.maxRows, root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.activate(root.current); e.accepted = true; }
                else if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !field.text && !field.preeditText
                font.pixelSize: 15
                text: "Search apps, = maths, > actions, ? ask Claude"
            }
        }
    }

    // ── results ──
    ListView {
        id: list
        visible: !root.answering
        x: 10
        y: 58
        width: parent.width - 20
        height: root.shown * root.rowH
        clip: true
        model: root.results
        currentIndex: root.current
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false

        Rectangle { // the selection springs between rows
            z: -1
            width: list.width
            height: root.rowH
            radius: 14
            y: root.current * root.rowH - list.contentY
            visible: root.results.length > 0
            color: root.confirming ? Qt.alpha(Theme.tone("error"), 0.16) : Qt.alpha(Theme.text, 0.08)
            Behavior on y { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool sel: index === root.current
            readonly property var a: modelData.a ?? null
            readonly property bool confirm: !!a && root.confirming === a.id
            width: list.width
            height: root.rowH

            Item {
                id: ico
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                readonly property string path: row.modelData.kind === "app" ? Quickshell.iconPath(row.modelData.e.icon, true) : ""
                Image {
                    id: appImg
                    anchors.fill: parent
                    sourceSize: Qt.size(64, 64)
                    source: ico.path
                    visible: status === Image.Ready
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    visible: appImg.status !== Image.Ready
                    color: row.confirm ? Qt.alpha(Theme.tone("error"), 0.2) : Qt.alpha(Theme.tone("action"), 0.14)
                    Icon {
                        anchors.centerIn: parent
                        size: 17
                        fill: 1
                        color: row.confirm ? Theme.tone("error") : Theme.tone("action")
                        name: row.modelData.kind === "calc" ? "calculate" : row.modelData.kind === "action" ? row.a.glyph
                            : row.modelData.kind === "ask" ? "auto_awesome" : "apps"
                    }
                }
            }
            Column {
                x: 52
                width: parent.width - 52 - 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: row.sel ? Font.DemiBold : Font.Medium
                    color: row.confirm ? Theme.tone("error") : Theme.text
                    text: row.modelData.kind === "app" ? row.modelData.e.name
                        : row.modelData.kind === "calc" ? calc.result
                        : row.modelData.kind === "ask" ? row.modelData.q
                        : row.confirm ? "Press Enter again to " + row.a.title.toLowerCase() : row.a.title
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    visible: text !== ""
                    text: row.modelData.kind === "app" ? (row.modelData.e.comment || row.modelData.e.genericName || "")
                        : row.modelData.kind === "calc" ? "= " + root.expr + "  ·  Enter copies"
                        : row.modelData.kind === "ask" ? "Ask Claude  ·  Enter"
                        : row.a.sub
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: if (root.current !== row.index) { root.current = row.index; root.confirming = ""; }
                onClicked: root.activate(row.index)
            }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 66
        visible: root.results.length === 0 && !root.answering
        Label { text: root.asking ? "Type a question for Claude" : root.mathy ? "Working it out…" : "Nothing found" }
    }

    // ── Claude's answer ──
    Item {
        id: answer
        x: 18
        y: 58
        width: parent.width - 36
        height: Math.min(380, Math.max(44, body.implicitHeight + 8))
        visible: root.answering
        clip: true
        function scroll(dy: real): void {
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
        }

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            // follow the stream while it's coming in
            onContentHeightChanged: if (Ask.busy) contentY = Math.max(0, contentHeight - height)

            Column {
                id: body
                x: 4
                width: parent.width - 8
                spacing: 10

                Row { // thinking: three breathing dots
                    visible: Ask.busy && !Ask.answer
                    spacing: 5
                    height: 24
                    Repeater {
                        model: 3
                        Rectangle {
                            id: dotItem
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: Theme.tone("action")
                            SequentialAnimation on opacity {
                                running: Ask.busy && !Ask.answer
                                loops: Animation.Infinite
                                PauseAnimation { duration: dotItem.index * 150 }
                                NumberAnimation { to: 0.25; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 400; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; text: "Claude is thinking…" }
                }

                TextEdit {
                    width: parent.width
                    visible: !!Ask.answer
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                    text: root.md(Ask.answer)
                }

                Label {
                    width: parent.width
                    visible: Ask.st === "error"
                    wrapMode: Text.Wrap
                    color: Theme.tone("error")
                    text: Ask.error
                }

                Row {
                    visible: Ask.st === "done"
                    spacing: 8
                    Rectangle {
                        id: copyBtn
                        width: copyRow.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: Qt.alpha(Theme.text, copyMa.containsMouse ? 0.12 : 0.07)
                        property bool copied: false
                        Row {
                            id: copyRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: copyBtn.copied ? "check" : "content_copy"; size: 15; color: Theme.text }
                            Label { anchors.verticalCenter: parent.verticalCenter; color: Theme.text; text: copyBtn.copied ? "Copied" : "Copy" }
                        }
                        MouseArea {
                            id: copyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Quickshell.execDetached(["wl-copy", Ask.answer]); copyBtn.copied = true; }
                        }
                        Connections { target: Ask; function onAnswerChanged() { copyBtn.copied = false; } }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 11
                        text: "Edit the question and press Enter for a follow-up"
                    }
                }
            }
        }
    }
}
