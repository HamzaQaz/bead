.pragma library

// bead's mic effects and "Both" output (services/AudioFx.qml): the PipeWire
// filter chain for the mic (RNNoise, an EQ preset, gain), and the arguments
// for the modules it loads. Tested in tests/tst_audiofx.qml.

// EQ presets: PipeWire's built-in biquads, in order
const presets = {
    off: [],
    // cut rumble, lift presence
    clear: [{ label: "bq_highpass", c: { Freq: 90, Q: 0.7 } }, { label: "bq_peaking", c: { Freq: 3000, Q: 1, Gain: 4 } }],
    // a little body, softer top
    warm: [{ label: "bq_highpass", c: { Freq: 70, Q: 0.7 } }, { label: "bq_lowshelf", c: { Freq: 180, Q: 0.7, Gain: 3 } }, { label: "bq_highshelf", c: { Freq: 8000, Q: 0.7, Gain: -2 } }],
    // telephone / walkie-talkie
    radio: [{ label: "bq_highpass", c: { Freq: 300, Q: 0.7 } }, { label: "bq_lowpass", c: { Freq: 3400, Q: 0.7 } }, { label: "bq_peaking", c: { Freq: 1500, Q: 1, Gain: 3 } }]
};
const presetNames = ["off", "clear", "warm", "radio"];

// the chain's nodes, in order
function nodeNames(o) {
    const n = [];
    if (o.noise) n.push("rnnoise");
    (presets[o.eq] || []).forEach((_, i) => n.push("eq" + (i + 1)));
    if (o.gain && Math.abs(o.gain - 1) > 0.001) n.push("gain");
    return n;
}

function controls(c) { return Object.keys(c).map(k => '"' + k + '" = ' + c[k]).join(" "); }

// the whole config for `pipewire -c <file>`; "" when nothing's on
function micChain(o, rnnoise) {
    const names = nodeNames(o);
    if (!names.length) return "";
    const eq = presets[o.eq] || [];
    const nodes = names.map(name => {
        if (name === "rnnoise")
            return '{ type = ladspa name = rnnoise plugin = "' + rnnoise + '" label = noise_suppressor_mono control = { "VAD Threshold (%)" = ' + Math.round(o.threshold ?? 50) + ' "VAD Grace Period (ms)" = 200 } }';
        if (name === "gain")
            return '{ type = builtin name = gain label = linear control = { "Mult" = ' + o.gain + ' "Add" = 0 } }';
        const f = eq[+name.slice(2) - 1];
        return '{ type = builtin name = ' + name + ' label = ' + f.label + ' control = { ' + controls(f.c) + ' } }';
    });
    const port = (name, dir) => name + ":" + (name === "rnnoise" ? (dir === "in" ? "Input" : "Output") : (dir === "in" ? "In" : "Out"));
    const links = [];
    for (let i = 0; i + 1 < names.length; i++)
        links.push('{ output = "' + port(names[i], "out") + '" input = "' + port(names[i + 1], "in") + '" }');
    return `# written by bead (services/AudioFx.qml); remade on every change
context.properties = { log.level = 0 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "bead Mic"
            media.name = "bead Mic"
            filter.graph = {
                nodes = [
                    ${nodes.join("\n                    ")}
                ]
                links = [
                    ${links.join("\n                    ")}
                ]
            }
            capture.props = { node.name = "capture.bead_mic" node.passive = true ${o.source ? 'target.object = "' + o.source + '" node.dont-reconnect = true ' : ""}audio.rate = 48000 audio.channels = 1 audio.position = [ MONO ] }
            playback.props = { node.name = "bead_mic" node.description = "bead Mic" media.class = Audio/Source audio.rate = 48000 audio.channels = 1 audio.position = [ MONO ] }
        }
    }
]
`;
}

// pactl arguments: both outputs at once (null unless two different devices)
function combineArgs(sinks) {
    const s = (sinks || []).filter((x, i, a) => x && a.indexOf(x) === i);
    if (s.length < 2) return null;
    return ["load-module", "module-combine-sink", "sink_name=bead_both", "sink_properties=device.description=Both", "slaves=" + s.join(",")];
}

// hearing your mic in your headphones
function loopbackArgs(source, latency) {
    return ["load-module", "module-loopback", "source=" + source, "latency_msec=" + latency, "source_dont_move=true", "sink_input_properties=media.name=bead-monitor"];
}
