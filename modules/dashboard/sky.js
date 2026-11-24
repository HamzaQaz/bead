.pragma library

// The Weather tab's moving backdrop for a WMO weather code (as Open-Meteo
// gives it, the same ranges Weather.icon uses): which motion, and how much.
// The kinds match shaders/sky.frag.

var SUN = 1, STARS = 2, CLOUD = 3, RAIN = 4, SNOW = 5, STORM = 6;

function of(code, isDay) {
    var c = code;
    if (c === 0) return { kind: isDay ? SUN : STARS, amount: 1 };
    if (c <= 2) return { kind: CLOUD, amount: c === 1 ? 0.3 : 0.45 };
    if (c === 3) return { kind: CLOUD, amount: 0.7 };
    if (c <= 48) return { kind: CLOUD, amount: 1 };          // fog
    if (c <= 57) return { kind: RAIN, amount: 0.3 };         // drizzle
    if (c <= 67) return { kind: RAIN, amount: c % 10 >= 5 ? 0.85 : c % 10 >= 3 ? 0.65 : 0.45 };
    if (c <= 77) return { kind: SNOW, amount: c % 10 >= 5 ? 0.9 : 0.6 };
    if (c <= 82) return { kind: RAIN, amount: c === 80 ? 0.7 : c === 81 ? 0.85 : 1 };
    if (c <= 86) return { kind: SNOW, amount: c === 86 ? 1 : 0.75 };
    return { kind: STORM, amount: 1 };
}
