pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Voice commands: hold Super+Space, say what you want, release. bead-dictate
// transcribes it (whisper.cpp); a small local model (Qwen2.5 1.5B in
// llama-server, on the GPU) picks ONE action from a fixed list as JSON, and
// the island runs it (see Island.runVoice). Nothing outside the list can run.
//
// The model server starts when you press the key (it loads while you talk)
// and stops after a few idle minutes, so nothing sits in VRAM all day.
Singleton {
    id: root

    // "" | listening | transcribing | thinking | done (the blob pops, then the result)
    property string state: ""
    property string partial: ""  // what you've said so far, live
    property string heard: ""    // the final transcript
    readonly property bool active: state !== ""
    property real level: 0
    signal decided(var action, string heard)
    signal failed(string why)

    readonly property string model: Quickshell.env("HOME") + "/.local/share/bead-models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
    readonly property int port: 8737
    property bool serverReady: false
    property string pending: "" // heard before the server was ready

    readonly property var actions: ({
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
    readonly property var schema: ({
        type: "object",
        properties: {
            action: { type: "string", enum: Object.keys(actions) },
            hours: { type: "integer", minimum: 0, maximum: 24 },
            minutes: { type: "integer", minimum: 0, maximum: 600 },
            seconds: { type: "integer", minimum: 0, maximum: 3600 },
            level: { type: "integer", minimum: 0, maximum: 100 },
            app: { type: "string", maxLength: 40 },
            workspace: { type: "integer", minimum: 1, maximum: 20 },
            alone: { type: "boolean" },
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
        + "\"go to workspace three\" -> {\"action\":\"workspace\",\"workspace\":3}\n"
        + "\"skip this song\" -> {\"action\":\"next_track\"}\n"
        + "\"who wrote hamlet\" -> {\"action\":\"ask\",\"text\":\"who wrote hamlet\"}\n"
        + "\"hi there\" -> {\"action\":\"none\"}"

    function start(): void {
        if (helper.running) return;
        // a muted mic records silence, which then does nothing: say so instead
        if (Audio.micMuted) { root.failed("Your mic is muted"); return; }
        ensureServer();
        level = 0;
        pending = "";
        partial = "";
        heard = "";
        state = "listening";
        helper.running = true;
    }
    function stop(): void { if (helper.running && state === "listening") helper.write("stop\n"); }
    function cancel(): void { if (helper.running) helper.write("cancel\n"); }

    // ── the model server ──
    readonly property bool warm: server.running || whisper.running // models in memory
    function unload(): void { if (!active) { server.running = false; whisper.running = false; } }
    function ensureServer(): void {
        idle.restart();
        if (!server.running) { serverReady = false; server.running = true; }
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
            "--server", "http://127.0.0.1:" + root.whisperPort]
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
            if (!t) { root.state = ""; return; }
            root.heard = t;
            root.partial = t;
            root.state = "thinking";
            if (root.serverReady) root.decide(t); else root.pending = t;
        }
    }

    function decide(heard: string): void {
        idle.restart();
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
        onTriggered: { root.state = ""; root.decided(action, root.heard); }
    }

    IpcHandler {
        target: "voice"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.cancel(); }
        function status(): string { return (root.state || "idle") + (server.running ? (root.serverReady ? " · model ready" : " · model loading") : ""); }
        // test the decision without speaking
        function decideText(text: string): void { root.ensureServer(); root.heard = text; root.partial = text; root.state = "thinking"; if (root.serverReady) root.decide(text); else root.pending = text; }
    }
}
