# Party player beta

Loreforge 0.2.0-beta adds invitations, joining, clickable questions,
reveals, streaks, shared standings and completed-match history. The full flow has not yet
been checked through a complete match in WoW. The existing 0.1.1-beta probe
proved only the underlying bidirectional Retail Party message exchange.

The beta permits a Retail home Party in the open world or a dungeon when
combat, activity restrictions and chat lockdown are inactive. An owner-supplied 0.3.1-beta probe log on 2026-10-30 confirms a full
bidirectional exchange inside a premade dungeon Party in 4.97 seconds.
That proves the probe transport for the reported context; the full player UI
and completed-match flow still need an in-game check. Raid, Instance, Guild and Forever retain the ordinary
chat game. Their addon player UI needs separate transport proof.

## Host and player flow

The host opens `/lf`, configures Party output and clicks **Open lobby**.
That deliberate action sends invitations; opening the setup window alone
remains private. Party members with the new build can choose **Join quiz** or
**Decline**. Invitations appear above the Loreforge main window and print a
chat notice. `/lf` reopens an unanswered invitation. The host sees the joined count and clicks **Start game** when
ready. **Close lobby** cancels an invitation without starting. A player can decline the addon UI and still answer in Party chat.

Setup exposes **Countdown before starting** and **Start countdown** outside
Advanced options. The countdown defaults to 30 seconds and can be set from
5 to 60 seconds or disabled. An old unmarked 10-second default upgrades once
to 30; other saved durations and later choices are preserved. The full delay
begins after the opening chat notice is confirmed. Invitations repeat during
the countdown and players can join until questions begin. The host can still
choose to start early.

The ready check uses a separate **I'm ready** action. Joining does not mark a
player ready. Clicking it immediately shows **Ready sent** and disables repeated
clicks until the host confirms **You're ready**. Missing confirmation or a queue
failure offers a retry or Party-chat fallback. Joining closes once question announcements start. The host can
continue without every player checking in, matching the existing optional
ready-check rules.

Joined players get the current question with four wrapped, clickable choices.
The first click immediately highlights the choice and shows a prominent
**Answer N selected** heading with **Sending...**. Only the host's receipt changes that to
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

`Game.lua` remains the only scoring and answer-acceptance engine. The staged
question-sync update negotiates `earlyQuestions` per participant. When all
joined addon players support it, the current question is prepared on their
clients while hidden on both the host and player screens. Rules can post,
but the first question line waits for preparation receipts, up to 12 seconds.
A timeout prints an explicit Party-chat fallback notice.

The first question chat echo reveals the host card. A prepared player's
selected-host Party/Party-leader chat event reveals the same cached question
immediately. A small `show` packet is the fallback if that event is missed.
The queued-text preview and secure send button obey the same hold, and
restart chat lines include the numeric attempt to reject stale cues.

Preparation uses a stable session/question/attempt/revision identity separate
from ordinary snapshot sequence numbers. A `show` arriving before the payload
is buffered. Showing the question never enables answers. After the final
choice is confirmed, the existing presentation gate retains shown receipts;
it does not resend the same bulk question. Only the confirmed **Answers open**
notice starts the host-owned deadline. Missing clients have a second bounded
presentation timeout and can use chat. Mixed older clients keep the previous
post-chat snapshot flow; all addon participants need the staged update for
the synchronized presentation path.

This removes the intentional host reading lead. It cannot promise identical
wall-clock display times across two networked clients, and a modified addon
can inspect prepared data. Display timers remain estimates and the host
alone decides whether an answer is in time. Transport queue/rate bounds and restrictions are unchanged.

Pause/restart changes the attempt number. Old choices and acknowledgements
cannot unlock or score a new attempt. Combat and activity/chat restrictions stop
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

Party packets negotiate the network-only LibSerialize codec when all explicit
recipients support it. Invite, join and sync messages remain in the original
format. Unknown or older recipients use the original format for the whole
packet. See [wire codec](wire-codec.md) for compatibility, bounds and measurements.

`Codec.lua` remains the saved-history and legacy packet codec. It
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

## Troubleshooting invitations

With both clients on 0.3.1-beta or later, use `/lf debug` on each client after
opening a Party lobby. The Party section shows context availability, the
loaded ChatThrottleLib version, remote prefix events, accepted frames, wire
send attempts, the latest invitation outcome and any player-window error.
Self-echoes do not count as remote traffic. An invitation hidden behind setup
is a different failure from one that never reaches the client; neither a local
send attempt nor a prefix event proves completed invitation delivery.

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
