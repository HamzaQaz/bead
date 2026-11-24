# Dashboard keys, round two (plus four UI pieces)

## Problem Statement
How might we put the last dashboard controls on the keyboard, make live tests
unable to type into other windows, and give bead's everyday surfaces more life?

## Recommended Direction
**Keys.** The timer dial becomes a stop (Left/Right nudge it, Return starts).
The calendar gains a selected day and paging: arrows move the day, `[` / `]`
change month, `t` goes back to today, and scrolling over it pages months for the
mouse. A `dashboard key <Name>` IPC sends a key through the same handler real
keys use, so live tests need no `wtype`. While the ring shows, a faint hint
strip lists the keys that work on the focused control.

**UI.** Notifications from one app stack into one card with a count that fans
open on click. The island's edge glows in the album art's main colour while
music plays. The Weather tab gets light motion matched to the conditions. On
unlock the lock clock flies to the bar clock while the blur clears.

## Key Assumptions to Validate
- [ ] IPC keys take the same path as real ones (one `handle(name)` function)
- [ ] `[` `]` `t` are ignored while a text field has focus
- [ ] The cover's main colour can be sampled cheaply (shrink in a shader, not in JS)
- [ ] Weather motion stays light on the GPU and pauses when the tab is hidden
- [ ] The lock and bar clocks can meet across layers (or need a stand-in clock)

## MVP Scope
In: dial stop, calendar (select, page, today), `dashboard key`, hint strip,
notification stacks, album glow, weather motion, unlock hand-off. Pure logic in
tested JS: month grid, stacking, hint text.

## Not Doing (and Why)
- Calendar day details: there is no per-day history yet
- Type-to-filter and remembering the last control: not picked; later
- Guarded `wtype`: IPC keys can't leak at all
- Bar panels by keyboard: dashboard only this round
- Desktop-wide weather, conversation-level stacks: scope

## Open Questions
- None blocking.
