import QtQuick
import QtTest
import "../config/blend.js" as Blend

// Fading from one palette to the next (config/blend.js, used by Theme.qml).
TestCase {
    name: "Blend"

    function test_mix_at_the_start_is_the_old_colour() { compare(Blend.mixHex("102030", "ffffff", 0), "#102030"); }
    function test_mix_at_the_end_is_the_new_colour() { compare(Blend.mixHex("102030", "a0b0c0", 1), "#a0b0c0"); }
    function test_mix_halfway_is_between_them_per_channel() { compare(Blend.mixHex("000000", "ffffff", 0.5), "#808080"); }
    function test_mix_keeps_two_digits_for_dark_channels() { compare(Blend.mixHex("000000", "0a0a0a", 0.5), "#050505"); }
    function test_mix_outside_0_to_1_is_clamped() {
        compare(Blend.mixHex("000000", "ffffff", -1), "#000000");
        compare(Blend.mixHex("000000", "ffffff", 2), "#ffffff");
    }
    function test_mix_from_something_that_is_not_a_colour_is_the_new_colour() {
        compare(Blend.mixHex(undefined, "a0b0c0", 0.3), "#a0b0c0");
        compare(Blend.mixHex("nope", "a0b0c0", 0.3), "#a0b0c0");
    }

    // a part of the ripple: it starts at `start` and takes `span` of it
    function test_phase_before_its_start_is_0() { compare(Blend.phase(0.1, 0.25, 0.75), 0); }
    function test_phase_after_its_end_is_1() { compare(Blend.phase(1, 0, 0.75), 1); }
    function test_phase_runs_evenly_in_between() { fuzzyCompare(Blend.phase(0.625, 0.25, 0.75), 0.5, 1e-9); }

    // has the palette changed? (same keys and values, in any order: no)
    function test_same_palette_in_another_order_is_not_a_change() { verify(!Blend.differs({ a: "111111", b: "222222" }, { b: "222222", a: "111111" })); }
    function test_a_changed_colour_is_a_change() { verify(Blend.differs({ a: "111111" }, { a: "111112" })); }
    function test_a_new_or_missing_colour_is_a_change() {
        verify(Blend.differs({ a: "111111" }, { a: "111111", b: "222222" }));
        verify(Blend.differs({ a: "111111", b: "222222" }, { a: "111111" }));
    }
}
