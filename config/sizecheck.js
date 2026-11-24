.pragma library
// Changing bead's size (Settings → Appearance → Size). Nothing changes until it's
// applied, and after the restart the island asks whether to keep it, going
// back by itself if nobody says so: a size that turns out unusable undoes
// itself. Plain logic: tests/tst_sizecheck.qml.

function percent(scale) { return Math.round(scale * 100) + "%"; }

// what the row says while a size is picked but not applied (its column is
// narrow: the Apply button beside it says the rest)
function changeHint(from, to) { return percent(from) + " → " + percent(to); }

// a pick to hold on to: "" when it's the size already in use
function pick(value, scale) { return Math.abs(Number(value) - scale) < 0.001 ? "" : String(value); }

// after the restart: `was` is the size before (0: nothing to confirm)
function pending(scale, was) { return was > 0 && Math.abs(was - scale) > 0.001; }

function prompt(scale, left) { return "Size is now " + percent(scale) + " · tap to keep · back in " + left + " s"; }

// one second later
function next(left) { return { left: left - 1, revert: left - 1 <= 0 }; }
