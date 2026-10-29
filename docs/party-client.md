# Party player beta

Loreforge 0.2.0-beta adds invitations, joining, clickable questions,
reveals, streaks, shared standings and completed-match history. The full flow has not yet
been checked through a complete match in WoW. The existing 0.1.1-beta probe
proved only the underlying bidirectional Retail Party message exchange.

The first supported context is a Retail home Party outside instances, combat
and chat restrictions. Raid, Instance, Guild and Forever retain the ordinary
chat game. Their addon player UI needs separate transport proof.

## Host and player flow

The host opens `/lf`, configures Party output and clicks **Open lobby**.
That deliberate action sends invitations; opening the setup window alone
remains private. Party members with the new build can choose **Join quiz** or
**Decline**. The host sees the joined count and clicks **Start game** when
ready. **Close lobby** cancels an invitation without starting. A player can decline the addon UI and still answer in Party chat.

The ready check uses a separate **I'm ready** action. Joining does not mark a
player ready. Joining closes once question announcements start. The host can
continue without every player checking in, matching the existing optional
ready-check rules.

Joined players get the current question with four wrapped, clickable choices.
The first click shows **Sending...**. Only the host's receipt changes that to
**Locked**. A missing receipt offers a retry of the same choice or Party-chat
fallback. A chat answer winning the race stays authoritative; a later click
cannot replace it. Correct answers, streaks and party scores appear after
reveal. Tied scores share rank and wins, and chat-only players stay in the
same game engine and standings.

Hide leaves the player joined. The compact restore button, `/lf play`, the
main `/lf` action or minimap left-click restores the match. `/lf host` opens
the host controls explicitly. **Leave** or `/lf leave` ends UI participation
without retracting an answer or score. Settings > Party player can disable
invitations. The player window scrolls long content while keeping actions
reachable, and supports a clamped scale.

## Timing and failure behaviour

`Game.lua` remains the only scoring and answer-acceptance engine. After the
last question chat echo, joined clients receive the question in a disabled
presentation state. They acknowledge complete, validated assembly. The host
waits up to 12 seconds, then sends an explicit **Answers open** chat line and
opens one host-owned answer deadline after that line is confirmed. Missing
clients get a chat-fallback notice. Reading time and message latency are not
identical across clients; displayed client timers are estimates and the host
decides whether an answer is in time.

Pause/restart changes the attempt number. Old choices and acknowledgements
cannot unlock or score a new attempt. Combat, instances and restrictions stop
native sends and disable the player interface. Roster changes use the host's
existing pause policy; departed members cannot submit or retrieve results.
A host reload ends active play. A participant reload requests the current
state or a retained completed result; loss of the host is shown explicitly.
An idle lobby expires after ten minutes.

## Protocol and bounds

`Transport.lua` now creates independent instances. The unchanged probe defaults
use `LoreforgeP2`; the Party bus uses `LoreforgeM1`, 64 wire attempts per ten
seconds and 128 attempted receives per ten seconds. It also limits each
roster sender to 64 frames per ten seconds, with at most 48 frames awaiting
decoding. Each encoded native packet still fits 255 bytes and retains the
small compressed-input cap. Native send guards check the active context and
generation on every CTL attempt, including retries.

`Codec.lua` parses typed length-prefixed values without evaluating Lua. It
limits messages to 32 KiB, strings to 4 KiB, nesting to eight and parsed values
to 8,192. `PartyBus.lua` splits into 160-byte fragments with declared size and
checksum; at most 205 fragments and sixteen concurrent assemblies, with two bulk and
two small-message slots per sender, and 64 KiB of incomplete data. Duplicate fragments are harmless, conflicting
ones discard the assembly, and superseded transfers send cancellation frames.
Packets expire after 90 seconds and have at most two full retries. Outgoing
packets are capped at twelve; transport receipts and answer/control messages
are scheduled ahead of bulk results.

Every sender resolves against the current Party roster. Session, selected
host, question and attempt bind subsequent actions. Snapshots use increasing
revisions and an explicit field allowlist; they never contain future questions
or the correct answer before reveal. Recipient fields select the UI that
handles a message. Party broadcasts are not confidential: other addons in the
group can read the traffic. A checksum detects corruption, not a dishonest host.

From 0.3.0-beta, a `between` snapshot can also carry `hostPaced` (boolean) and,
with auto-advance, `nextIn` (milliseconds until the next question, 0 to
120000). Both are optional: 0.2.0-beta clients ignore them, and 0.3.0-beta
clients reject a snapshot only if a present field is malformed.

## Saved results

Only `Game:RecordResults`, after all final chat output is confirmed, can publish
a completed result. Aborted games never create completed history. Host and
joined clients retain the same canonical settings, final scores and per-round
summaries under a unique host/session ID. Duplicate delivery acknowledges the
existing entry; conflicting content is rejected. Client receipts confirm
assignment to SavedVariables, not a proven disk flush.

`/lf history` opens the History tab, which lists hosted games and the twenty most recent Party games on that client.
Open an entry for final standings and per-round scores. Received matches are
separate from legacy player-record aggregates, so duplicate delivery cannot
increment those counters. Reset settings preserves both record types. The host
retains the prior consenting-recipient set for catch-up; merely knowing a match ID
does not authorise retrieving it. Up to twenty pending, previously consented
match IDs survive reload and moving to a newer lobby; delayed finals can still
be stored without replacing the current player window.

## Verification

The automated suites include separate real-library host/player environments
and a chat-only participant. They cover invitation/consent, readiness, complete
question assembly, presentation timeout, answer receipts and chat/click races,
reveals, streaks, ties, identical results, duplicate/conflicting finals,
participant reload, aborted final output, pause/restart, restrictions, bounded
fragment floods and expiry. Claude implemented and tested the front end in an
isolated worktree; integration uses the agreed model/action contract.

Before claiming the full flow is verified in game, run the full Party checklist in
[client checks](client-checks.md) with two addon players and a chat-only player.
The new invitation, rendering, full game timing and result persistence remain
unverified in WoW until that test is completed.

## Independent review follow-up

Astra checked the architecture and presentation/history boundaries. Claude
implemented the front end in an isolated worktree and then supplied scrolling
and round-history views. Separate Claude diff reviews identified reliability
issues fixed before handoff: idle-session heartbeats, control-message capacity,
recipient-specific receipts, restored membership, cancelled invitations,
non-repeating lock receipts, equal-revision presentation recovery and result
schema checks. Live history browsing retains a compact match return prompt.
Full redraws are limited to state changes and a one-second layout refresh;
the visible timer updates independently. The fixed roster/scoring rules and
conservative restriction pause are retained deliberately.

Release follow-up checks also cover recovery when the answer-opening packet is
lost, using the host's periodic accepting-state update. Fragment positions
advance only after CTL confirms an actual send; rejected frames have bounded
retries. Replacing a frame already queued in CTL cancels its partial transfer
explicitly. Invitations respect Decline for the session; the host's reminder
button invites new arrivals, and stale unanswered invitations expire.
