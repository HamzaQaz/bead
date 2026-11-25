import QtQuick
import QtTest
import "../services/messengers.js" as M

// WhatsApp and Telegram in bead (services/messengers.js): which notifications
// are theirs (their desktop apps, or the web versions in a browser), the
// message without the browser's origin line, and the inbox grouped by chat.
TestCase {
    name: "Messengers"
    function e(app, summary, body, time, key) { return { appName: app, summary: summary, body: body, time: time || 1, key: key || time || 1 }; }

    function test_the_desktop_apps() {
        compare(M.source(e("Telegram Desktop", "Sam", "hi")), "telegram");
        compare(M.source(e("AyuGram", "Sam", "hi")), "telegram");
        compare(M.source(e("ZapZap", "Sam", "hi")), "whatsapp");
        compare(M.source(e("WhatsApp", "Sam", "hi")), "whatsapp");
    }
    function test_the_web_versions_in_a_browser() {
        compare(M.source(e("Google Chrome", "Sam", "web.whatsapp.com\n\nhi")), "whatsapp");
        compare(M.source(e("Google Chrome", "Sam", '<a href="https://web.telegram.org/">web.telegram.org</a>\n\nhi')), "telegram");
        compare(M.source(e("Firefox", "Sam", "hi\nweb.whatsapp.com")), "whatsapp");
    }
    function test_other_apps_and_sites_are_not_theirs() {
        compare(M.source(e("Google Chrome", "Sam", "mail.google.com\n\nhi")), "");
        compare(M.source(e("discord", "Sam", "hi")), "");
    }
    function test_the_origin_line_and_markup_are_taken_off() {
        compare(M.text('<a href="https://web.whatsapp.com/">web.whatsapp.com</a>\n\nsee you <b>soon</b>'), "see you soon");
        compare(M.text("hi\nweb.whatsapp.com"), "hi");
        compare(M.text("a &amp; b"), "a & b");
    }
    function test_the_inbox_groups_by_chat_newest_first() {
        const list = M.inbox([
            e("Telegram Desktop", "Sam", "third", 30),
            e("Google Chrome", "Mum", "web.whatsapp.com\n\nsecond", 20),
            e("Telegram Desktop", "Sam", "first", 10),
            e("Google Chrome", "Inbox", "mail.google.com\n\nnope", 25)
        ], {}, ["whatsapp", "telegram"]);
        compare(list.length, 2);
        compare(list[0].chat, "Sam");
        compare(list[0].app, "telegram");
        compare(list[0].count, 2);
        compare(list[0].text, "third");
        compare(list[0].keys, [30, 10]);
        compare(list[1].app, "whatsapp");
    }
    function test_read_chats_drop_out_until_something_newer() {
        const entries = [e("Telegram Desktop", "Sam", "old", 10)];
        compare(M.inbox(entries, { "telegram/Sam": 10 }, ["telegram"]).length, 0);
        compare(M.inbox([e("Telegram Desktop", "Sam", "new", 11)].concat(entries), { "telegram/Sam": 10 }, ["telegram"])[0].count, 1);
    }
    function test_only_the_apps_turned_on() {
        const entries = [e("Telegram Desktop", "Sam", "x", 10), e("WhatsApp", "Mum", "y", 9)];
        compare(M.inbox(entries, {}, ["whatsapp"]).map(i => i.app), ["whatsapp"]);
        compare(M.inbox(entries, {}, []).length, 0);
    }
    function test_counts_summaries_are_not_chats() {
        // "WhatsApp: 3 new messages" style roll-ups name no chat
        compare(M.inbox([e("Google Chrome", "WhatsApp", "web.whatsapp.com\n\n3 new messages", 5)], {}, ["whatsapp"]).length, 0);
    }
}
