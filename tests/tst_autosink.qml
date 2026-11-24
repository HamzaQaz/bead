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
}
