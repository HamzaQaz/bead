#!/usr/bin/env python3
"""The pure parts of bin/bead-discord: python3 tests/discord_test.py (make test)."""
import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("bead_discord", os.path.join(HERE, "..", "bin", "bead-discord"))
_spec = importlib.util.spec_from_loader("bead_discord", _loader)
bd = importlib.util.module_from_spec(_spec)
_loader.exec_module(bd)

ME = "100"


def note(author_id="200", msg_type=0, title="Ada", content="hi"):
    return {"channel_id": "9", "title": title, "body": content,
            "message": {"type": msg_type, "content": content, "author": {"id": author_id, "username": "ada"}}}


class NoteKind(unittest.TestCase):
    def test_a_direct_message_is_a_dm(self):
        self.assertEqual(bd.note_kind(note(), 1, ME), "dm")

    def test_a_group_dm_is_a_dm(self):
        self.assertEqual(bd.note_kind(note(), 3, ME), "dm")

    def test_a_server_channel_notification_is_a_mention(self):
        self.assertEqual(bd.note_kind(note(title="Ada (#general, Some Server)"), 0, ME), "mention")

    def test_a_call_message_is_a_call(self):
        self.assertEqual(bd.note_kind(note(msg_type=3, content=""), 1, ME), "call")

    def test_your_own_messages_are_ignored(self):
        self.assertIsNone(bd.note_kind(note(author_id=ME), 1, ME))

    def test_unknown_channel_type_falls_back_to_the_title(self):
        self.assertEqual(bd.note_kind(note(title="Ada (#general, Some Server)"), None, ME), "mention")
        self.assertEqual(bd.note_kind(note(title="Ada"), None, ME), "dm")


class ChannelLink(unittest.TestCase):
    def test_a_dm_opens_under_me(self):
        self.assertEqual(bd.channel_link(None, "9"), "discord://-/channels/@me/9")

    def test_a_server_channel_opens_under_its_server(self):
        self.assertEqual(bd.channel_link("5", "9"), "discord://-/channels/5/9")


class Inbox(unittest.TestCase):
    def item(self, channel="9", kind="dm", text="hi"):
        return {"channel": channel, "guild": None, "kind": kind, "name": "Ada", "avatar": "a.png", "text": text}

    def test_messages_in_one_channel_merge_and_count(self):
        box = bd.inbox_add({}, self.item(text="one"), now=1)
        box = bd.inbox_add(box, self.item(text="two"), now=2)
        view = bd.inbox_view(box)
        self.assertEqual(len(view), 1)
        self.assertEqual(view[0]["count"], 2)
        self.assertEqual(view[0]["text"], "two")

    def test_newest_first(self):
        box = bd.inbox_add({}, self.item(channel="1"), now=1)
        box = bd.inbox_add(box, self.item(channel="2"), now=2)
        self.assertEqual([i["channel"] for i in bd.inbox_view(box)], ["2", "1"])

    def test_the_oldest_drop_past_the_limit(self):
        box = {}
        for i in range(5):
            box = bd.inbox_add(box, self.item(channel=str(i)), now=i, limit=3)
        self.assertEqual([i["channel"] for i in bd.inbox_view(box)], ["4", "3", "2"])

    def test_adding_leaves_the_old_inbox_alone(self):
        box = bd.inbox_add({}, self.item(), now=1)
        bd.inbox_add(box, self.item(), now=2)
        self.assertEqual(bd.inbox_view(box)[0]["count"], 1)

    def test_each_item_carries_its_link(self):
        box = bd.inbox_add({}, dict(self.item(kind="mention"), guild="5"), now=1)
        self.assertEqual(bd.inbox_view(box)[0]["link"], "discord://-/channels/5/9")


class Presence(unittest.TestCase):
    track = {"title": "Wow.", "artist": "Post Malone"}

    def test_off_publishes_nothing(self):
        self.assertIsNone(bd.presence({"music": False, "project": False}, self.track, "bead"))

    def test_music_while_playing(self):
        a = bd.presence({"music": True, "project": True}, self.track, "bead")
        self.assertEqual(a["details"], "Listening to Wow.")
        self.assertEqual(a["state"], "by Post Malone")

    def test_project_when_nothing_plays(self):
        a = bd.presence({"music": True, "project": True}, None, "bead")
        self.assertEqual(a["details"], "Working on bead")
        self.assertNotIn("state", a)

    def test_music_allowed_but_project_not(self):
        self.assertIsNone(bd.presence({"music": True, "project": False}, None, "bead"))

    def test_long_text_fits_discords_limit(self):
        a = bd.presence({"music": True}, {"title": "x" * 300, "artist": ""}, "")
        self.assertLessEqual(len(a["details"]), 128)
        self.assertNotIn("state", a)


class VoiceNow(unittest.TestCase):
    def vs(self, uid, name):
        return {"nick": None, "user": {"id": uid, "username": name, "global_name": None, "avatar": None}}

    def ch(self, cid, people, guild="Server"):
        return {"id": cid, "name": "Lounge " + cid, "guild_id": "5", "guild": guild, "voice_states": people}

    def test_busiest_first_and_empty_left_out(self):
        out = bd.voice_now([self.ch("1", [self.vs("2", "a")]), self.ch("2", []),
                            self.ch("3", [self.vs("2", "a"), self.vs("3", "b")])], ME, None)
        self.assertEqual([c["id"] for c in out], ["3", "1"])
        self.assertEqual(out[0]["count"], 2)
        self.assertEqual(out[0]["people"][0]["name"], "a")

    def test_the_call_youre_in_is_left_out(self):
        out = bd.voice_now([self.ch("1", [self.vs("2", "a")])], ME, "1")
        self.assertEqual(out, [])

    def test_a_channel_with_only_you_is_left_out(self):
        out = bd.voice_now([self.ch("1", [self.vs(ME, "me")])], ME, None)
        self.assertEqual(out, [])


class PickGuilds(unittest.TestCase):
    def test_pinned_then_recent_without_repeats(self):
        self.assertEqual(bd.pick_guilds(["a", "b", "c"], ["b", "z"], limit=4), ["b", "z", "a", "c"])

    def test_capped(self):
        self.assertEqual(bd.pick_guilds([str(i) for i in range(20)], [], limit=8), [str(i) for i in range(8)])

    def test_remember_puts_a_server_first(self):
        self.assertEqual(bd.remember_guild(["a", "b"], "b"), ["b", "a"])
        self.assertEqual(bd.remember_guild(["a"] * 0, "x"), ["x"])
        self.assertEqual(len(bd.remember_guild([str(i) for i in range(30)], "new")), 20)


class ParseCommand(unittest.TestCase):
    def test_a_bare_command(self):
        self.assertEqual(bd.parse_command("leave\n"), ("leave", ""))

    def test_a_command_with_an_argument(self):
        self.assertEqual(bd.parse_command("join 123\n"), ("join", "123"))

    def test_json_arguments_keep_their_spaces(self):
        self.assertEqual(bd.parse_command('presence {"music": true}'), ("presence", '{"music": true}'))

    def test_blank_lines_are_nothing(self):
        self.assertEqual(bd.parse_command("  \n"), ("", ""))


if __name__ == "__main__":
    unittest.main(verbosity=1)
