# Phone link

**Status: slice 1 built** (2026-11-25): `bin/bead-phone` + `services/Phone.qml`, Settings → Phone (pair, unpair, firewall check), the phone's battery in the bar's Devices panel, "Ring my phone" in the launcher, a strand part and doctor checks. Not yet tried with a real phone: pair the iPhone next (ufw already allows 1714–1764).

## Problem Statement
How might we make your phone feel like part of the desktop (its
notifications, calls, battery and files coming through bead's island) without
opening a separate app?

## Recommended Direction
Build on KDE Connect as a built-in part of bead: strand installs it with
bead (not an optional part), the package depends on it, and the installer
opens ports 1714–1764 when ufw or firewalld is running (it already has your
password for the install). It already speaks to Android and iPhone, and its daemon posts phone
notifications as ordinary desktop notifications, so bead's pop-ups and
history pick those up with no work. bead adds what the daemon doesn't show
well outside Plasma. A small helper (`bin/bead-phone`, like `bead-discord`)
watches the daemon over D-Bus and reports to a `Phone` service, since
Quickshell has no general D-Bus access from QML.

Slices follow what can be tested now, which is an iPhone. KDE Connect on iOS
does battery, ring (Find my device), files, links and text both ways,
clipboard sync and run-commands. It has no notifications, calls or SMS,
because iOS doesn't let it.

Slice 1 (works on both phones): a Settings → Phone page to pair and see the
connection, with the firewall check (KDE Connect needs ports 1714–1764, and a
closed firewall makes pairing fail silently). The phone's battery shows on
the dashboard, and the launcher gets "Ring my phone".

Slice 2 (both phones): files and links. Drop a file on the island, or use
"Send to phone" in the launcher for the current link. A photo or link from
the phone arrives as a toast with Open and Show in folder. The phone becomes a
remote for bead, with Focus modes, lock and wallpaper as KDE Connect
run-commands.

Slice 3 (Android, when one is available to test): incoming calls take the
island like the Discord call activity does (caller, Mute ringer, music
pauses and resumes). Phone notifications get bead's inline Reply. bead shows
only what the paired device supports, so iPhone users simply never see these.

## Key Assumptions to Validate
- [ ] (Android, slice 3) Phone notifications arrive through bead with the phone app's name and
      icon, not as a generic "KDE Connect". Test: pair, get a message.
- [ ] (Android, slice 3) KDE Connect's Reply action works outside Plasma. If not, replies go
      through the SMS / notification-reply plugins over D-Bus.
- [ ] A helper can follow the daemon's D-Bus signals (devices, battery, calls)
      reliably: `busctl --user monitor org.kde.kdeconnect` or `gdbus monitor`.
- [ ] (Android, slice 3) Call events (ringing, talking, ended) carry the caller's name or number.
- [ ] The firewall check can tell "blocked" from "phone not on this network".

- [ ] The iOS app reports battery and answers "ring" while it's in the
      background (iOS suspends apps, so this may only work with it open).

## MVP Scope
In: KDE Connect installed with bead (strand, PKGBUILD depends, firewall
ports opened during install); `bead-phone` helper and `Phone`
service; Settings → Phone (pair, unpair, status, firewall check); battery on
the dashboard; "Ring my phone" in the launcher; `bead doctor` knows about it.

Out of the first slice: files and links and phone-as-remote (slice 2), calls
and replies (slice 3, Android), clipboard history markers.

## Not Doing (and Why)
- Our own phone app or protocol: KDE Connect already is that, on both phones.
- iPhone-specific features: bead follows what the device reports.
- Mirroring the phone screen: scrcpy is its own world.
- SMS conversation threads in bead: KDE Connect's SMS app does that.
- Valent support: one backend first, and KDE Connect has every feature.

## Open Questions
- Where does the phone battery live: the bar's devices panel, the dashboard,
  or both?
- When a call comes in while Focus mode's Do Not Disturb is on, does the
  island still show it? (Probably yes, like urgent notifications.)
