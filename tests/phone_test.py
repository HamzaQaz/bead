#!/usr/bin/env python3
"""The pure parts of bin/bead-phone: python3 tests/phone_test.py (make test)."""
import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("bead_phone", os.path.join(HERE, "..", "bin", "bead-phone"))
_spec = importlib.util.spec_from_loader("bead_phone", _loader)
bp = importlib.util.module_from_spec(_spec)
_loader.exec_module(bp)


def props(**kw):
    """What busctl --json=short prints for Properties.GetAll."""
    t = {bool: "b", int: "i", str: "s", list: "as"}
    return {"type": "a{sv}", "data": [{k: {"type": t[type(v)], "data": v} for k, v in kw.items()}]}


PHONE = dict(name="Pixel", type="phone", isReachable=True, isPaired=True, pairState=3,
             supportedPlugins=["kdeconnect_battery", "kdeconnect_findmyphone", "kdeconnect_share", "kdeconnect_ping"])


class Unwrap(unittest.TestCase):
    def test_a_reply_is_its_values(self):
        self.assertEqual(bp.reply({"type": "as", "data": [["a", "b"]]}), ["a", "b"])

    def test_properties_become_a_plain_dict(self):
        self.assertEqual(bp.reply(props(name="Pixel", isPaired=True)), {"name": "Pixel", "isPaired": True})

    def test_nothing_is_nothing(self):
        self.assertIsNone(bp.reply(None))
        self.assertIsNone(bp.reply({"type": "as", "data": []}))


class Device(unittest.TestCase):
    def test_a_paired_phone(self):
        d = bp.device("abc", bp.reply(props(**PHONE)), {"charge": 81, "isCharging": True})
        self.assertEqual(d["id"], "abc")
        self.assertEqual(d["name"], "Pixel")
        self.assertEqual(d["kind"], "phone")
        self.assertTrue(d["reachable"])
        self.assertEqual(d["pair"], "paired")
        self.assertEqual(d["battery"], 81)
        self.assertTrue(d["charging"])
        self.assertEqual(d["can"], ["battery", "ping", "ring", "share"])

    def test_pairing_both_ways(self):
        mine = bp.device("a", bp.reply(props(**dict(PHONE, isPaired=False, pairState=1))), None)
        theirs = bp.device("a", bp.reply(props(**dict(PHONE, isPaired=False, pairState=2))), None)
        none = bp.device("a", bp.reply(props(**dict(PHONE, isPaired=False, pairState=0))), None)
        self.assertEqual(mine["pair"], "requested")
        self.assertEqual(theirs["pair"], "incoming")
        self.assertEqual(none["pair"], "none")

    def test_older_daemons_say_it_with_flags(self):
        p = dict(PHONE, isPaired=False, isPairRequestedByPeer=True)
        del p["pairState"]
        self.assertEqual(bp.device("a", bp.reply(props(**p)), None)["pair"], "incoming")

    def test_no_battery_reported_is_none_not_zero(self):
        d = bp.device("a", bp.reply(props(**PHONE)), None)
        self.assertIsNone(d["battery"])
        self.assertEqual(bp.device("a", bp.reply(props(**PHONE)), {"charge": -1})["battery"], None)

    def test_an_unpaired_phone_can_do_nothing_yet(self):
        d = bp.device("a", bp.reply(props(**dict(PHONE, isPaired=False, pairState=0))), None)
        self.assertEqual(d["can"], [])

    def test_a_missing_name_falls_back(self):
        d = bp.device("a", {}, None)
        self.assertEqual(d["name"], "Phone")
        self.assertEqual(d["kind"], "phone")


class Order(unittest.TestCase):
    def test_paired_and_near_first_then_by_name(self):
        ds = [
            {"id": "1", "name": "Tablet", "pair": "none", "reachable": True},
            {"id": "2", "name": "Old", "pair": "paired", "reachable": False},
            {"id": "3", "name": "Pixel", "pair": "paired", "reachable": True},
            {"id": "4", "name": "Asks", "pair": "incoming", "reachable": True},
        ]
        self.assertEqual([d["id"] for d in bp.ordered(ds)], ["3", "4", "2", "1"])


class Commands(unittest.TestCase):
    def test_commands_become_dbus_calls(self):
        self.assertEqual(bp.call_for("ring abc"), ("/modules/kdeconnect/devices/abc/findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring", "", []))
        self.assertEqual(bp.call_for("pair abc"), ("/modules/kdeconnect/devices/abc", "org.kde.kdeconnect.device", "requestPairing", "", []))
        self.assertEqual(bp.call_for("share abc https://x.org/a b"), ("/modules/kdeconnect/devices/abc/share", "org.kde.kdeconnect.device.share", "shareUrl", "s", ["https://x.org/a b"]))

    def test_a_file_is_shared_as_a_file_url(self):
        self.assertEqual(bp.call_for("share abc /home/me/My Shot.png")[4], ["file:///home/me/My%20Shot.png"])

    def test_bad_commands_and_ids_are_refused(self):
        self.assertIsNone(bp.call_for("ring"))
        self.assertIsNone(bp.call_for("ring ../daemon"))
        self.assertIsNone(bp.call_for("explode abc"))
        self.assertIsNone(bp.call_for("share abc"))


class Firewall(unittest.TestCase):
    def test_ufw_with_both_protocols_open_is_open(self):
        rules = ("-A ufw-user-input -p udp -m multiport --dports 1714:1764 -j ACCEPT\n"
                 "-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT\n")
        self.assertTrue(bp.ufw_open(rules))

    def test_an_app_profile_rule_counts(self):
        rules = ("-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT -m comment --comment 'dapp_KDE%20Connect'\n"
                 "-A ufw-user-input -p udp -m multiport --dports 1714:1764 -j ACCEPT -m comment --comment 'dapp_KDE%20Connect'\n")
        self.assertTrue(bp.ufw_open(rules))

    def test_only_one_protocol_or_a_deny_is_closed(self):
        self.assertFalse(bp.ufw_open("-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT\n"))
        self.assertFalse(bp.ufw_open("-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j DROP\n"
                                     "-A ufw-user-input -p udp -m multiport --dports 1714:1764 -j DROP\n"))
        self.assertFalse(bp.ufw_open(""))


if __name__ == "__main__":
    unittest.main()
