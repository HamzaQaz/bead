# Question toasts that answer in place

## Problem Statement
How might we answer Claude Code's questions from bead's toast without the
desktop jumping to the Claude terminal, and go there only when I ask?

## Recommended Direction
Keep the question in both places (toast and terminal), as now. Change how a
pick reaches the terminal: send the keys to the Claude terminal's window with
Hyprland's `send_shortcut` dispatcher (by pid) instead of focusing it and
typing with `wtype`. If Hyprland refuses the first key (a probe Down, then
Up), it uses the old focus-and-type path from the start. Retyping after a
partial send could double an answer, so it never does that. After sending, the
hook waits up to 4 s for this question's result in the transcript
(`settled`). If the result never shows, it focuses the terminal so you can see
where it stopped.

The toast gets an "Open terminal" button. That's the only thing that switches.
Clicking the body no longer does. Free-text answers ride the same key path:
move to "Type something", send the characters, then Enter. Free text is
offered on single-pick questions only. Text with characters outside a US
layout (é, emoji) uses the focus-and-type fallback.

## Key Assumptions to Validate
- [x] `send_shortcut` reaches an unfocused kitty (2026-11-25, on a hidden
      special workspace): Down, Return and `x` arrived as `ESC [ B`, `\r`,
      `x`. Focus never moved.
- [x] The Lua-config form on 0.57.2:
      `hl.dsp.send_shortcut({ mods = "", key = "Down", window = "pid:N" })`.
- [x] Free-text characters arrive. `SHIFT`+`a`, `space`, `SHIFT`+`slash`
      and `1` gave `A ?1`. Keys are xkb names, with shift for capitals and
      symbols.
- [x] The hook end to end (2026-11-25, stub glint answering `[[1],"Hi?"]`,
      a hidden recorder window as the terminal): exactly the expected 21
      bytes, focus never moved, and it saw the answer land.
- [ ] Claude's own prompt acts on the sent keys (the bytes are identical, so
      this is likely). Test with a real question in a background terminal.
- [ ] Number keys still don't select in Claude's prompt. If they do now, use
      them instead of counting Downs.

## MVP Scope
In: send_shortcut delivery with the transcript-checked fallback, an "Open
terminal" button on question toasts, free text in `glint ask`, and a shorter
timeout (~120 s instead of 280 s, since the terminal has the question anyway).

Out: holding the question, kitty remote control, and a new layout for several
questions (keep it, and fix only what testing shows is broken).

## Not Doing (and Why)
- Holding the question and returning `answers` through `updatedInput`: the
  terminal should keep showing it. Plan B if key delivery turns out flaky.
- kitty `@ send-key`: it needs the kitty config changed and only works in
  kitty. Hyprland's dispatcher works with any terminal.
- Typing into a window it can't confirm is Claude's: the fallback still
  checks the focused pid, as now.

## Open Questions
- After typing free text with no focus, how does the hook know it landed?
  It sees the same `settled` result in the transcript, so this is likely fine.
- Does Permission (Allow/Deny) need the same "Open terminal" button? It
  already answers without switching, through the hook's JSON reply.
