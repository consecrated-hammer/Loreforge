# Player window

`Player.lua` is the player's side of a Party game: invitation, lobby, ready
check, question card, reveal, final results and saved games. It draws a model
and calls `ns.Party` actions. It never reads `Game` internals, the question
bank or scores, so the host stays the only authority. The design behind it is
in [player UI design review](player-ui-design-review.md).

## Contract

`ns.Player` provides:

- `Initialise()` registers a `PLAYER_REGEN_ENABLED` listener so an invitation
  held back by combat appears once combat ends. Optional; later renders also
  show it.
- `Render(model)` stores the model and redraws. `Render(nil)` closes the
  window and the restore button. Call it on every state change and tick.
- `Show()` reopens the window for the current model. `Hide()` hides it and
  leaves the player in the game.

A model with `handlers` uses those functions instead of `ns.Party`. That's the
host playing along: `ns.RefreshHostPlayer` in `Host.lua` builds a model from
the game on every host refresh and closes the window when the game ends, since
results stay on the console. A Party game the host has joined or been invited
to takes priority, as does browsing history.

**Minimise** on the console hides it during the game. The model's `hostStep`
then puts the host's next step on the footer: **Start questions now**, **Ask
next question**, or **Open host console** when only the console can do it
(manual posting and pauses). `consoleHidden` adds a **Host console** button off
the quiz card. A minimised console opens again when the game finishes.

The window is built on the first render that needs it. Clicks call
`ns.Party.Join`, `Decline`, `Ready`, `Answer(choice)`, `RetryAnswer`, `Leave`,
`RequestSync`, `ShowHistory` and `OpenHistory(id)` as plain functions, looked
up at click time. A missing action does nothing.

The model fields are the ones in the integration contract: `id`, `state`,
`host`, `status`, `config`, `joined`, `ready`, `index`, `round`,
`totalQuestions`, `attempt`, `question`, `choices`, `deadline`, `selected`,
`locked`, `pending`, `answerStatus`, `correct`, `correctText`, `rows`, `me`,
`answeredCount`, `resultsPending`, `reason` and `history`, plus the optional
`rounds` for finished games. `correct` is only
read in `revealing`, `between` and `finished`, so a stray value during
`accepting` can't leak the answer.

## When the window shows

- An invitation opens once per session `id`. In combat or chat lockdown it
  waits and appears afterwards. **Decline** declines and closes it for good. Invitations sit near the top of the screen; joined games use the saved position.
- A joined session opens once on its own, for example after a reload and
  `RequestSync`. After that, only **Hide**/Escape and the restore button
  control it, so ticks never pop it back up.
- While hidden in an active game, a small **Loreforge quiz** button stays on
  screen. It reads **Loreforge: answer now** while a question is open and
  unanswered. It's draggable but its position isn't saved.
- Final results open once even if the player hid the window mid-game.
  **Close** on results or history shuts it without a restore button.
- **Leave** calls `Leave`, closes the window and keeps it closed for that
  session. **Show** can still reopen it.
- `state = "history"` always shows, because it only comes from a click.

## Layout

The window follows HammerCore's lore quiz (`src/Quiz.lua`): the quest icon and
title, the position top right, a close X (which hides, as above), and a thin
timer bar under the title. Those and the footer of actions are fixed.
Everything between them sits in a scrolling body. The window is at least 340
tall, so moving from the lobby to a question doesn't change its shape. The
body grows with its content until
the whole window would take more than 85% of the screen height at the
window's scale. Past that, the mouse wheel or the thin bar on the right
scrolls it. A new question or phase starts at the top, and renders within
the same question keep the position.

## Answering

Four plain full-width rows grow with wrapped text and push later content down
rather than overlapping. A click sends `Answer(n)`, the row takes the selected
border and the feedback line under the rows reads **Sending...** straight
away. Rows stay open until time's up: clicking another row changes the answer,
matching chat, where the last number typed counts. Clicking the same row does
nothing. **Answer in. Click another to change it.** only appears when the model
sets `locked`.
If `selected` is set with `pending` false and nothing locked, the feedback
reads `answerStatus` (or "Answer not confirmed; use Party chat") and **Retry
answer** calls `RetryAnswer()` with no choice. The timer bar counts down from
the model's `deadline`, and the rows close when it runs out, even between
renders. One muted line under the feedback gives the player's points, place
and how many have answered.

The reveal gives the correct row the accent border and a wrong pick the danger
border, and the feedback reads **Correct!** (with any streak of two or more),
**Not quite.** or **Out of time!**. Standings wait until `between`: up to five
rows in model order, with the local player pinned underneath when they're
further down.
Chat-only players are listed like anyone else. Tied winners read **Shared
win**.

## Round scores

A finished model can carry `rounds = { { round = n, rows = { { key, round,
total, rank }, ... } }, ... }`. When it does, **Round scores** appears under
the final standings, which stay where they are, with a button per round (up to
20). Clicking a round lists up to 10 of its rows, with the local player pinned
underneath if they're lower down. Each row shows the round points and the
running total. Clicking the same round again closes it. Names come from the
round row, or else from the top-level `rows` by `key`. Round data is only
displayed, never re-ranked or used for scoring, and it's ignored outside
`finished`.

## Settings it reads

`ns.db.playerScale` (clamped to 0.7 to 1.5, set under Settings > Interface)
and `ns.db.playerX`/`playerY`, which are saved when the game window is dragged.
An invitation sits near the top of the screen instead and doesn't save its
position. `ns.db.sound` turns the cues below off.

## Cues and finish

The position line uses the host's numbering: the question and total, with the
round and its theme in front for a themed game.
Between questions, a model with `nextAt` counts down; `hostPaced` says the
host starts the next one. The timer bar turns amber under 30% and red for the
last five seconds, with a soft tick each second until the player answers.
Sounds play for an invitation, a new question, a correct or wrong reveal and
the finish (a fanfare for a win). Finished games show a headline (**You won!**, **Shared win!**
or the place) and gold, silver and bronze names for the top three. **Leave** asks first, and isn't offered on the quiz card. Answer key bindings
still work but aren't shown on the rows.
History lists up to 20 games; **Your games** opens the main window's History
tab out of combat.

## Tests

`tests/test_player_ui.lua` loads the real vendored HammerCore and the full
addon with stubbed `ns.Party` actions. It covers the invitation, combat
deferral, joining, lobby, ready check, all four answer rows, pending, locked,
unconfirmed and retry, deadline closing, reveal, long-text layout, scroll
bounds on a 600px screen and at 1.5 scale, wheel and bar scrolling, the fixed
footer, round scores, hide/restore and Escape, pinned standings, shared
winners, history, Leave, missing actions and no keyboard focus. The harness
reports fixed text heights unless a test overrides them, so in-game wrapping
and clipping still need checking in both clients.

## Window height

A game's window holds its height so it doesn't jump between screens. It starts
tall enough for a question card and the standings it will show, and only grows
from there, up to the screen cap. Long content past the cap scrolls. The window
is pinned by its top edge (`playerLeft`, `playerTop`), so growth only moves the
bottom. A new game id starts again, and the history view isn't held.
