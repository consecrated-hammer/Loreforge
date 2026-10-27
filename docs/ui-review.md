# Host game UI/UX review, 2026-10-24

Claude reviewed the Host game start-to-finish flow independently. The first
review used the cross-model review tool. A dedicated Herdr Claude session then
reviewed the revised flow and checked the resulting blocker fixes. Both were
read-only. The reports are in ignored `.scratch/peer-review/`.

The review found unclear per-line manual controls, hidden setup options,
chat-only errors, poor echo recovery, incomplete roster visibility and an
incorrect ready-button action during the announcement. Follow-up code checks
confirmed the blocker fixes. Claude did not run a game client or Lua tests;
Codex ran the tests under Lua 5.1 in Docker.

The revised flow:

- Host-paced and auto-advance games both deliver question lines and results
  automatically. Host-paced games wait at **Ask next question**.
- The primary action follows the phase: sending, start questions, answers open,
  ask next question, resume game or new game. Progress, instructions and player
  counts stay visible. Section shortcuts reach the lower setup options.
- Destination and eligibility errors appear in setup. Fresh settings select
  the active group channel, and **Use current group** corrects it after changes.
- Ready replies work during the announcement and countdown, including common
  variants. The Game Master's ready button submits readiness in both phases.
  Ready-lobby roster refresh can add missing players and shows its result.
- Forever names include surnames independently of realm. Chat replies can
  also match an enrolled GUID; unmatched quiz senders appear in diagnostics.
- Actual chat lockdown pauses sending. The outgoing-addon realm flag does not
  prevent ordinary chat attempts by itself.
- A timed-out pending line is preserved. The host can confirm a visibly posted
  line directly, or resume and prepare a resend. Failed sends never retry in a
  loop. Stopping asks before discarding unfinished results.

All four Lua suites pass. The UI-flow suite walks a two-round Instance game on
both client configurations, including real-shaped surname APIs, a differently
formatted sender with matching GUID, early ready-button use, roster refresh,
host-paced progression, timeout recovery, saved records and confirmed stop.
The automatic suite covers all four destinations, auto-advance, participation
and local testing. Syntax and both TOC checks pass.

Actual Instance chat permissions, the client's sender/GUID payload, native
secure macros, popups and pixel layout remain for the client checklist. A
passing mocked walkthrough is not proof of a successful in-game quiz.
