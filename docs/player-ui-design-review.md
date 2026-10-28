# Player UI and shared game history

Design review, 2026-10-24. Original design; see [current Party implementation](party-client.md)
for the local implementation and remaining in-game checks.
Reviewed with Astra and Claude Opus. The transport probe shipped in 0.1.0-dev11.

## Is this possible?

Yes in principle. WoW provides addon messages and ordinary frames for an
invitation, lobby, clickable question card and results. Reliable remote
delivery needs a real two-client test for each supported client and destination.
An API success or the sender's own echo doesn't prove another player received it.

| Context | Evidence and release position |
| --- | --- |
| Local player interface | Existing HammerCore surfaces and widgets support the design; native rendering still needs testing. |
| Party outside restricted activity | First candidate on Retail and Forever, conditional on a bidirectional probe. |
| Premade party inside a dungeon | Test separately from an open-world party and from a queued Instance group. |
| Raid | Extend after delivery and larger-roster traffic tests. |
| Instance | Explicitly unverified on both clients. Don't promise remote player UI from ordinary Instance chat working. |
| Guild | Existing chat games remain available. Defer unsolicited guild-wide UI invitations; use explicit player opt-in if added. |
| Combat or restricted activity | Pause in the first version. Exact native restriction boundaries need testing; this is a product rule, not a claim that every API is always blocked. |

