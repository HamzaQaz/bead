.pragma library

// What a polkit request is for (services/Polkit.qml): the program pkexec
// would run, from polkit's message, past wrappers like stdbuf and env.
// Tested in tests/tst_polkit.qml.

const wrappers = ["stdbuf", "env", "nice", "ionice", "sh", "bash", "unbuffer"];

function program(message) {
    const m = /`([^'`]+)['`]/.exec(message || "");
    if (!m) return "";
    for (const w of m[1].trim().split(/\s+/)) {
        if (w.startsWith("-") || /^\w+=/.test(w)) continue;
        const name = w.split("/").pop();
        if (!wrappers.includes(name)) return name;
    }
    return "";
}

function describe(message) {
    const p = program(message);
    return p ? p + " wants to run as administrator" : (message || "");
}
