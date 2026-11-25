.pragma library
// The island shelf (services/Shelf.qml, docs/ideas/island-shelf.md): things you
// put down on the island and drag out into any app. It holds paths, never
// copies of your files. Folders stay after you drag them out (you often want
// one more than once); everything else leaves, with an undo. Pure: tests/tst_shelf.qml.

var MAX = 24;

var IMAGE = /\.(png|jpe?g|webp|gif|bmp|svg|avif|tiff?|heic)$/i;
var VIDEO = /\.(mp4|mkv|webm|mov|avi|m4v)$/i;

var _n = 0;
function _id(now) { _n = (_n + 1) % 100000; return "s" + Math.floor(now || 0).toString(36) + "-" + _n; }

function kindOf(path, isDir) {
    if (isDir) return "folder";
    if (IMAGE.test(path)) return "image";
    if (VIDEO.test(path)) return "video";
    return "file";
}

function _base(path) {
    var p = String(path).replace(/\/+$/, "");
    return p.slice(p.lastIndexOf("/") + 1) || p;
}

// file:// URLs (as a drop gives them) to paths; anything else is left out
function pathsOf(urls) {
    var out = [];
    (urls || []).forEach(function (u) {
        var s = String(u || "");
        if (s.indexOf("file://") !== 0) return;
        var p = s.slice(7);
        try { p = decodeURIComponent(p); } catch (e) {}
        if (p) out.push(p);
    });
    return out;
}

// links from a browser (an image, a PDF, a page): fetched, not file:// paths
function webOf(urls) {
    return (urls || []).map(String).filter(function (u) { return /^https?:\/\//i.test(u); });
}
// a fetched link's file name: the last part of its path, or "download"
function webName(url) {
    var p = String(url).replace(/^[a-z]+:\/\/[^\/]*/i, "").replace(/[?#].*$/, "").replace(/\/+$/, "");
    var n = p.slice(p.lastIndexOf("/") + 1);
    try { n = decodeURIComponent(n); } catch (e) {}
    n = n.replace(/[\/\0]/g, "_").replace(/^\.+/, "");
    return n && n.indexOf(".") > 0 ? n.slice(0, 120) : "download";
}

// a drag from a browser often carries the file itself (Chromium:
// application/octet-stream;name="photo.jpg") besides links to the page: that's
// what was meant. Its format and a safe name, or null
function carried(formats) {
    for (var i = 0; i < (formats || []).length; i++) {
        var m = /^application\/octet-stream;\s*name="?([^"]+)"?$/i.exec(formats[i]);
        if (!m) continue;
        var n = m[1].slice(m[1].lastIndexOf("/") + 1).replace(/[\\\0]/g, "_").replace(/^\.+/, "");
        return { format: formats[i], name: (n || "dropped").slice(0, 120) };
    }
    return null;
}
// bytes → base64 (Qt.btoa takes text, which would mangle them)
var _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function base64(buf) {
    var u = new Uint8Array(buf), out = [], i;
    for (i = 0; i + 2 < u.length; i += 3) {
        var n = (u[i] << 16) | (u[i + 1] << 8) | u[i + 2];
        out.push(_B64[n >> 18 & 63] + _B64[n >> 12 & 63] + _B64[n >> 6 & 63] + _B64[n & 63]);
    }
    var left = u.length - i;
    if (left === 1) { var a = u[i] << 16; out.push(_B64[a >> 18 & 63] + _B64[a >> 12 & 63] + "=="); }
    else if (left === 2) { var b = (u[i] << 16) | (u[i + 1] << 8); out.push(_B64[b >> 18 & 63] + _B64[b >> 12 & 63] + _B64[b >> 6 & 63] + "="); }
    return out.join("");
}

function item(path, isDir, now) {
    return { id: _id(now), kind: kindOf(path, isDir), path: path, name: _base(path), text: "", added: now || 0 };
}
function textItem(text, now) {
    var first = String(text).split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l; })[0] || "Text";
    return { id: _id(now), kind: "text", path: "", name: first.slice(0, 60), text: String(text), added: now || 0 };
}

function _same(a, b) { return a.kind === "text" ? b.kind === "text" && a.text === b.text : a.path === b.path; }

// put things down: newest first; the same thing again moves to the front
function add(items, fresh) {
    var out = (fresh || []).slice();
    (items || []).forEach(function (i) {
        if (!out.some(function (f) { return _same(f, i); })) out.push(i);
    });
    return out.slice(0, MAX);
}

// after a drag out: folders stay; anything else leaves (and can be put back)
function afterDrag(items, id) {
    var at = -1;
    for (var i = 0; i < items.length; i++) if (items[i].id === id) { at = i; break; }
    if (at < 0 || items[at].kind === "folder") return { items: items, removed: null, at: -1 };
    var out = items.slice();
    var gone = out.splice(at, 1)[0];
    return { items: out, removed: gone, at: at };
}
function putBack(items, removed, at) {
    if (!removed) return items;
    var out = items.filter(function (i) { return i.id !== removed.id; });
    out.splice(Math.max(0, Math.min(at, out.length)), 0, removed);
    return out;
}

// what an app gets when a file is dragged out of the shelf
function uriList(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/") + "\r\n";
}

// a download still being written (browsers rename it when done), or a hidden file
function isPartial(name) {
    return /^\./.test(name) || /\.(part|crdownload|tmp|download|partial|opdownload)$/i.test(name);
}