The [Blizzard ChatInfo documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua)
defines prefix registration, addon sending and receipt events. Unlike ordinary
chat events, `CHAT_MSG_ADDON` doesn't provide a sender GUID. Identity needs its
own roster lookup. [Campkeeper's author notes](https://www.curseforge.com/wow/addons/campkeeper/files/9129067/additional-files)
provide encouraging Forever Guild/custom-channel evidence, but don't prove Party,
Raid or Instance delivery.

## Hosting and joining

Opening `/lf` or clicking the minimap button opens the current activity or private
setup. It doesn't advertise a game. **Open lobby**, inside **Host game**, starts
the deliberate invitation while the Game Master finishes configuring it.
**Start quiz** commits settings and starts the countdown.

Players receive one non-modal HammerCore invitation with the Game Master's
name, channel, game length, answer time and **Join quiz** / **Not now**.
It doesn't steal focus. Settings changes update the existing lobby rather than
creating more invitations. Defer invitations during combat, deduplicate by
host/session and provide session mute plus general invitation preferences.
Silence doesn't establish whether someone lacks the addon, declined or muted.

Join shows a pending state until the host confirms it. Players can join while
setup continues, inspect categories and difficulty, and see who else joined.
When the optional ready check is enabled, show **I'm ready**; joining alone
doesn't silently satisfy that explicit check. Material settings changes clear
readiness. The host can start with unready players after a clear warning.

Declining the UI doesn't prohibit ordinary chat participation. Hide keeps the
player joined and leaves a compact return control. Leave ends UI participation
without retracting an accepted answer or earned score. Competing lobbies never
stack popups or switch a player automatically.

## Player window

Use one draggable, scalable window for lobby, question, reveal and results.
Start around 480 pixels wide, grow for wrapped content, and test both clients
before fixing dimensions. Keep the existing HammerCore dark surfaces, green
headings, blue selected state, muted secondary text and parchment highlights.
Use theme roles rather than hard-coded colours.

```text
Loreforge                 Round 2/3 · Question 4/5
██████████████░░░░░░░░░                         12s

<Question, fully wrapped>

[ 1  First answer                                ]
[ 2  Second answer                               ]
[ 3  Third answer                                ]
[ 4  Fourth answer                               ]

Locked: 2 · Second answer
You: 4 points · Streak 2          [Leaderboard]
```

Four vertical full-width answer rows accommodate long choices. One click is
final, matching chat. The selected row responds immediately with **Sending…**;
only host acknowledgment changes it to **Locked**. Missing acknowledgment shows
**Answer not confirmed**. Retry the same request and choice, never a new answer.
After timeout, disable choices and wait for the authoritative reveal.

Reveal shows the correct answer, the player's choice, point/streak change and
per-choice totals. Words and symbols accompany colour. No other player's choice
is shown before reveal, including on a participating Game Master's screen.
The Game Master uses the existing Host game answers rather than a second card.

Use brief optional transitions, optional soft question/reveal sounds, Reduce
motion and a scale setting. No flashing countdown, looping effects, keyboard
focus theft or automatic number-key bindings. Hide/restore stays easy.

## Leaderboard

The live leaderboard updates from confirmed question results, with rank, name,
score and current streak. Pin the local player's row when they're outside the
visible leaders. Show a compact top group with an expandable full roster rather
than squeezing a raid into the question card. During an open question, only
the answered count changes; provisional answers don't change standings.

Round results show round points and overall standings. Final results show
shared winners, total correct/attempted, accuracy and best streak. Equal scores
share rank and wins; alphabetical ordering may stabilize tied rows but cannot
break a tie. Chat-only players belong in the same standings. A non-participating
Game Master doesn't acquire a score merely by hosting.

## Each quiz is a saved game

The design requires completed results to sync to every participating addon client,
like a run in a history list. This supersedes the reviewers' initial suggestion
to defer player-side history. The host remains authoritative during play; each
client then stores the same completed result locally.

The History list should show date, Game Master, client, category/difficulty
summary, rounds/questions, winner or shared winners and the local player's rank.
Opening an entry restores the full leaderboard, per-round standings, scores,
attempts, accuracy and best streak. Mark local tests so they can be distinguished
from group games. Show **Results from <Game Master>**, not a claim of independent
Blizzard verification.

Use a unique game ID, separate from the host's local serial, and a versioned
result format. Store host identity, start/end times, client scope, committed
settings, scoring rules, participant identities and final standings. Include
chat-only players in the result even though they cannot receive it themselves.
Sync to consenting participating addon clients; don't broadcast historical
records to arbitrary guild members or silently enroll bystanders.

Completion and persistence must be explicit. A complete result is stored once
under its game ID. Repeat deliveries acknowledge the existing entry and cannot
increment games, wins or streak records again. Conflicting data for the same
finalized ID is flagged rather than silently overwriting history. Aborted games
are labelled incomplete and cannot award completed-game wins.

Use a small final-result manifest plus bounded chunks, with format version,
length and integrity check. Publish only after host finalization. Receivers
acknowledge durable storage, request missing pieces and mark **Sync pending**
until complete. Retain recent finalized results for bounded catch-up after a
participant reload or temporary disconnect. Offline clients cannot receive
anything until they reconnect with a client that still has the result.

Transport acknowledgments and result history are separate from current chat
echo confirmation. A lost result acknowledgment must not re-score or restart
the game. A checksum detects corruption; it doesn't authenticate a modified
host or client. Keep received history and legacy host-only aggregates clearly
separated until migration and deduplication rules are defined.

## Shared rules and delivery

Use one host-owned scoring engine and identity key across chat and UI. First
valid host-received answer wins, one point per correct answer, no speed bonus.
Players receive actual question text and shuffled choices, not bank IDs or
future answers. Never send the correct index before reveal.

Bind messages to actual roster-resolved sender, session nonce, protocol version,
question and attempt. Payload GUIDs are hints to verify, not trusted identity.
Reject stale attempts, unexpected host messages and malformed/oversized data.
Don't depend on cross-realm whispers; test each distribution independently.

The timer uses one host deadline. Client `GetTime()` values aren't shared clocks;
estimate offset/latency and resync remaining time without granting a new window.
The display is approximate and the host decides whether an answer was timely.

Chat users retain the full question and choices. UI users shouldn't receive
complete question text ahead of the corresponding chat presentation. Wait for
the final chat confirmation and complete UI assembly before opening answers,
with bounded delivery waits and a visible fallback decision. Never wait forever
for one unresponsive client. Existing `Game:Echo` currently opens the timer
immediately, so presentation coordination needs an explicit engine boundary.

On addon transport failure, visibly fall back to chat without claiming an
unacknowledged click counted. Participant reload requests a current snapshot;
host reload ends the active game in the first version. There is no host
migration. Freeze scored enrollment at question one initially; late arrivals
can use the existing chat rules where eligible, with UI spectating deferred.

## Review decisions and proof needed

Both reviewers support the flow, explicit consent, host authority, vertical
answer rows, acknowledged locking, one shared chat/UI score and probe-first
delivery. Opus proposed a broader Party/Raid/Instance overlay and fewer engine
changes. Astra recommended Party first and a deliberate presentation gate.
Use the narrower first channel and the explicit gate: current echo timing and
partial question delivery make an unchanged-engine guarantee premature.

Readiness is explicit when enabled, rather than assuming Join means ready.
Use a host deadline rather than restarting a full duration on packet receipt.
Keep motion subtle rather than adding pulses and sweeps to every transition.
Shared history and a real leaderboard are now required in the first complete
player experience, rather than later extras.

Before implementation, run a dev-only two-client transport probe on Retail and
Forever: invite, accept, multipart UTF-8 question, answer and host acknowledgment.
Record actual remote receipts, result codes, sender names, latency, throttling
and restriction transitions. Include Forever surnames, home/instance group
categories, and separate Party, Raid, Instance and Guild contexts. Use consenting
clients and a bounded message count. Self-echo alone isn't a pass.

Then test one full game with two addon players and one chat-only player:
invitation, settings updates, readiness, pacing, clicks versus chat first-answer
locking, equal scores, shared ties, round/final leaderboard and identical stored
results. Inject loss, duplicates, reorder, missing chunks, player reload, host
loss, major-version mismatch and oversized payloads. Verify a repeated final
result never awards records twice and a missing-final client catches up when
delivery becomes available. Large-roster traffic needs its own budget test.

The local Party implementation now follows this design after the paired Retail
probe passed on 2026-10-29. See [Party client](party-client.md) and the new
[client acceptance checklist](client-checks.md) for its scope and remaining proof.
