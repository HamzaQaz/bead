.pragma library
// Snoozing a notification: it leaves the screen and comes back later as a
// fresh pop-up. Notifs.qml keeps the list ([{ key, until }], saved with the
// history); Notifications.qml offers the choices. Plain logic:
// tests/tst_snooze.qml.

// a pop-up's buttons once "Later" is pressed (ids starting "__" keep it open)
var choices = [
    { id: "__snooze:20m", label: "20 min" },
    { id: "__snooze:1h", label: "1 hour" },
    { id: "__snooze:tomorrow", label: "Tomorrow" }
];
function choiceOf(id) { return String(id).indexOf("__snooze:") === 0 ? String(id).slice(9) : ""; }

// when a choice comes back (ms), or 0. "Tomorrow" is 9:00 the next morning:
// the same morning if it's said in the small hours
function until(choice, now) {
    if (choice === "20m") return now + 20 * 60000;
    if (choice === "1h") return now + 60 * 60000;
    if (choice === "tomorrow") {
        var d = new Date(now);
        if (d.getHours() >= 4) d.setDate(d.getDate() + 1);
        d.setHours(9, 0, 0, 0);
        return d.getTime();
    }
    return 0;
}

function remove(list, key) { return list.filter(function (s) { return s.key !== key; }); }
function add(list, key, until_) { return remove(list, key).concat([{ key: key, until: until_ }]); }
function when(list, key) { var s = list.filter(function (x) { return x.key === key; })[0]; return s ? s.until : 0; }

// what's due now (keys), and what still waits
function split(list, now) {
    return { due: list.filter(function (s) { return s.until <= now; }).map(function (s) { return s.key; }),
             waiting: list.filter(function (s) { return s.until > now; }) };
}
// without snoozes whose notification is no longer in the history (`keys`)
function prune(list, keys) { return list.filter(function (s) { return keys.indexOf(s.key) >= 0; }); }

function label(until_, now) {
    var d = new Date(until_), n = new Date(now);
    var t = d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
    var sameDay = d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
    return sameDay ? "Back at " + t : "Back tomorrow at " + t;
}
