import QtQuick
import QtTest
import "../components/emptystates.js" as Empty

// What a panel says when it has nothing to show, is still loading, or
// couldn't load (components/emptystates.js).
TestCase {
    name: "EmptyStates"

    // ── weather ──
    function test_weather_that_is_there_needs_no_message() { compare(Empty.weather({ ready: true, failed: false }), null); }
    function test_weather_on_its_way_says_so_without_a_retry() {
        const s = Empty.weather({ ready: false, failed: false });
        compare(s.text, "Getting the weather…");
        verify(!s.retry);
    }
    function test_weather_that_failed_says_why_and_offers_a_retry() {
        const s = Empty.weather({ ready: false, failed: true });
        compare(s.text, "Couldn't get the weather");
        compare(s.hint, "Check the connection, then try again");
        verify(s.retry);
    }
    function test_old_weather_stays_up_when_a_refresh_fails() { compare(Empty.weather({ ready: true, failed: true }), null); }

    // ── wallpapers ──
    function test_wallpapers_that_exist_need_no_message() { compare(Empty.wallpapers({ shown: 3, stills: 3, lives: 0, filter: "all", dir: "~/Pictures/Wallpapers" }), null); }
    function test_no_wallpapers_at_all_says_where_to_put_them() {
        const s = Empty.wallpapers({ shown: 0, stills: 0, lives: 0, filter: "all", dir: "~/Pictures/Wallpapers" });
        compare(s.text, "No wallpapers yet");
        compare(s.hint, "Put pictures in ~/Pictures/Wallpapers");
        verify(s.open);
    }
    function test_an_empty_filter_points_back_to_the_others() {
        const s = Empty.wallpapers({ shown: 0, stills: 4, lives: 0, filter: "live", dir: "~/Pictures/Wallpapers" });
        compare(s.text, "No live wallpapers");
        compare(s.hint, "4 still ones are under All");
        verify(!s.open);
    }
    function test_an_empty_still_filter_counts_the_live_ones() {
        compare(Empty.wallpapers({ shown: 0, stills: 0, lives: 1, filter: "still", dir: "x" }).hint, "1 live one is under All");
    }

    // ── Wi-Fi ──
    function test_wifi_off_says_so() { compare(Empty.wifi({ enabled: false, adapter: true, nets: 0, looking: 0 }), "Wi-Fi is off"); }
    function test_no_adapter_says_so() { compare(Empty.wifi({ enabled: true, adapter: false, nets: 0, looking: 0 }), "No Wi-Fi adapter"); }
    function test_wifi_looks_for_a_while() { compare(Empty.wifi({ enabled: true, adapter: true, nets: 0, looking: 4 }), "Looking for networks…"); }
    function test_wifi_that_finds_nothing_stops_saying_it_is_looking() { compare(Empty.wifi({ enabled: true, adapter: true, nets: 0, looking: 12 }), "No networks in range"); }
    function test_wifi_with_networks_says_nothing() { compare(Empty.wifi({ enabled: true, adapter: true, nets: 3, looking: 12 }), ""); }
}
