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

The 0.1.1-beta probe uses ChatThrottleLib and LibDeflate with a new wire
prefix. Both test players need this build. AceComm is excluded because its
licence raises a GPLv3 compatibility issue. See [transport](transport.md) for
source pins, bounds, cancellation, test coverage and the remaining client
proof. The 0.2.0-beta Party player implementation and its verification boundary
are described in [Party client](party-client.md).

Claude independently reviewed the transport diff. Follow-up fixes filter
self-echoes before decoding, stop with a reason on rejected submissions, report
pending cancellation and context changes, handle boolean/enum prefix results,
and preserve upstream files through the packager's `plain-copy` setting.
The fixed wire budget, strict deadline and context cancellation remain
deliberate limits; an incomplete run must remain incomplete. A shared library
fork that falsely retains version 32 cannot be authenticated by a version
check and still needs client testing.

The 0.1.1-beta release review also covered asynchronous native-send failures
and enqueue errors. Both now stop or disable the probe explicitly, with
regression coverage. The receive budget counts attempted decodes, including
invalid input, to bound work from untrusted channel traffic. Exhausting that
budget can make a run incomplete; it isn't a transport authentication scheme.
The strict retry budget, deadline and context cancellation remain deliberate.

## Party player beta, 2026-10-29

The new Party client is packaged in 0.2.0-beta, with Claude's front end and the
host-authoritative session/history integration. All nine Lua suites, Lua 5.1
syntax, both TOCs and the vendor checks pass. Independent review follow-ups
and the complete in-game acceptance sequence are in [Party client](party-client.md).
The beta is intended for the full-game acceptance test; local client staging
is separate from CurseForge publication.
Only the earlier 0.1.1-beta transport probe has real paired-client evidence;
the new full-game flow still needs that test.
