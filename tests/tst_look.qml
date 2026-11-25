import QtQuick
import QtTest
import "../config/look.js" as L

// Customisation (config/look.js): every option once, with its page, range and
// default; values checked on the way in, presets, and a look as shareable text.
TestCase {
    name: "Look"

    // ── the schema ──
    function test_every_option_has_a_page_a_label_and_a_valid_default() {
        const pages = L.PAGES.map(p => p.id);
        const seen = {};
        for (const o of L.SCHEMA) {
            verify(!seen[o.k], "one entry per key: " + o.k);
            seen[o.k] = true;
            verify(pages.indexOf(o.page) >= 0, o.k + " is on a page");
            verify(o.label.length > 0, o.k + " has a label");
            compare(L.clean(o, o.def), o.def, o.k + "'s default is valid");
        }
        verify(L.SCHEMA.length >= 60, "plenty to customise");
    }
    function test_each_customisation_page_has_options() {
        for (const p of L.PAGES) verify(L.SCHEMA.some(o => o.page === p.id), p.id);
    }

    // ── values on the way in ──
    function test_numbers_are_clamped_and_snapped_to_their_step() {
        const o = L.entry("islandHoverDelay");
        compare(L.clean(o, 5000), o.max);
        compare(L.clean(o, -3), o.min);
        compare(L.clean(o, 231), 240);   // step 20
        compare(L.clean(o, "fast"), o.def);
    }
    function test_choices_bools_and_colours_fall_back_to_the_default() {
        compare(L.clean(L.entry("popScreen"), "nowhere"), "island");
        compare(L.clean(L.entry("popScreen"), "focused"), "focused");
        compare(L.clean(L.entry("islandGlow"), "yes"), true);   // not a bool: the default
        compare(L.clean(L.entry("islandGlow"), false), false);
        compare(L.clean(L.entry("accent"), "#12abEF"), "#12abef");
        compare(L.clean(L.entry("accent"), "red; rm -rf"), "");
        compare(L.clean(L.entry("accent"), ""), "");
    }
    function test_per_app_rules_keep_only_known_rules() {
        const o = L.entry("popApps");
        compare(L.clean(o, { Discord: "quiet", Spotify: "loud", "": "quiet" }), { Discord: "quiet" });
        compare(L.clean(o, "x"), {});
    }
    function test_load_fills_defaults_and_drops_unknown_keys() {
        const v = L.load({ islandRadius: 12, nope: 1, popMax: 99 });
        compare(v.islandRadius, 12);
        compare(v.popMax, 8);
        compare(v.nope, undefined);
        compare(v.islandGlow, true);
    }
    function test_set_returns_a_new_object_and_validates() {
        const a = L.load({});
        const b = L.set(a, "speed", 9);
        compare(a.speed, 1);
        compare(b.speed, 2);
        compare(L.set(a, "unknown", 1), a);
    }

    // ── what's changed, and resetting a page ──
    function test_changes_and_reset_page() {
        let v = L.set(L.set(L.load({}), "islandRadius", 10), "popMax", 2);
        compare(L.changed(v).sort(), ["islandRadius", "popMax"]);
        compare(L.changed(v, "island"), ["islandRadius"]);
        v = L.resetPage(v, "island");
        compare(L.changed(v), ["popMax"]);
    }

    // ── presets ──
    function test_built_in_presets_are_valid_and_start_from_the_defaults() {
        for (const p of L.PRESETS) {
            for (const k in p.values) verify(L.entry(k), p.name + ": " + k + " is an option");
            const v = L.preset(p.id, {});
            for (const k in p.values) compare(v[k], L.clean(L.entry(k), p.values[k]), p.name + " " + k);
        }
        compare(L.changed(L.preset("bead", {})), []);
    }
    function test_a_saved_preset_is_applied_like_a_built_in() {
        const mine = { "My look": { islandRadius: 5 } };
        compare(L.preset("My look", mine).islandRadius, 5);
        compare(L.preset("missing", mine), null);
    }
    function test_which_preset_the_values_match() {
        compare(L.matching(L.load({}), {}), "bead");
        compare(L.matching(L.preset("minimal", {}), {}), "minimal");
        compare(L.matching(L.set(L.load({}), "popMax", 1), {}), "");
        compare(L.matching(L.load({ islandRadius: 5 }), { "Mine": { islandRadius: 5 } }), "Mine");
    }

    // ── sharing a look as text ──
    function test_export_keeps_only_changes_and_imports_back() {
        const v = L.set(L.set(L.load({}), "islandRadius", 10), "accent", "#ff0088");
        const text = L.exportText(v, "Pink");
        const obj = JSON.parse(text);
        compare(obj.bead, "look");
        compare(obj.name, "Pink");
        compare(Object.keys(obj.values).sort(), ["accent", "islandRadius"]);
        const back = L.importText(text);
        verify(back.ok);
        compare(back.name, "Pink");
        compare(back.values, v);
    }
    function test_import_rejects_what_isnt_a_look_and_cleans_what_is() {
        verify(!L.importText("hello").ok);
        verify(!L.importText('{"values":{}}').ok);   // not marked as a look
        const r = L.importText('{"bead":"look","values":{"popMax":40,"evil":"x","accent":"javascript:1"}}');
        verify(r.ok);
        compare(r.values.popMax, 8);
        compare(r.values.accent, "");
        compare(r.values.evil, undefined);
        compare(r.name, "Imported look");
    }

    // ── motion: speed and bounce shape the spring ──
    function test_spring_bounce_zero_never_overshoots_and_one_is_sileos() {
        const sileo = t => t < 0.5 ? 0.5 : 1.03;   // stand-ins for the two curves
        const settle = t => t < 0.5 ? 0.4 : 1;
        compare(L.blend(sileo(0.6), settle(0.6), 0), 1);
        compare(L.blend(sileo(0.6), settle(0.6), 1), 1.03);
        fuzzyCompare(L.blend(sileo(0.6), settle(0.6), 2), 1.06, 1e-9);
        compare(L.duration(600, { motionOn: true, speed: 2 }), 300);
        compare(L.duration(600, { motionOn: false, speed: 1 }), 1);
    }

    // ── searching settings finds options by label, hint and words ──
    function test_search_finds_options() {
        const hits = L.search("melt").map(o => o.k);
        verify(hits.indexOf("islandGoo") >= 0);
        verify(hits.indexOf("popGoo") >= 0);
        compare(L.search("").length, 0);
    }
}
