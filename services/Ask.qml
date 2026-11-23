pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Io

// Ask Claude a quick question from the launcher, through the Claude Code CLI
// (your logged-in account): print mode, no tools, --restricted (so your
// settings' hooks don't run and no session is saved), streamed. Follow-ups
// carry the earlier exchange along. Model: $BEAD_ASK_MODEL (default sonnet).
Singleton {
    id: root

    property string st: ""          // "" | asking | done | error
    property string question: ""
    property string answer: ""
    property string error: ""
    property list<var> history: []  // [{ q, a }] of this launcher session
    readonly property bool active: st !== ""
    readonly property bool busy: st === "asking"

    readonly property string model: Settings.askModel || "sonnet"
    readonly property string system: "You are answering a quick question typed into a desktop launcher "
        + "(Hyprland on CachyOS / Arch Linux, fish shell). Answer directly and briefly: usually one to four "
        + "sentences, or a short list or code block when that is clearer. No preamble, no sign-off."

    function ask(q: string): void {
        q = q.trim();
        if (!q) return;
        let prompt = q;
        if (history.length) {
            prompt = "Earlier in this conversation:\n\n"
                + history.map(h => "Q: " + h.q + "\nA: " + h.a).join("\n\n")
                + "\n\nNow: " + q;
        }
        question = q;
        answer = "";
        error = "";
        st = "asking";
        const cmd = ["sh", "-c",
            'd="${XDG_CACHE_HOME:-$HOME/.cache}/bead/ask"; mkdir -p "$d" && cd "$d" && exec claude -p --restricted --tools "" '
            + '--no-session-persistence --output-format stream-json --include-partial-messages --verbose '
            + '--model "$1" --append-system-prompt "$2" -- "$3"',
            "ask", model, system, prompt];
        // a previous question still streaming: stop it, start this one when it exits
        if (proc.running) { pending = cmd; proc.signal(15); }
        else { proc.command = cmd; proc.running = true; }
    }
    property var pending: null
    function cancel(): void { pending = null; if (proc.running) proc.signal(15); }
    function clear(): void { cancel(); st = ""; question = ""; answer = ""; error = ""; history = []; }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                if (root.st !== "asking" || root.pending) return; // a cancelled run's tail
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "stream_event" && m.event?.delta?.type === "text_delta")
                    root.answer += m.event.delta.text;
                else if (m.type === "result" && m.is_error)
                    root.error = m.result || "Claude couldn't answer.";
                else if (m.type === "assistant" && !root.answer)
                    root.answer = (m.message?.content ?? []).filter(c => c.type === "text").map(c => c.text).join("");
            }
        }
        stderr: StdioCollector { id: errs }
        onExited: code => {
            if (root.pending) { proc.command = root.pending; root.pending = null; proc.running = true; return; }
            if (root.st !== "asking") return;
            if (root.answer && !root.error) {
                root.st = "done";
                root.history = [...root.history, { q: root.question, a: root.answer }].slice(-6);
            } else {
                root.error = root.error || errs.text.trim().split("\n").pop() || "Claude couldn't answer (exit " + code + ").";
                root.st = "error";
            }
        }
    }
}
