.pragma library

// The dashboard calendar's logic: the month grid and the selected day moving
// with keys. A day is {y, m, d} with m 0-based (as Date has it); the grid shows
// the selected day's month, Monday first.

function _date(day) { return new Date(day.y, day.m, day.d); }
function _day(date) { return { y: date.getFullYear(), m: date.getMonth(), d: date.getDate() }; }
function _same(a, b) { return a.y === b.y && a.m === b.m && a.d === b.d; }
function _col(day) { return (_date(day).getDay() + 6) % 7; } // 0 Monday … 6 Sunday
function _offset(y, m) { return (new Date(y, m, 1).getDay() + 6) % 7; }
function _length(y, m) { return new Date(y, m + 1, 0).getDate(); }

// The cells for `sel`'s month: 35, or 42 when the month spills into a sixth row.
// Each is {n, inMonth, today, selected, day}.
function grid(sel, today) {
    var off = _offset(sel.y, sel.m);
    var count = off + _length(sel.y, sel.m) > 35 ? 42 : 35;
    var out = [];
    for (var i = 0; i < count; i++) {
        var day = _day(new Date(sel.y, sel.m, 1 - off + i));
        out.push({ n: day.d, inMonth: day.m === sel.m, today: _same(day, today), selected: _same(day, sel), day: day });
    }
    return out;
}

// `sel` moved by `months`, keeping the day of the month where it can.
function page(sel, months) {
    var first = new Date(sel.y, sel.m + months, 1);
    return { y: first.getFullYear(), m: first.getMonth(), d: Math.min(sel.d, _length(first.getFullYear(), first.getMonth())) };
}

// What a key does to the selected day: {day} when the calendar takes it, null
// when it doesn't (off the grid's edge, so the ring moves on; or not its key).
function key(sel, name, today) {
    var col = _col(sel);
    var step = function (n) { var d = _date(sel); d.setDate(d.getDate() + n); return { day: _day(d) }; };
    switch (name) {
    case "Left": return col === 0 ? null : step(-1);
    case "Right": return col === 6 ? null : step(1);
    case "Up": return sel.d <= 7 ? null : step(-7);
    case "Down": return sel.d + 7 > _length(sel.y, sel.m) ? null : step(7);
    case "[": return { day: page(sel, -1) };
    case "]": return { day: page(sel, 1) };
    case "t": return { day: { y: today.y, m: today.m, d: today.d } };
    default: return null;
    }
}
