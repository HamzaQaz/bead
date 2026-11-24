.pragma library

// What `bluetoothctl --agent NoInputNoOutput pair <addr>` printed, as a
// message for the panel: "" when it paired. bluetoothctl exits 0 either way.
function pairResult(text) {
    var t = String(text || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
    if (/Pairing successful|Error\.AlreadyExists/.test(t)) return "";
    if (/not available/.test(t)) return "Not found. Put it in pairing mode and try again";
    if (/Error\.(AuthenticationTimeout|ConnectionAttemptFailed|AuthenticationCanceled|PageTimeout)/.test(t)) return "It didn't answer. Put it in pairing mode and try again";
    if (/Error\.(AuthenticationFailed|AuthenticationRejected)/.test(t)) return "It refused. Put it in pairing mode and try again";
    var m = /Failed to pair: org\.bluez\.Error\.(\w+)/.exec(t);
    return m ? "Couldn't pair (" + m[1] + ")" : "Couldn't pair";
}
