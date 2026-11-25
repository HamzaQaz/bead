# Discord panel

## Problem Statement
How might bead handle the everyday Discord moments (a call coming in, a DM or mention, friends hanging out in voice) without opening Discord's window?

## Recommended Direction
One Discord panel in the bar, fed by the existing `bin/bead-discord` helper (Discord's local RPC socket, the user's own app; nothing that breaks Discord's terms):

- **Call**: an incoming DM or group call rings on the island with Answer / Leave. Answering joins it (`SELECT_VOICE_CHANNEL`); while in a call, the panel shows who's there with Leave.
- **Inbox**: DMs *and* @mentions (today server notifications are dropped). Each item opens its channel in Discord (`discord://-/channels/<guild|@me>/<channel>`) and shows the communication workspace. RPC can't send messages, so this has no reply box.
- **Voice now**: voice channels in your servers that have people in them, with Join. Polled only while the panel is open.
- **Presence (opt-in)**: bead sets your Discord activity to the music playing, or the project you're working on.

The helper's logic lives in pure functions tested with Python's `unittest` (no dependencies), written test-first and run by `make test`.

## Key Assumptions to Validate
- [ ] Discord announces an incoming call over RPC (a `NOTIFICATION_CREATE`, or a `VOICE_STATE` on the DM channel). Test with a real call.
- [ ] `SELECT_VOICE_CHANNEL` joins a ringing DM call (answers it)
- [ ] `GET_GUILDS` / `GET_CHANNELS` / `GET_CHANNEL` (voice_states) work with the current scopes and stay inside rate limits when polled only while the panel is open
- [ ] `SET_ACTIVITY` from the user's own app shows on their profile

## MVP Scope
In: Call, Inbox (DMs + mentions), Voice now, Presence (music, project; both off by default), Settings toggles, tests for every helper function.

## Not Doing (and Why)
- Reading or sending chat through the user's token: breaks Discord's terms, ban risk
- A bot account: more setup, servers only; not needed for "helpful"
- Friends' online status: Discord's RPC doesn't expose it
- Declining a call: RPC has no command for it; let it ring out, or open Discord
- Screenshare / stream controls: not asked for

## Decided (2026-11-24)
- RPC only. Calls: just answer and leave. Presence: music and project, opt-in.
