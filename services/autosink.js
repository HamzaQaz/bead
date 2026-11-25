.pragma library

// Following Bluetooth headphones: given the output names before and now, the
// current default, the one bead switched to (if any) and what was in use
// before that, what to do: { use: name to switch to ("" for nothing left to
// go back to), before: what to go back to later }, or null to leave it be.
function _bt(n) { return /^bluez_output\./.test(n); }
// the headphones themselves, whichever profile's output this is (bluez_output.MAC.N)
function _dev(n) { var m = /^bluez_output\.(.+)\.\d+$/.exec(n || ""); return m ? m[1] : ""; }
function sameDevice(a, b) { var d = _dev(a); return !!d && d === _dev(b); }

// the headphones bead switched to just went: wait a moment before going back
// (opening a game or a call can drop and remake their output in a blink)
function waits(was, now, switchedTo) {
    return !!switchedTo && was.indexOf(switchedTo) >= 0 && now.indexOf(switchedTo) < 0;
}

function decide(was, now, current, switchedTo, before) {
    var added = now.filter(function (n) { return was.indexOf(n) < 0; });
    var gone = was.filter(function (n) { return now.indexOf(n) < 0; });
    var bt = added.filter(_bt);
    if (bt.length) {
        if (bt[0] === current) return null;
        // a renamed output of the same headphones keeps the original "before"
        return { use: bt[0], before: switchedTo && gone.indexOf(switchedTo) >= 0 ? (before || "") : current };
    }
    if (switchedTo && gone.indexOf(switchedTo) >= 0) {
        // still there under another output (a profile change): stay on them
        var still = now.filter(function (n) { return sameDevice(n, switchedTo); })[0];
        if (still) return still === current ? null : { use: still, before: before || "" };
        return { use: before && now.indexOf(before) >= 0 ? before : "", before: "" };
    }
    return null;
}
