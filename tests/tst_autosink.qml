import QtQuick
import QtTest
import "../services/autosink.js" as A

// Following Bluetooth headphones (services/autosink.js): switch to them when
// they connect, back when they go.
TestCase {
    name: "AutoSink"

    function test_new_bluetooth_output_is_used() {
        compare(A.decide(["alsa_usb_headset"], ["alsa_usb_headset", "bluez_output.AA.1"], "alsa_usb_headset", ""), { use: "bluez_output.AA.1", before: "alsa_usb_headset" });
    }
    function test_a_new_wired_output_is_left_alone() {
        compare(A.decide(["alsa_usb_headset"], ["alsa_usb_headset", "alsa_hdmi"], "alsa_usb_headset", ""), null);
    }
    function test_already_on_it_does_nothing() {
        compare(A.decide(["alsa_usb_headset"], ["alsa_usb_headset", "bluez_output.AA.1"], "bluez_output.AA.1", ""), null);
    }
    function test_going_back_when_they_disconnect() {
        compare(A.decide(["alsa_usb_headset", "bluez_output.AA.1"], ["alsa_usb_headset"], "", "bluez_output.AA.1", "alsa_usb_headset"), { use: "alsa_usb_headset", before: "" });
    }
    function test_no_going_back_when_the_old_output_is_gone_too() {
        compare(A.decide(["alsa_usb_headset", "bluez_output.AA.1"], [], "", "bluez_output.AA.1", "alsa_usb_headset"), { use: "", before: "" });
    }
    function test_a_profile_switch_that_renames_the_output_is_followed() {
        // A2DP → headset mode: .1 goes, .2 comes in one change; stay on the headphones
        compare(A.decide(["alsa_usb_headset", "bluez_output.AA.1"], ["alsa_usb_headset", "bluez_output.AA.2"], "bluez_output.AA.1", "bluez_output.AA.1", "alsa_usb_headset"),
            { use: "bluez_output.AA.2", before: "alsa_usb_headset" });
    }
    function test_headphones_still_there_under_another_output_are_not_left() {
        // the old output goes first and the new one is already listed: no going back
        compare(A.decide(["alsa_usb_headset", "bluez_output.AA.1", "bluez_output.AA.2"], ["alsa_usb_headset", "bluez_output.AA.2"], "bluez_output.AA.1", "bluez_output.AA.1", "alsa_usb_headset"),
            { use: "bluez_output.AA.2", before: "alsa_usb_headset" });
    }
    function test_going_back_waits_out_a_blip() {
        verify(A.waits(["alsa_usb_headset", "bluez_output.AA.1"], ["alsa_usb_headset"], "bluez_output.AA.1"));
        verify(!A.waits(["alsa_usb_headset", "alsa_hdmi"], ["alsa_usb_headset"], "bluez_output.AA.1"));
        verify(!A.waits(["alsa_usb_headset", "bluez_output.AA.1"], ["alsa_usb_headset"], ""));
    }
    function test_the_same_headphones_coming_back_are_used_again() {
        // they dropped (sound went back), then returned within moments: back on them
        compare(A.decide(["alsa_usb_headset"], ["alsa_usb_headset", "bluez_output.AA.1"], "alsa_usb_headset", "", ""),
            { use: "bluez_output.AA.1", before: "alsa_usb_headset" });
    }
    function test_headphones_are_one_device_whatever_the_profile() {
        verify(A.sameDevice("bluez_output.E8_8F_16.1", "bluez_output.E8_8F_16.2"));
        verify(!A.sameDevice("bluez_output.E8_8F_16.1", "bluez_output.AA_BB.1"));
        verify(!A.sameDevice("alsa_x", "alsa_x"));
    }
}
