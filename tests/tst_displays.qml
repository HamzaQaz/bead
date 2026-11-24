import QtQuick
import QtTest
import "../services/displays.js" as D

// The Displays tab's logic (services/displays.js): reading hyprctl monitors,
// building a full hl.monitor spec, and snapping a dragged monitor.
TestCase {
    name: "Displays"

    readonly property var dp: ({ name: "DP-1", width: 1920, height: 1080, refreshRate: 165.00101, x: 0, y: 0, scale: 1, transform: 0, vrr: false,
        currentFormat: "XRGB8888", colorManagementPreset: "srgb", sdrBrightness: 1, sdrSaturation: 1,
        availableModes: ["1920x1080@60.00Hz", "1920x1080@165.00Hz", "1920x1080@144.00Hz", "1280x720@60.00Hz", "1920x1080@60.00Hz"] })
    readonly property var hdmi: ({ name: "HDMI-A-1", width: 1920, height: 1080, refreshRate: 60, x: -1080, y: 0, scale: 1, transform: 1, vrr: false,
        currentFormat: "XRGB2101010", colorManagementPreset: "srgb", sdrBrightness: 1.2, sdrSaturation: 0.9, availableModes: [] })

    function test_rates_for_the_current_size_highest_first_without_repeats() {
        compare(D.rates(dp), [165, 144, 60]);
    }
    function test_rates_that_round_the_same_show_once_keeping_the_closest_to_whole() {
        const m = Object.assign({}, dp);
        m.availableModes = ["1920x1080@119.88Hz", "1920x1080@120.00Hz", "1920x1080@59.94Hz"];
        compare(D.rates(m), [120, 59.94]);
    }
    function test_a_rotated_monitor_is_tall() {
        compare(D.logical(hdmi), { x: -1080, y: 0, w: 1080, h: 1920 });
        compare(D.logical(Object.assign({}, dp, { scale: 1.5 })), { x: 0, y: 0, w: 1280, h: 720 });
    }
    function test_a_spec_keeps_everything_it_does_not_change() {
        const s = D.spec(hdmi, { rate: 75 });
        verify(s.indexOf('output = "HDMI-A-1"') >= 0, s);
        verify(s.indexOf('mode = "1920x1080@75"') >= 0, s);
        verify(s.indexOf('position = "-1080x0"') >= 0, s);
        verify(s.indexOf("transform = 1") >= 0, s);
        verify(s.indexOf('cm = "srgb"') >= 0, s);
        verify(s.indexOf("sdrbrightness = 1.2") >= 0, s);
        verify(s.indexOf("sdrsaturation = 0.9") >= 0, s);
        verify(s.indexOf("bitdepth = 10") >= 0, s);
        verify(s.startsWith("hl.monitor({") && s.endsWith("})"), s);
    }
    function test_a_spec_takes_the_changes() {
        const s = D.spec(dp, { scale: 1.25, transform: 3, x: 1920, y: -200 });
        verify(s.indexOf("scale = 1.25") >= 0, s);
        verify(s.indexOf("transform = 3") >= 0, s);
        verify(s.indexOf('position = "1920x-200"') >= 0, s);
        verify(s.indexOf('mode = "1920x1080@165"') >= 0, s);   // the live rate, rounded
        verify(s.indexOf("bitdepth = 8") >= 0, s);
    }
    function test_names_cannot_break_out_of_the_lua_string() {
        const evil = "x\" }) os.execute(\"y";
        const m = Object.assign({}, dp);
        m.name = evil;
        verify(D.spec(m, {}).indexOf("os.execute(\"") < 0);
    }
    function test_a_dragged_monitor_snaps_edge_to_edge() {
        const other = [{ x: 0, y: 0, w: 1920, h: 1080 }];
        // dropped a little off DP-1's right edge, a little low: sits flush, tops aligned
        compare(D.snap({ x: 1950, y: 40, w: 1080, h: 1920 }, other, 80), { x: 1920, y: 0 });
        // to the left, bottoms aligned
        compare(D.snap({ x: -1100, y: -790, w: 1080, h: 1920 }, other, 80), { x: -1080, y: -840 });
    }
    function test_a_monitor_far_from_the_others_is_pulled_next_to_the_nearest() {
        const p = D.snap({ x: 5000, y: 3000, w: 1920, h: 1080 }, [{ x: 0, y: 0, w: 1920, h: 1080 }], 80);
        verify(p.x === 1920 || p.y === 1080, JSON.stringify(p));
    }
    function test_snapping_never_overlaps() {
        const p = D.snap({ x: 900, y: 100, w: 1920, h: 1080 }, [{ x: 0, y: 0, w: 1920, h: 1080 }], 80);
        verify(p.x >= 1920 || p.x <= -1920 || p.y >= 1080 || p.y <= -1080, JSON.stringify(p));
    }
}
