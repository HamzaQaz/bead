# Island shelf

## Problem Statement
How might we let you put something down for a moment (a file, screenshot,
recording, download or copied image) and pick it up again in any app, without
hunting through folders or opening a file picker?

## Recommended Direction
A shelf that lives on the island. Drop anything on the island and it's held there.
A small stack chip ("📄 3") sits on the resting island while the shelf has
anything. While it isn't empty, hovering the island opens the shelf instead of the
media card, so what you put down is one move away. Drag an item into any app and it
leaves the shelf; folders stay, since you often want them more than once. A Clear
button empties it.

Things you just made come to you: after a screenshot, a recording or a finished
download, the island shows its thumbnail for a few seconds (the ClipHints moment).
Drag it straight into Discord, or tap to keep it on the shelf.

Copied images work too: apps want files, so an image copied to the clipboard is
written to a file under $XDG_RUNTIME_DIR/bead/shelf as soon as it shows on the
shelf, and that's what gets dragged. Dropped text is kept as text and dragged out
as text.

## Key Assumptions to Validate
- [x] Layer shell takes drops from apps and drags into apps (spike, 2026-11-25:
      Thunar → island, island → Discord as an attachment)
- [ ] "Ended outside bead" is a good enough sign a drag was used. Test: drag into
      Discord, onto the desktop, and cancel with Esc; compare what Qt reports.
      Removal comes with an "undo" chip on the island for a few seconds either way.
- [ ] Downloads can be caught on the final rename. Test: Helium, Firefox and a
      curl -O into ~/Downloads; ignore .part / .crdownload / .tmp.
- [ ] A copied image written on arrival drags into Discord. Test: copy an image in
      Helium, drag it from the shelf into Discord.
- [ ] Forgotten items don't make hover annoying. Test: a week of daily use; count
      how often you clear the shelf just to get the media card back.

## MVP Scope
In:
- services/Shelf.qml + shelf.js: items (path, kind, name, sticky for folders),
  add, remove, clear, undo of the last removal; logic test-first in tests/tst_shelf.qml
- Drop target on the island (resting and open)
- Stack chip on the resting island; the hover card shows the shelf while it isn't
  empty (thumbnails for images and videos, icons otherwise), with Clear
- Drag out: files leave, folders stay, "undo" for a few seconds
- The moment: a thumbnail after a screenshot (Capture), a recording (Recorder) or
  a finished download (~/Downloads watch), draggable, tap to keep
- Copied images become files; dropped text stays text
- Demo mode: the shelf shows made-up items

Out: everything under Not Doing.

## Not Doing (and Why)
- **A drag waypoint across workspaces:** dragging across workspaces mid-drag is rare.
- **A send-to strip:** a different product; an app's own drop target is already the
  "send to".
- **A shelf per workspace:** more state for little gain.
- **Keeping the shelf across restarts:** it's for the moment; copied-image files
  live in $XDG_RUNTIME_DIR and go at logout.
- **Copying or moving files:** the shelf holds paths, never copies of your files
  (except copied images, which have no file).
- **Auto-adding every screenshot/download:** the moment offers it; you keep it
  with a tap.

## Open Questions
- Should the moment replace the screenshot notification's Open/Edit buttons, or
  sit alongside them?
- Max items before the hover card scrolls? (Guess: 8 visible.)
- Drag several at once (select, then drag a bundle)?
