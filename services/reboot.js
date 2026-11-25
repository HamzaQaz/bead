.pragma library

// Scheduling a restart after an update (services/Updates.qml, the island's
// UpdateView): the next time a clock time comes round, how it reads, and the
// string systemd-run takes. Tested in tests/tst_reboot.qml.

// the next h:m after now (the current minute counts as gone)
function next(h, m, now) {
    const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m, 0, 0);
    if (t <= now) t.setDate(t.getDate() + 1);
    return t;
}

function hm(t) { return t.getHours() + ":" + String(t.getMinutes()).padStart(2, "0"); }

function label(t, now) {
    const mins = Math.round((t - now) / 60000);
    if (mins < 30) return "In " + mins + (mins === 1 ? " minute" : " minutes");
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const days = Math.round((new Date(t.getFullYear(), t.getMonth(), t.getDate()) - day) / 86400000);
    const h = t.getHours();
    if ((days === 0 && h >= 18) || (days === 1 && h < 6)) return "Tonight at " + hm(t);
    if (days === 0) return "Today at " + hm(t);
    if (days === 1) return "Tomorrow at " + hm(t);
    return Qt.formatDateTime(t, "ddd") + " at " + hm(t);
}

function pad(n) { return String(n).padStart(2, "0"); }
function calendar(t) {
    return t.getFullYear() + "-" + pad(t.getMonth() + 1) + "-" + pad(t.getDate()) + " " + pad(t.getHours()) + ":" + pad(t.getMinutes()) + ":00";
}

// a custom time, nudged by some minutes, round the clock
function step(h, m, by) {
    const total = ((h * 60 + m + by) % 1440 + 1440) % 1440;
    return [Math.floor(total / 60), total % 60];
}
