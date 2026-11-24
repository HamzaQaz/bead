import QtQuick
import QtTest
import "../services/nightlight.js" as Night

// The night light: a warmer screen, on by hand or from sunset to sunrise
// (services/nightlight.js).
TestCase {
    name: "NightLight"

    function at(h, m) { return new Date(2026, 10, 24, h, m, 0, 0).getTime(); }
    readonly property real rise: at(7, 10)
    readonly property real set: at(16, 50)

    // ── one tap goes to the next mode ──
    function test_modes_go_off_on_sunset_and_round_again() {
        compare(Night.nextMode("off"), "on");
        compare(Night.nextMode("on"), "sunset");
        compare(Night.nextMode("sunset"), "off");
        compare(Night.nextMode("something else"), "on");
    }

    // ── is the screen warm right now? ──
    function test_off_is_never_warm() { verify(!Night.warm("off", at(23, 0), rise, set)); }
    function test_on_is_always_warm() { verify(Night.warm("on", at(12, 0), rise, set)); }
    function test_sunset_mode_is_warm_after_sunset() { verify(Night.warm("sunset", at(17, 0), rise, set)); }
    function test_sunset_mode_is_warm_before_sunrise() { verify(Night.warm("sunset", at(5, 0), rise, set)); }
    function test_sunset_mode_is_not_warm_by_day() { verify(!Night.warm("sunset", at(12, 0), rise, set)); }
    function test_the_sun_times_only_count_by_their_time_of_day() {
        // yesterday's times still say when today's evening starts
        verify(Night.warm("sunset", at(17, 0) + 86400000, rise, set));
        verify(!Night.warm("sunset", at(12, 0) + 86400000, rise, set));
    }
    function test_without_sun_times_night_is_seven_to_seven() {
        verify(Night.warm("sunset", at(19, 30), 0, 0));
        verify(Night.warm("sunset", at(6, 30), 0, 0));
        verify(!Night.warm("sunset", at(18, 30), 0, 0));
    }

    // ── the warmth ──
    function test_warmth_stays_between_candlelight_and_daylight() {
        compare(Night.temp(4500), 4500);
        compare(Night.temp(900), 2500);
        compare(Night.temp(9000), 6000);
        compare(Night.temp(undefined), 4500);
    }

    // ── what the chip shows ──
    function test_the_chip_names_the_mode() {
        compare(Night.chip("off", false).label, "Warm");
        compare(Night.chip("on", true).label, "Warm");
        compare(Night.chip("sunset", false).label, "Sunset");
    }
    function test_the_chip_is_lit_only_while_the_screen_is_warm() {
        verify(!Night.chip("off", false).lit);
        verify(Night.chip("on", true).lit);
        verify(!Night.chip("sunset", false).lit);
        verify(Night.chip("sunset", true).lit);
    }
    function test_the_toast_says_what_a_tap_did() {
        compare(Night.said("on", true, set), "Night light on");
        compare(Night.said("off", false, set), "Night light off");
        compare(Night.said("sunset", false, set), "Night light from sunset · 16:50");
        compare(Night.said("sunset", true, set), "Night light until sunrise");
        compare(Night.said("sunset", false, 0), "Night light from sunset · 19:00");
    }
}
