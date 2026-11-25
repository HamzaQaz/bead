.pragma library

// WhatsApp and Telegram in bead (services/Messengers.qml), from the
// notifications they already show: their desktop apps, or web.whatsapp.com /
// web.telegram.org in a browser. Tested in tests/tst_messengers.qml.

const apps = {
    whatsapp: { app: /whats ?app|zapzap|whatsie|wasistlos|karere/i, site: /web\.whatsapp\.com/i },
    telegram: { app: /telegram|ayugram|kotatogram|64gram|materialgram|paper ?plane/i, site: /web\.telegram\.org/i }
};

function source(e) {
    const app = e.appName || "", all = (e.summary || "") + "\n" + (e.body || "");
    for (const k in apps)
        if (apps[k].app.test(app) || apps[k].site.test(all)) return k;
    return "";
}

// the message: no browser origin line, no markup
function text(body) {
    return (body || "")
        .replace(/<[^>]*>/g, "")
        .split("\n")
        .filter(l => !/^\s*(https?:\/\/)?web\.(whatsapp\.com|telegram\.org)\/?\s*$/i.test(l))
        .join(" ")
        .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
        .replace(/\s+/g, " ")
        .trim();
}

// roll-ups like "WhatsApp" / "3 new messages" name no chat
function isRollup(chat, msg) {
    return /^(whats ?app|telegram)$/i.test(chat) || (!chat && /\d+ new messages?/i.test(msg));
}

// entries newest first → [{ app, chat, text, count, time, keys }], newest first.
// read: { "app/chat": time read up to }; on: the apps turned on
function inbox(entries, read, on) {
    const out = [], at = {};
    for (const e of entries || []) {
        const app = source(e);
        if (!app || on.indexOf(app) < 0) continue;
        const chat = (e.summary || "").replace(/<[^>]*>/g, "").trim();
        const msg = text(e.body);
        if (isRollup(chat, msg)) continue;
        const id = app + "/" + chat;
        if ((read[id] || 0) >= e.time) continue;
        if (at[id] === undefined) {
            at[id] = out.length;
            out.push({ id: id, app: app, chat: chat, text: msg, count: 0, time: e.time, keys: [] });
        }
        const it = out[at[id]];
        it.count++;
        it.keys.push(e.key);
    }
    return out;
}
