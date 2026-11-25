import QtQuick
import QtTest
import "../services/audiofx.js" as F

// bead's mic effects and "Both" output (services/audiofx.js): the PipeWire
// filter chain it writes, and the arguments it loads modules with.
TestCase {
    name: "AudioFx"
    readonly property string rnnoise: "/usr/lib/ladspa/librnnoise_ladspa.so"

    function test_noise_suppression_alone() {
        const c = F.micChain({ noise: true, threshold: 50, eq: "off", gain: 1 }, rnnoise);
        verify(c.includes("librnnoise_ladspa"));
        verify(c.includes("noise_suppressor_mono"));
        verify(c.includes('"VAD Threshold (%)" = 50'));
        verify(!c.includes("bq_"));
    }
    function test_an_eq_preset_adds_its_filters_in_order() {
        const c = F.micChain({ noise: false, eq: "clear", gain: 1 }, rnnoise);
        verify(!c.includes("rnnoise"));
        verify(c.includes("bq_highpass"));
        verify(c.indexOf("bq_highpass") < c.indexOf("bq_peaking"));
    }
    function test_the_chain_is_linked_end_to_end() {
        const c = F.micChain({ noise: true, threshold: 50, eq: "warm", gain: 1.5 }, rnnoise);
        // every node but the last feeds the next
        const names = F.nodeNames({ noise: true, eq: "warm", gain: 1.5 });
        compare(names[0], "rnnoise");
        compare(names[names.length - 1], "gain");
        for (let i = 0; i + 1 < names.length; i++)
            verify(c.includes('output = "' + names[i] + ':') && c.includes('input = "' + names[i + 1] + ':'));
    }
    function test_no_gain_node_at_unity() {
        compare(F.nodeNames({ noise: true, eq: "off", gain: 1 }), ["rnnoise"]);
    }
    function test_nothing_on_is_no_chain() {
        compare(F.micChain({ noise: false, eq: "off", gain: 1 }, rnnoise), "");
    }
    function test_the_virtual_mic_is_named_for_bead() {
        const c = F.micChain({ noise: true, threshold: 50, eq: "off", gain: 1 }, rnnoise);
        verify(c.includes('node.name = "bead_mic"'));
        verify(c.includes('node.description = "bead Mic"'));
        verify(c.includes("Audio/Source"));
    }
    function test_it_records_from_the_chosen_mic_not_the_default() {
        // bead Mic becomes the default input: following the default, it would record itself
        const c = F.micChain({ noise: true, eq: "off", gain: 1, source: "alsa_input.usb-HyperX" }, rnnoise);
        verify(c.includes('target.object = "alsa_input.usb-HyperX"'));
        verify(c.includes("node.dont-reconnect = true"));
    }
    function test_combine_sink_args() {
        compare(F.combineArgs(["a.sink", "b.sink"]), ["load-module", "module-combine-sink", "sink_name=bead_both",
            "sink_properties=device.description=Both", "slaves=a.sink,b.sink"]);
    }
    function test_combine_needs_two_devices() {
        compare(F.combineArgs(["a.sink"]), null);
        compare(F.combineArgs(["a.sink", "a.sink"]), null);
    }
    function test_loopback_args() {
        compare(F.loopbackArgs("mic.src", 30), ["load-module", "module-loopback", "source=mic.src", "latency_msec=30",
            "source_dont_move=true", "sink_input_properties=media.name=bead-monitor"]);
    }
}
