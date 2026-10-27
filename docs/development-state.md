# Development state

Loreforge `0.1.0-beta` is the first public release, published as a CurseForge
beta for Retail and WoW Forever. It vendors a committed HammerCore pin, and
`tools/check.py` verifies that copy.

Automated checks cover Lua 5.1 syntax, the game rules, both TOCs, all four
output channels, automatic and host-paced games, echo gating, ready checks,
pauses, Game Master participation, records and the hidden `/lf probe`
transport test. HammerCore's checks confirm every one of the 1,000 decoded
questions matches its canonical source. Shipped question files are lightly
obfuscated; that deters casual browsing, not a determined reader.

Chat API and macro permissions, real chat events, secure-button behaviour,
rendering and timing are not proved in either game client. Work through
[the client checklist](client-checks.md) on each client before calling a
build verified in game.

The automatic sender uses `InChatMessagingLockdown()` plus combat and activity
checks, then confirms each line by its chat echo. The outgoing-addon realm
flag is not treated as a chat permission gate. Sources:
[Blizzard API documentation mirror](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua),
[Campkeeper author beta report](https://www.curseforge.com/wow/addons/campkeeper/files/9129067/additional-files).
Forever unit names use the full name independently of realm:
[AllTheThings client API report](https://github.com/ATTWoWAddon/AllTheThings/issues/2630).

## Player UI transport probe

`Probe.lua` adds a hidden `/lf probe` command for the first proof step in the
[player UI design](player-ui-design-review.md). It doesn't change the game. The
Game Master's client sends a hello, a multi-message UTF-8 question with length
and checksum, and a lock acknowledgement for each answer it gets. A listener
has to opt in with `/lf probe listen`, answers each nonce once on the channel
it arrived on, and only accepts a lock addressed to itself. Traffic is capped
at 24 sends per run or listen window, and the log keeps 300 lines and the last
10 run summaries in `LoreforgeDB.probe`. `tests/test_probe.lua` covers the
protocol; real delivery needs the two-client run in check 15 of
[the client checklist](client-checks.md).
