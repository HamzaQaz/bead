# Island widgets

## Problem Statement
How might we let you put anything you care about on the island (a server's
state, a build, a number you check ten times a day) by filling in a form in
Settings, without writing QML, files or scripts?

## Recommended Direction
A widget builder in Settings → Widgets. You pick a template, fill in its few
fields, and watch the widget take shape in a live preview, as on the
Customise pages. Underneath, every widget is a command run on a timer, and
its output (plain text, or JSON with value, icon, colour, progress) becomes
what's shown. You never see that unless you pick the Command template.

Widgets you pin show as small chips on the resting island, beside the clock
and live activities. Every widget also has a card on a new dashboard
Widgets tab, with more detail and its button. Live activities stay as they
are: those are tasks that end, and widgets are things that stay.

The templates follow what you'd use first:

| Template | Fields | Shows |
|---|---|---|
| Server up | host or URL | up/down, response time |
| Number from a URL | URL, field (`players.online`) | the number |
| GitHub | repo; CI, PRs or release | the last CI run (with a ring while running), open PRs, the latest release |
| Toggle | on command, off command, state check | on/off; a click flips it |
| Command | a command, every N seconds | its output |

## Key Assumptions to Validate
- [x] The resting island has room for pinned chips (2026-11-25, 1080p,
      `widgets demo N` mock): clock, weather and four chips come to ~430 px,
      under a quarter of the screen, and read clearly. A playing track adds
      at most ~170 px (title capped at 190). Cap at 4 pinned chips, with "+N"
      beyond that.
- [x] A hanging command can't stall the others (2026-11-25): each widget runs
      its own process with a 5 s timeout; `sleep 30` showed "timed out" and
      was killed, while the rest kept updating. Idle CPU with many widgets is
      still unmeasured.
- [x] `gh` covers the GitHub template without a token of our own (2026-11-25):
      the CI widget read bead's real runs, and caught CI failing on v0.4.0.
- [ ] Secrets (the Home Assistant token, URLs with keys) can live in the
      keyring through `secret-tool`; gnome-keyring already runs here.

## MVP Scope
In: a `Widgets` service (runs each widget on its interval, with a timeout,
and parses text or JSON); widgets saved in `~/.config/bead/widgets.json`;
Settings → Widgets (add from a template, edit, pin to the island, reorder,
delete, live preview); pinned chips on the resting island; a dashboard
Widgets tab with cards; the five templates above.

Next: Home Assistant (an entity's state; a tap toggles lights and switches;
the token in the keyring). After that: "Keep on the island" from launcher
results and notifications, and widgets per Focus mode.

## Not Doing (and Why)
- QML plugins: full power, but it's code, and code can break the shell. The
  builder and commands cover the examples.
- Sharing or importing widgets for now: importing means running someone
  else's command. Only with a screen that shows the command and asks first.
- Scripts pushing values over IPC as the main way: live activities already do
  that for tasks, and it needs a process kept alive.
- Charts and history in the cards: a value and its state first.

## Open Questions
- How do pinned chips share the resting island with media and live
  activities: always on, or only when the island is idle?
- Does a widget that turns bad (server down, CI failed) raise a toast, or
  just change colour?
