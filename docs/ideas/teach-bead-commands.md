# Teach bead a command

## Problem Statement
How might we let anyone teach bead a new command in seconds, without opening a file?

## Recommended Direction
Custom actions already exist in `~/.config/bead/voice.json`, but only for people willing
to write JSON. Keep that file as the single store and add three ways in and out of it.

- **Capture:** after one or more voice commands, "save that as focus" (or "save the last
  three as focus") shows the steps on the island; confirming writes the action, with
  "focus" as its phrase.
- **Recipes:** a few generic actions offered as toggles in Settings.
- **Run anywhere:** every action is listed in the launcher and callable over IPC, so a
  key can be bound to it.

## Key Assumptions to Validate
- [ ] Chains get spoken as separate commands often enough to be worth saving.
      Test: count commands for a week (count only, no content).
- [ ] A saved step replays correctly later. Test: save and replay each built-in; list
      the ones that depend on state (toggles, "this window").
- [ ] The name alone is a reliable trigger. Test: saved names matched as phrases,
      without the model, including names close to built-ins.

## MVP Scope
In: a history of the last five commands; "save that as X" and "save the last N as X"
matched without the model; a preview with confirm; toggles saved as on/off; actions in
the launcher; `bead voice run <name>`; "forget X" to delete one.

Out: recipes (second slice), parameters in saved actions, editing steps by voice.

## Not Doing (and Why)
- **A visual editor:** capture plus the existing file covers it for far less UI.
- **Teach by showing ("watch this"):** unreliable to infer steps from window events.
- **Event triggers:** a real feature, but a second one; it needs its own design.
- **bead writing Hyprland keybinds:** it never edits that config; IPC lets you bind it.

## Open Questions
- Can one utterance already hold two commands? If so, the history matters less.
- Which built-ins must be refused in a saved chain (ask, undo, again)?
- Where do recipes live so they don't overwrite a person's edited file?
