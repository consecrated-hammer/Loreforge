# Campfire Quick play

Campfire.lua observes Forever's seated campfire aura (1229739). It uses existing
Loreforge questions and the same offer/card/book UI as flights. No third-party
question data or implementation is copied. Unsupported clients have no listener
or Camping tab. Secret/unavailable aura data is unknown, never absence.

Quick play > Camping owns these independent settings:
- qpCampfire: enabled; existing false remains Off.
- qpCampfireStart: false for Ask me, true for Auto-start when enabled.
- qpCampfireClose: close campfire results after six seconds, default true.
- qpCampfireReveal: challenge answer pause, default 3 seconds, range 1–8.
- qpCampfireGrace: finish-question time after standing, default 10, range 0–30.
- qpCampfireBook: show dismissed book, default true.
- qpCampfireBookPoint: saved position independent of the flight book.

Ask me opens the flight-style two-choice prompt: Quick play / Campfire challenge,
Not now, context-specific opt-out and automatic-start checkboxes. No question is
created before acceptance. Auto-start uses the flight-style three-second countdown.
Campfire challenge is mode camping, with no per-question deadline while seated.
It is context-only, leaving ordinary solo-mode preferences unchanged.

Quick.Landed and Quick.EndCamping share the same ended() state machine. Standing
ends a countdown immediately, grants grace for an open challenge question, or
finishes between questions. A timed-out last question is not counted. Results
show Back on your feet!, correct answers, best streak and a separate camping best,
with Keep going / Close and optional auto-close. Quick play survives departure,
matching its flight behavior. Hidden paused quizzes close on departure. Combat
uses the same card pause/resume path as flights.

Campfire ownership is the exact Quick.state pointer, retained across in-card mode
changes. Manual replacement remains separate. A new seated visit is latched;
dismissing the offer leaves a book without repeating the prompt. Loreforge
rechecks a missing seated aura after one second so sleeping bag stack refreshes
keep the same visit and the current quiz or book. Group games,
active cards/prompts and welcome/news have priority over automatic offers.
Standing/disable/takeoff remove campfire prompts/books; takeoff clears owned
sessions before normal flight handling and waits for known absence before a new
visit. State changes are event-driven with no polling or protected gameplay calls.

Tests exercise actual prompts, card/game, book actions, combat, both challenge
endings, grace, countdowns, settings/reset isolation and Retail non-support.
Native aura detection and rendering remain in-client acceptance checks.
