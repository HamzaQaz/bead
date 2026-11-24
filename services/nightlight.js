.pragma library
// The night light: a warmer screen (hyprsunset), on by hand or from sunset
// to sunrise. NightLight.qml runs it; this is the deciding. Plain logic:
// tests/tst_nightlight.qml.
//
// mode: "off" | "on" | "sunset". Times are ms; sunrise and sunset are the
// weather's for some day (0: not known, so 7:00 and 19:00).

function nextMode(mode) { return mode === "on" ? "sunset" : mode === "sunset" ? "off" : "on"; }

function minutes(ms) { var d = new Date(ms); return d.getHours() * 60 + d.getMinutes(); }
function sunTimes(sunrise, sunset) { return { rise: sunrise ? minutes(sunrise) : 7 * 60, set: sunset ? minutes(sunset) : 19 * 60 }; }

// is the screen warm now?
function warm(mode, now, sunrise, sunset) {
    if (mode === "on") return true;
    if (mode !== "sunset") return false;
    var s = sunTimes(sunrise, sunset), m = minutes(now);
    return m >= s.set || m < s.rise;
}

// the colour temperature, in K: candlelight to daylight
function temp(k) { return Math.max(2500, Math.min(6000, Math.round(Number(k)) || 4500)); }

function chip(mode, isWarm) { return { label: mode === "sunset" ? "Sunset" : "Warm", lit: !!isWarm }; }

// what to say after a tap
function said(mode, isWarm, sunset) {
    if (mode === "on") return "Night light on";
    if (mode !== "sunset") return "Night light off";
    if (isWarm) return "Night light until sunrise";
    var s = sunTimes(0, sunset).set, mm = s % 60;
    return "Night light from sunset · " + Math.floor(s / 60) + ":" + (mm < 10 ? "0" : "") + mm;
}
