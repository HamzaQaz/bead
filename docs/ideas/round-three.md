# Round three: daily tools, then learnability

## Problem Statement
How might we make bead quicker to live in every day, and easier to learn on day one?

## Recommended Direction
Daily tools first, because they pay back every day: pinned clips (pin from the
clipboard list; pins sit on top and never expire) and snooze (a "later" chip on a
pop-up or history row; it returns as a fresh pop-up).

Then learnability: a keys sheet opened from the launcher ("keys") or `bead keys`,
listing bead's own bindings from the table the installer already has; and a pass over
every panel for empty states, loading placeholders and keyboard focus.

Night light last: a Utilities tile, shown only when hyprsunset is installed, with
"from sunset" using the weather service's sunset time.

## Key Assumptions to Validate
- [ ] Pins get used. Test: after two weeks, are there more than two, and were they pasted?
- [ ] Snoozed pop-ups are welcome when they return. Test: the three intervals; note
      any that came back at a bad moment.
- [ ] A shipped keys table stays true enough. Test: compare it to a fresh install;
      check whether hl.bind accepts a description, which would let it be read live.
- [ ] hyprsunset can be driven without a restart. Test: toggle it over its IPC.

## MVP Scope
In: pin/unpin a clip, pins on top, a pins file; snooze 20 min / 1 h / tomorrow with
a "snoozed" section in the history; the keys sheet; the night-light tile.

The pass, as a checklist: notifications history, Wi-Fi, Bluetooth, timers, updates,
clipboard, launcher "no results".

Logic for pins, snooze times and the keys table written test-first.

## Not Doing (and Why)
- **Holding Super to show keys:** releasing Super already opens the launcher.
- **Listing your own Hyprland keys in plain words:** Hyprland doesn't report what they do.
- **Snoozed notifications keeping their action buttons:** the app has released them.
- **Installing hyprsunset for you:** bead doesn't install packages outside its installer.
- **Pinning secrets:** entries that look like keys or tokens can't be pinned.

## Open Questions
- Tomorrow morning means what time: 9:00, or when you first unlock?
- Should pins sync with the vault, or stay local?
