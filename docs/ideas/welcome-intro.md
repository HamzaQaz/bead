# Welcome intro: the bead becomes the shell

## Problem Statement
How might we make bead's first 2–3 seconds show what it is — a shell that
grows from one bead — instead of a generic splash?

## Recommended Direction
Whole screen, about 2.6 s, one object, any key skips to the card:

1. **0–0.75 s** On black, one bead in the accent colour falls to the top
   centre, where the island lives, and lands with a small squash.
2. **0.75–1.3 s** It stretches into the island's pill. Light runs out of it
   both ways along the top edge, down the sides and along the bottom: the
   frame being drawn, thicker on the left where the bar is.
3. **1.3–1.9 s** The black lifts; the traced frame settles into the real
   frame's colour and gives way to it.
4. **1.9–2.6 s** The pill blooms down into the welcome card; "bead." comes
   into focus on it and step one's words follow.

The island is usually tucked at rest, so the intro doesn't hand off to the
live island: the drawn pill becomes the card instead. The frame's geometry
(Theme.frameThickness, a 40 px bar on the left) matches the real one, so the
traced frame lies exactly on it.

## Key Assumptions to Validate
- [ ] The traced frame lines up with the real one on every monitor scale —
      look at the hand-off frame by frame
- [ ] A rect changing size and corner radius together reads as one object
      blooming at 165 Hz — watch `bead welcome` live
- [ ] The landing squash reads as weight, not cartoon — keep it to ~15%

## MVP Scope
The four beats above in Welcome.qml (no new shader); the old intro (dot
field, aurora, ripples, shine) is removed from the opening; the backdrop
shader stays for between steps.

## Not Doing (and Why)
- Sound — a first-run chime surprises people
- The goo shader on landing — a geometric squash is enough for v1
- Handing off to the live island — it's usually tucked; the card is the
  natural end
- Every monitor — plays on the welcome's monitor; others are untouched

## Open Questions
- Accent colour or wallpaper colour for the bead? Accent: the wallpaper
  isn't chosen until step two.
