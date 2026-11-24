.pragma library

// Following Bluetooth headphones: given the output names before and now, the
// current default, the one bead switched to (if any) and what was in use
// before that, what to do: { use: name to switch to ("" for nothing left to
// go back to), before: what to go back to later }, or null to leave it be.
function _bt(n) { return /^bluez_output\./.test(n); }

function decide(was, now, current, switchedTo, before) {
    var added = now.filter(function (n) { return was.indexOf(n) < 0; });
    var gone = was.filter(function (n) { return now.indexOf(n) < 0; });
    var bt = added.filter(_bt);
    if (bt.length) {
        if (bt[0] === current) return null;
        // a renamed output of the same headphones keeps the original "before"
        return { use: bt[0], before: switchedTo && gone.indexOf(switchedTo) >= 0 ? (before || "") : current };
    }
    if (switchedTo && gone.indexOf(switchedTo) >= 0)
        return { use: before && now.indexOf(before) >= 0 ? before : "", before: "" };
    return null;
}
