import QtQuick
import QtTest
import "../modules/bar/bluetooth.js" as Bt

// Reading what `bluetoothctl --agent NoInputNoOutput pair <addr>` printed
// (modules/bar/bluetooth.js): it exits 0 either way.
TestCase {
    name: "Bluetooth"

    function test_success_is_no_message() {
        compare(Bt.pairResult("Attempting to pair with AA:BB:CC:DD:EE:FF\n[CHG] Device AA:BB:CC:DD:EE:FF Paired: yes\nPairing successful\n"), "");
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.AlreadyExists\n"), "");
    }
    function test_colour_codes_are_ignored() {
        compare(Bt.pairResult("\u001b[0;94m[bluetoothctl]\u001b[0m> Pairing successful\n"), "");
    }
    function test_a_device_that_went_away() {
        compare(Bt.pairResult("Device 00:11:22:33:44:55 not available\n"), "Not found. Put it in pairing mode and try again");
    }
    function test_a_device_that_did_not_answer_or_said_no() {
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.AuthenticationTimeout\n"), "It didn't answer. Put it in pairing mode and try again");
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.ConnectionAttemptFailed\n"), "It didn't answer. Put it in pairing mode and try again");
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.AuthenticationFailed\n"), "It refused. Put it in pairing mode and try again");
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.AuthenticationRejected\n"), "It refused. Put it in pairing mode and try again");
    }
    function test_anything_else_says_what_bluez_said() {
        compare(Bt.pairResult("Failed to pair: org.bluez.Error.InProgress\n"), "Couldn't pair (InProgress)");
        compare(Bt.pairResult(""), "Couldn't pair");
    }
}
