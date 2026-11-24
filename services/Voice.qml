pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Voice commands: hold Super+Space, say what you want, release. bead-dictate
// transcribes it (whisper.cpp); a small local model (Qwen2.5 1.5B in
// llama-server, on the GPU) picks ONE action from a fixed list as JSON, and
// the island runs it (see Island.runVoice). Nothing outside the list can run.
//
// Your own actions (and automations: chains of steps) live in
// ~/.config/bead/voice.json, reloaded on save:
//   { "actions": [ {
//       "name": "game_mode",                       a-z, 0-9, _
//       "when": "start gaming or game mode",       tells the model when to pick it
//       "phrases": ["game mode"],                  optional: exact words that skip the model
//       "text": false,                             true: what you said goes to $BEAD_TEXT
//       "say": "Game mode on",                     optional: shown on the island after
//       "steps": [
//         { "do": "open_app", "app": "steam", "workspace": 5, "alone": true },
//         { "do": "dnd" },                         any built-in action, with its fields
//         { "wait": 500 },                         milliseconds
//         { "run": "notify-send 'gl hf'" }         a shell command (sh -c)
//       ] } ] }
// The model only ever picks a name; the commands come from your file. A text
// action's words reach its commands as $BEAD_TEXT (an environment variable,
// never pasted into the command: write "$BEAD_TEXT", quoted).
//
// The model server starts when you press the key (it loads while you talk)
// and stops after a few idle minutes, so nothing sits in VRAM all day.
Singleton {
    id: root

    // "" | listening | transcribing | thinking | done (the blob pops, then the result)
    property string state: ""
    property string partial: ""  // what you've said so far, live
    property string heard: ""    // the final transcript
    readonly property bool active: state !== "" || question !== null
    property real level: 0
    signal decided(var action, string heard)
    property bool dry: false
    property string lastDecision: ""

    // ── context: what's on your clipboard when you speak (text, up to 4k).
    // It stays here: the local model only sees it when you mention it ──
    property string clip: ""
    function mentionsClip(t: string): bool { return /\b(clipboard|copied|i copied|just copied)\b/i.test(t); }
    function mentionsScreen(t: string): bool { return /\b(on (the |my )?screen|on screen|you can see|in (this|the) window|that button|the button)\b/i.test(t); }
    // a host or IP in some text: user@host, an IPv4 address, or a dotted name
    function hostIn(t: string): string {
        const m = String(t).match(/(?:^|[\s"'(<\[])((?:[A-Za-z0-9._-]+@)?(?:(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9-]+)+))(?=$|[\s"')>\]:/,])/);
        return m ? m[1] : "";
    }
    Process {
        id: clipRead
        command: ["sh", "-c", "wl-paste -n -t text 2>/dev/null | head -c 4096"]
        stdout: StdioCollector { onStreamFinished: root.clip = text }
    }
    signal failed(string why)

    readonly property string model: Quickshell.env("HOME") + "/.local/share/bead-models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    readonly property int port: 8737
    property bool serverReady: false
    property string pending: "" // heard before the server was ready

    readonly property var builtins: ({
        timer: "start a countdown timer; hours, minutes and seconds as said (don't add them up)",
        stopwatch: "start a stopwatch",
        stop_timers: "stop or cancel all timers",
        play_pause: "play or pause the music",
        next_track: "skip to the next song",
        previous_track: "go back to the previous song",
        volume_set: "set the volume; level = percent 0-100",
        volume_up: "turn the volume up",
        volume_down: "turn the volume down",
        mute: "mute or unmute the sound",
        mic_mute: "mute or unmute the microphone",
        again: "do the last command again, repeat it",
        undo: "undo or take back the last command",
        window: "do something to an open window: op = focus (switch to it), close, move (to workspace = the number), fullscreen, float, or side_by_side (with with_app); app = which window by its app name, or \"this\" for the current one",
        look: "a question about what's on the screen right now: this window, this error, this page, what am I looking at; text = the question",
        click: "click, press or tap something visible on the screen (a button, link, tab, icon); text = what to click, as said",
        ssh: "open an SSH session (a remote shell) in a new terminal; workspace = the number, if they say where",
        open_app: "open or launch an application; app = its name only; workspace = the number, if they say which workspace (or window, desktop) to open it on; alone = true if they ask to close the other windows there",
        workspace: "go or switch to a workspace; workspace = its number",
        overview: "show all workspaces / windows",
        wallpaper: "change to a random wallpaper",
        dnd: "turn do not disturb on or off",
        screenshot_area: "take a screenshot of a region",
        screenshot_screen: "take a screenshot of the whole screen",
        ask: "any question (who, what, how, why, when…) or request for information; text = the question",
        none: "only greetings, chit-chat or unclear speech"
    })
    // built-ins, then yours
    readonly property var actions: {
        const out = Object.assign({}, builtins);
        delete out.none; // keep "none" last: the model's fallback
        for (const c of custom) out[c.name] = c.when + (c.text ? "; text = what they asked for" : "");
        out.none = builtins.none;
        return out;
    }

    // ── your actions (~/.config/bead/voice.json) ──
    readonly property string customPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/voice.json"
    property var custom: []
    property string customError: ""   // why the file (or an action in it) was skipped
    function parseCustom(txt: string): void {
        let d;
        try { d = JSON.parse(txt); } catch (e) { custom = []; customError = "voice.json isn't valid JSON: " + e.message; return; }
        const out = [], bad = [];
        for (const c of (d.actions ?? [])) {
            const name = String(c.name ?? "");
            const steps = Array.isArray(c.steps) ? c.steps : [];
            const why = !/^[a-z][a-z0-9_]{0,39}$/.test(name) ? "name must be a-z, 0-9 or _"
                : builtins[name] !== undefined ? "a built-in has that name"
                : out.some(x => x.name === name) ? "used twice"
                : !c.when ? "needs \"when\""
                : !steps.length ? "needs steps"
                : steps.some(st => !(st.run || st.wait > 0 || (st.do && builtins[st.do] !== undefined && st.do !== "none")))
                    ? "a step needs \"run\", \"wait\" or a built-in \"do\"" : "";
            if (why) { bad.push((name || "?") + ": " + why); continue; }
            out.push({ name: name, when: String(c.when), text: c.text === true, say: String(c.say ?? ""),
                phrases: (c.phrases ?? []).map(norm).filter(x => x), steps: steps });
        }
        custom = out;
        customError = bad.join("; ");
        if (bad.length) console.warn("voice: skipped", customError);
    }
    // words only, lower case, single spaces
    function norm(t: string): string { return String(t).toLowerCase().replace(/[^a-z0-9' ]+/g, " ").replace(/\s+/g, " ").trim(); }
    // one of your phrases, said: run it straight away, no model needed. A text
    // action's phrase starts the sentence and the rest is its text
    function byPhrase(heard: string): var {
        const h = norm(heard);
        for (const c of custom) for (const p of c.phrases) {
            if (c.text && (h === p || h.startsWith(p + " "))) {
                // the rest as you said it (case, punctuation and all), past the phrase's words
                const lead = new RegExp("^\\W*" + p.split(" ").map(w => w.replace(/'/g, "\\W?")).join("\\W+") + "\\W*", "i");
                return { action: c.name, text: heard.replace(lead, "").trim() };
            }
            if (!c.text && (" " + h + " ").includes(" " + p + " ")) return { action: c.name };
        }
        return null;
    }
    // a starting point for the file, if you don't have one yet
    function ensureCustom(): void {
        if (customFile.loaded) return;
        customFile.setText(JSON.stringify({ actions: [
            { name: "game_mode", when: "start gaming, or game mode", phrases: ["game mode"], say: "Game mode on",
              steps: [{ do: "open_app", app: "steam", workspace: 5, alone: true }, { do: "dnd" }] },
            { name: "search_web", when: "search the web for something", text: true, phrases: ["search for", "look up"],
              steps: [{ run: "xdg-open \"https://duckduckgo.com/?q=$BEAD_TEXT\"" }] },
            {"name": "spotify", "when": "play or find a song, artist, album or playlist on Spotify; text = just what to play", "text": true, "phrases": ["on spotify play", "spotify play"], "say": "Spotify", "steps": [{"run": "q=$(printf %s \"$BEAD_TEXT\" | sed -E 's/^(play|put on) +//I; s/ +(on|in|from) +spotify$//I; s/%/%25/g; s/ /%20/g; s/#/%23/g; s/\\?/%3F/g'); xdg-open \"spotify:search:$q\""}]}
        ] }, null, 2) + "\n");
    }
    FileView {
        id: customFile
        path: root.customPath
        watchChanges: true
        printErrors: false
        property bool loaded: false
        onFileChanged: reload()
        onLoaded: { loaded = true; root.parseCustom(text()); }
        onLoadFailed: { loaded = false; root.custom = []; root.customError = ""; }
    }

    readonly property var schema: ({
        type: "object",
        properties: {
            action: { type: "string", enum: Object.keys(actions) },
            op: { type: "string", enum: ["focus", "close", "move", "fullscreen", "float", "side_by_side"] },
            hours: { type: "integer", minimum: 0, maximum: 24 },
            minutes: { type: "integer", minimum: 0, maximum: 600 },
            seconds: { type: "integer", minimum: 0, maximum: 3600 },
            level: { type: "integer", minimum: 0, maximum: 100 },
            app: { type: "string", maxLength: 40 },
            workspace: { type: "integer", minimum: 1, maximum: 20 },
            alone: { type: "boolean" },
            with_app: { type: "string", maxLength: 40 },
            text: { type: "string", maxLength: 300 }
        },
        required: ["action"]
    })
    readonly property string system: "You turn a spoken request into exactly one desktop action as JSON. "
        + "Actions:\n" + Object.keys(actions).map(k => "- " + k + ": " + actions[k]).join("\n")
        + "\nOnly fill the fields the action needs. Examples:\n"
        + "\"set a timer for ten minutes\" -> {\"action\":\"timer\",\"minutes\":10}\n"
        + "\"timer for two hours and five seconds\" -> {\"action\":\"timer\",\"hours\":2,\"seconds\":5}\n"
        + "\"volume to thirty\" -> {\"action\":\"volume_set\",\"level\":30}\n"
        + "\"open firefox\" -> {\"action\":\"open_app\",\"app\":\"firefox\"}\n"
        + "\"open spotify on workspace five and close the other windows there\" -> {\"action\":\"open_app\",\"app\":\"spotify\",\"workspace\":5,\"alone\":true}\n"
        + "\"click the update button\" -> {\"action\":\"click\",\"text\":\"the update button\"}\n"
        + "\"move discord to workspace two\" -> {\"action\":\"window\",\"op\":\"move\",\"app\":\"discord\",\"workspace\":2}\n"
        + "\"close spotify\" -> {\"action\":\"window\",\"op\":\"close\",\"app\":\"spotify\"}\n"
        + "\"switch to firefox\" -> {\"action\":\"window\",\"op\":\"focus\",\"app\":\"firefox\"}\n"
        + "\"make this fullscreen\" -> {\"action\":\"window\",\"op\":\"fullscreen\",\"app\":\"this\"}\n"
        + "\"put firefox and kitty side by side\" -> {\"action\":\"window\",\"op\":\"side_by_side\",\"app\":\"firefox\",\"with_app\":\"kitty\"}\n"
        + "\"what does this error mean\" -> {\"action\":\"look\",\"text\":\"what does this error mean\"}\n"
        + "\"summarize what's on my screen\" -> {\"action\":\"look\",\"text\":\"summarize what's on my screen\"}\n"
        + "\"undo that\" -> {\"action\":\"undo\"}\n"
        + "\"do that again\" -> {\"action\":\"again\"}\n"
        + "\"ssh\" -> {\"action\":\"ssh\"}\n"
        + "\"ssh into the pi on workspace two\" -> {\"action\":\"ssh\",\"workspace\":2}\n"
        + "\"go to workspace three\" -> {\"action\":\"workspace\",\"workspace\":3}\n"
        + "\"skip this song\" -> {\"action\":\"next_track\"}\n"
        + "\"who wrote hamlet\" -> {\"action\":\"ask\",\"text\":\"who wrote hamlet\"}\n"
        + "\"hi there\" -> {\"action\":\"none\"}"


    function start(): void {
        if (helper.running) return;
        // a muted mic records silence, which then does nothing: say so instead
        if (Audio.micMuted) { root.failed("Your mic is muted"); return; }
        if (question) { question = null; answerCb = null; } // a new command drops an open question
        handsFree = false;
        clip = "";
        clipRead.running = true;
        ensureServer();
        level = 0;
        pending = "";
        partial = "";
        heard = "";
        state = "listening";
        helper.running = true;
    }
    function stop(): void { if (helper.running && state === "listening") helper.write("stop\n"); }
    function cancel(): void {
        if (helper.running) helper.write("cancel\n");
        else if (question) { question = null; answerCb = null; }
    }

    // ── a follow-up question: the island shows the options and listens
    // hands-free (no key: it stops when you stop talking); say one, or tap it ──
    property var question: null   // { prompt, options: [string] }
    property var answerCb: null
    property bool handsFree: false
    function ask(prompt: string, options: var, then: var): void {
        question = { prompt: prompt, options: options };
        answerCb = then;
        listenAgain();
    }
    function listenAgain(): void {
        if (helper.running || !question) return;
        if (Audio.micMuted) return; // the options can still be tapped
        ensureWhisper();
        handsFree = true;
        level = 0;
        partial = "";
        heard = "";
        state = "listening";
        helper.running = true;
    }
    function answer(choice: string): void {
        const cb = answerCb;
        question = null;
        answerCb = null;
        if (helper.running) helper.write("cancel\n");
        state = "";
        if (cb) cb(choice);
    }
    // which option was said: its name (allowing for mishearing), or "the
    // second one", "number two"…
    function matchOption(said: string, options: var, ordinals = true): string {
        // spoken letters ("dee lax" is dlax, "el see" is lc): only when every
        // word in the run is a letter, so "I'll see" stays words
        const letters = { ay: "a", bee: "b", see: "c", sea: "c", dee: "d", ee: "e", ef: "f", gee: "g", aitch: "h",
            eye: "i", jay: "j", kay: "k", el: "l", elle: "l", em: "m", en: "n", oh: "o", pee: "p", cue: "q", queue: "q",
            ar: "r", es: "s", tee: "t", tea: "t", vee: "v", ex: "x", zed: "z", zee: "z" };
        const words = norm(said).replace(/'/g, "").split(" ").filter(w => w);
        const name = o => norm(o).replace(/[ ']/g, "");
        // "the second one", "number three": an ordinal ("one" only when it's alone)
        const ords = [["first", "1"], ["second", "two", "2"], ["third", "three", "3"], ["fourth", "four", "4"], ["fifth", "five", "5"], ["sixth", "six", "6"]];
        let k = ords.findIndex(set => set.some(w => words.includes(w)));
        if (k < 0 && words.includes("one") && words.every(w => ["the", "one", "number"].includes(w))) k = 0;
        // runs of 1-3 whole words: as said, as letters, and as initials + last word ("home lab")
        const exact = [], loose = [];
        for (let i = 0; i < words.length; i++) for (let n = 1; n <= 3 && i + n <= words.length; n++) {
            const run = words.slice(i, i + n);
            exact.push(run.join(""));
            loose.push(run.join(""));
            if (run.every(w => letters[w] || w.length === 1)) exact.push(run.map(w => letters[w] ?? w).join(""));
            if (n > 1) exact.push(run.slice(0, -1).map(w => w[0]).join("") + run[n - 1], run.map(w => w[0]).join(""));
        }
        const hit = options.find(o => exact.includes(name(o)));
        if (hit) return hit;
        if (ordinals && k >= 0 && k < options.length) return options[k];
        // a near miss of a whole run ("h-lab", "dlacks"): close, and long enough to be sure
        let best = "", score = 0;
        for (const o of options) for (const g of loose) {
            const v = Apps.similar(g, name(o));
            if (v >= 0.8 && v > score) { score = v; best = o; }
        }
        return best;
    }



    // ── your SSH hosts (~/.ssh/config: the Host names, not wildcards) ──
    property var sshHosts: []
    FileView {
        path: Quickshell.env("HOME") + "/.ssh/config"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const m = line.match(/^\s*Host\s+(.+?)\s*$/i);
                if (m) for (const h of m[1].split(/\s+/)) if (!/[*?!]/.test(h) && !out.includes(h)) out.push(h);
            }
            root.sshHosts = out;
        }
        onLoadFailed: root.sshHosts = []
    }

    // ── the model server ──
    readonly property bool warm: server.running || whisper.running // models in memory
    function unload(): void { if (!active) { server.running = false; whisper.running = false; } }
    function ensureServer(): void {
        idle.restart();
        if (!server.running) { serverReady = false; server.running = true; }
        if (!whisper.running) whisper.running = true;
    }
    // just the speech model (dictation types live through it)
    function ensureWhisper(): void {
        idle.restart();
        if (!whisper.running) whisper.running = true;
    }
    // whisper kept warm while you use voice: live partials take ~50 ms each
    readonly property int whisperPort: 8739
    Process {
        id: whisper
        command: ["whisper-server", "-m", Quickshell.env("HOME") + "/.local/share/bead-models/ggml-base.en.bin",
            "--host", "127.0.0.1", "--port", String(root.whisperPort), "-l", "en"]
    }
    Process {
        id: server
        command: ["llama-server", "-m", root.model, "-ngl", "99", "-c", "2048", "--host", "127.0.0.1",
            "--port", String(root.port), "--no-webui", "-np", "1"]
        onExited: (code, status) => {
            root.serverReady = false;
            if (root.state === "thinking") { root.state = ""; root.failed("The voice model stopped (is llama-cpp installed?)"); }
        }
    }
    // ready when /health answers 200 (log lines vary between versions)
    Timer {
        interval: 150
        repeat: true
        running: server.running && !root.serverReady
        onTriggered: {
            const x = new XMLHttpRequest();
            x.open("GET", "http://127.0.0.1:" + root.port + "/health");
            x.onreadystatechange = () => {
                if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200 || root.serverReady) return;
                root.serverReady = true;
                if (root.pending) { const t = root.pending; root.pending = ""; root.decide(t); }
            };
            x.send();
        }
    }
    Timer { id: idle; interval: 4 * 60 * 1000; onTriggered: if (!root.active) { server.running = false; whisper.running = false; } }

    // ── listening, then deciding ──
    Process {
        id: helper
        command: [Quickshell.env("HOME") + "/.local/bin/bead-dictate", "--no-type", "--partials",
            "--server", "http://127.0.0.1:" + root.whisperPort].concat(root.handsFree ? ["--until-silence"] : [])
        stdinEnabled: true
        property string heard: ""
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.level !== undefined) root.level = m.level;
                else if (m.partial !== undefined) root.partial = m.partial;
                else if (m.state) { root.state = m.state; root.level = 0; }
                else if (m.error) { console.warn("voice: helper error:", m.error); root.failed(m.error); }
                else if (m.text !== undefined) { console.info("voice: heard:", JSON.stringify(m.text), "peak", m.peak, "loud", m.loud); helper.heard = m.text; }
            }
        }
        onExited: (code, status) => {
            console.info("voice: helper exited", code, "heard", JSON.stringify(heard), "server ready", root.serverReady);
            const t = heard;
            heard = "";
            root.level = 0;
            if (root.question) {
                // an answer: no model needed. Not caught: the options stay up to tap
                root.state = "";
                const hit = t ? root.matchOption(t, root.question.options) : "";
                if (hit) root.answer(hit);
                else root.partial = t ? "\u201c" + t + "\u201d? Say one, or tap it" : "";
                return;
            }
            if (!t) { root.state = ""; return; }
            root.heard = t;
            root.partial = t;
            root.state = "thinking";
            if (root.serverReady) root.decide(t); else root.pending = t;
        }
    }

    function decide(heard: string): void {
        idle.restart();
        // "undo" and "again" need no model
        const n = norm(heard);
        const quick = /^(undo|undo (that|it|this)|take (that|it) back|revert (that|it))$/.test(n) ? { action: "undo" }
            : /^(again|do (that|it) again|repeat( that| it)?|one more time|same again)$/.test(n) ? { action: "again" } : null;
        const hit = quick ?? byPhrase(heard);
        if (hit) {
            console.info("voice: phrase", JSON.stringify(hit), "for", JSON.stringify(heard));
            root.state = "done";
            handover.action = hit;
            handover.restart();
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:" + port + "/v1/chat/completions");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 20000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let a = null;
            try { a = JSON.parse(JSON.parse(xhr.responseText).choices[0].message.content); } catch (e) {}
            console.info("voice: http", xhr.status, "decided", JSON.stringify(a), "for", JSON.stringify(heard));
            if (!a || !a.action) { root.state = ""; root.failed("Couldn't work that out: “" + heard + "”"); return; }
            // the blob pops, then the island becomes the result
            root.state = "done";
            handover.action = a;
            handover.restart();
        };
        xhr.send(JSON.stringify({
            messages: [{ role: "system", content: system }, { role: "user", content: heard }],
            temperature: 0,
            max_tokens: 120,
            response_format: { type: "json_schema", json_schema: { name: "action", schema: schema } }
        }));
    }

    Timer {
        id: handover
        interval: 280
        property var action: null
        onTriggered: {
            root.state = "";
            if (root.dry) { root.dry = false; root.lastDecision = JSON.stringify(action); return; }
            root.decided(action, root.heard);
        }
    }

    IpcHandler {
        target: "voice"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.cancel(); }
        function status(): string { return (root.state || "idle") + (server.running ? (root.serverReady ? " · model ready" : " · model loading") : ""); }
        // one of your actions, by name (for keybinds and scripts: bead voice run NAME [TEXT])
        function run(name: string, text: string): string {
            if (!root.custom.some(c => c.name === name)) return "no action called " + name + (root.customError ? " (" + root.customError + ")" : "");
            root.decided({ action: name, text: text }, text);
            return "ok";
        }
        function list(): string { return root.custom.map(c => c.name + (c.phrases.length ? " (\"" + c.phrases.join("\", \"") + "\")" : "")).join("\n") + (root.customError ? "\nskipped: " + root.customError : ""); }
        // test how an answer would match, without acting: match "the h lab one" "dlax,lc,hlab"
        function match(said: string, options: string): string { return root.matchOption(said, options.split(",")) || "(none)"; }
        // test a follow-up answer without speaking
        function answerText(text: string): string {
            if (!root.question) return "no question open";
            const hit = root.matchOption(text, root.question.options);
            if (hit) root.answer(hit);
            return hit || "(none)";
        }
        // test the decision without speaking
        // what would it do? decides, shows it, runs nothing: decideDry "…" then lastDecision
        function decideDry(text: string): void { root.dry = true; root.lastDecision = ""; decideText(text); }
        function lastDecision(): string { return root.lastDecision; }
        function decideText(text: string): void { root.ensureServer(); root.heard = text; root.partial = text; root.state = "thinking"; if (root.serverReady) root.decide(text); else root.pending = text; }
    }
}
