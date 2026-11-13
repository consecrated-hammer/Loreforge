# Loreforge UX audit and development candidate, 13 November 2026

Loreforge keeps its tavern quiz character: square category paintings, readable answer text, storybook headings, streak flames, local banter and restrained celebrations. Controls keep direct wording. This pass improves reading space and discoverability rather than adding game mechanics or another visual system.

The implementation is on `feat/settings-ux`, based on `ef20465`. The source candidate is 1.4.0; it is not a stable release. The four pre-existing dirty files in the primary checkout were the 12 November flight launcher work (`QuickCard.lua`, `QuickPlay.lua`, `README.md`, `tests/test_quick_play.lua`). They were copied intact into an isolated worktree before extending the card. The primary checkout and its edits remain untouched. HammerCore was clean at `3c1eeeb2b1ef58ff964c5866ff4abe552733522a`, version 0.5.2, and synced with its official tool. No shared-library source changes were needed.

## Complete surface audit

The audit considered information architecture, progressive disclosure, visual hierarchy, interaction quality and delight on every surface below. Layout findings are source/harness evidence; none constitute native client acceptance.

| Surface | Finding and decision |
| --- | --- |
| Main Play, History, Hall of Fame | Keep the three task tabs. When solo, show Quick play, Daily question and Practice a full game choices with records, then the hosting setup in a scrollable form. Preserve Solo Main by ordering and highlighting its preferred choice. Keep the restore-running-game path. |
| Game setup | Preserve Play in, host participation, difficulty, count, answer time and countdown. Keep Short/Standard/Marathon visible. Name the active preset or Custom in the existing duration summary; tooltips state that only count/time change. No new wizard. |
| Categories | Preserve bank, overlapping selections, All/None, difficulty-filtered counts and insufficient-pool errors. Keep full category labels and count reservations. Keep Categories available when Party lobby opens. Existing paintings remain the category identity during play; no new catalogue/art. |
| Pacing & chat | Explain auto-advance versus Ask next question directly. Disable Question gap and Pause when quiet while host-paced, including mouse-wheel changes. Keep choice formatting and record announcements separate. |
| Party lobby | Open once into its own tab, with Categories still alongside it. Preserve invitation/join state, expiry, Keep lobby open, invite-new-arrivals and output-change confirmation. Do not label unknown clients as ready or available. Readiness belongs to the start countdown. |
| Live host console | Existing phase-specific action, scores, timer, response counts and pause/recovery are appropriate. Preserve sending, pending echo, confirmed post, refusal, timeout and explicit manual fallback. No timer starts or automatic retries changed. |
| Party invitation and joined quiz | Existing question scroll layout, answer pending/confirmed states, score/streak, results, Leave confirmation and restore are retained. Restore-button pulse now respects Animations, including an already running pulse. |
| Quick play | Reserve three question lines, two answer lines and feedback space before play. Measure only overflow; keep ordinary click targets stable and centre the square painting. Reveal verdicts use normal text with tick/cross cues, with small quips underneath. Reuse existing Pop, Sparkle, Shake, Pulse and StreakBadge helpers under the card animation switch. Preserve endless/manual/automatic behaviour and timer rules. |
| Streak | Keep first-miss ending and correct answer in the summary. New bests get a headline, previous best, win sound and one visible celebration, without replay on redraw. |
| Lightning | Keep 30–180-second game clock, immediate feedback, rapid transition and deadline-owned final score. Layout changes do not restart the clock. |
| Flight challenge | Preserve unknown ETA, optional LibTaxiData, NPC flights, answer pause, grace, Touchdown, close/Keep going and dismissed-quiz launcher. Do not change transport or flight detection. |
| Quick play Options | Keep four mode descriptions, Timer, card appearance and flight choices. Place left when right space is insufficient. Use one existing timer setter from both settings and Options; never invent a new deadline on a presentation redraw. |
| Takeoff prompt | Keep Ask me/Auto-start/Off choices and existing concise invitation copy. Preserve combat deferral and saved preferences. Check real prompt fit on both clients. |
| Daily and result | Preserve server-date selection, daily number, one attempt, reveal, streaks, best and next availability. Full result-note wrapping now gets room. No two-letter ID, reroll or scheduling change. |
| Welcome/setup | Existing two preference tasks and reopening `/lf setup` remain appropriate. Preserve one-time/update triggering, dismissal and defaults. No blocking extra steps. |
| History | Keep hosted/joined combined list, detail/round navigation, ordering and client boundaries. Name a winner or shared win with a crown in the detail, then your place and best streak. Leave ranks and records unchanged. |
| Hall of Fame | Personal bests lead as four tiles, with leaderboard below and destructive clearing only in settings. Keep wins/accuracy/streak rankings and client separation. Long names and best captions still need native inspection. |
| Interface settings | Split presentation choices from window sizing/behaviour. Retain independent flair switches; default personality stays on. Card animations do not require Interface Animations. Reset only the current tab. |
| Quick play settings | Split Play, Card, Flights and Daily question. Hidden dependent controls remain searchable through their enabling row. Reset only the current tab. |
| Key Bindings | Keep shared keyboard/mouse editor, conflict confirmation and combat guard. Index individual bind/change/remove actions and replace registrations after dynamic refresh. Recheck combat when confirming a replacement. |
| Records, Party games, Visibility | Keep confirmed destructive clear secondary to viewing records. Reset settings retains history, bests and Daily data. Preserve Retail-only enhanced home-Party support and shared minimap/update/settings controls. |
| Minimap, reference and troubleshooting | Preserve mode shortcuts, daily completed state, solo-click preference, Back to game, diagnostics/probe and commands. What's new links target the new tabs. No unrelated shared-page redesign. |

## Current-to-proposed control mapping

Essential controls stay directly visible for their task. Standard preferences live on shallow tabs. Advanced/dependent preferences either name their enabling control or remain disabled with explanatory hints.

| Before | Candidate location | Controls and level |
| --- | --- | --- |
| Interface / Sound, Game window, Flair | Interface > Presentation | Sound cues, Artwork, Round intros, Storybook style, Animations, Tavern banter, Streak flair. Standard. |
| Interface / Window size and Game window behaviour | Interface > Windows | Main window, Player window, Window opacity, Minimise when playing along. Standard. |
| Quick play / Play | Quick play > Play | Timer, Seconds per question, Next question automatically, Wait before next, Lightning length, Main button when solo, Categories & difficulty. Timer/next are standard; seconds/delay are dependent. |
| Quick play / Look | Quick play > Card | Artwork, Animations, Card size and Banter frequency (every third reveal by default). Appearance switches are shared with Options; Lightning has no quips. |
| Quick play / Flights | Quick play > Flights | On flights, Shortest flight, Close on landing, Flight answer pause, Landing grace, Retail Loremaster lines. On flights is standard; shortest flight depends on Auto-start. Remaining tuning is advanced but visible. |
| Quick play / Daily question | Quick play > Daily question | Daily question, Offer at login. Offer depends on enabled Daily. |
| Key Bindings / grouped editor | Key Bindings, same page | Bind Answer 1–4 and Quick play; Change/Remove appear only while bound. Standard, individually searchable. |
| Player records | Games and records | Open Hall of Fame, confirmed Clear player records. View is standard; clear remains secondary/destructive. |
| Party games | Games and records | Show Party game invitations, Open History and support/privacy explanation. Standard. |
| Visibility/reference | Same shared pages | Minimap, solo left-click, update/setup/search/window preferences, Commands, Troubleshooting, About and What's new. Unchanged ownership. |
| Hosted setup presets | Same header and summary | Short/Standard/Marathon and Custom, question count and estimate. Essential starting point. |
| Hosted Game/Categories/Pacing | Same task tabs, plus lobby | Existing setup controls retained. Categories no longer disappears; pacing-only steppers disable in host-paced mode. |

Settings labels are unique within each tab. Standard controls register with HammerCore; custom binding tiles and active-row actions register locally and clear stale entries. Hidden timer/next/shortest-flight/daily controls point at their enabling row. Search focuses the actual control, or the visible enabling row. The category shortcut opens the existing shared setup state rather than duplicating category/difficulty preferences.

## Compatibility and deferred work

All saved preference keys remain flat and unchanged. Tab selection uses HammerCore's existing navigation state. Resets touch explicit tab-owned keys; record/history/daily structures are not migrated or cleared. No game rules, scoring, question identity, Party messages, timing authority, chat restrictions, retry policy, transport, calendar selection, eligibility or question-bank files changed. Retail keeps enhanced home-Party play; Forever keeps chat hosting and its existing fallback. Optional LibTaxiData remains optional.

The source freeze and validation receipt is in ignored `.scratch/ux-overhaul/`. Full Lua suites, syntax, TOC inventories, dependency pins, bank/generator checks and independent review are recorded in the current workstream handoff. Existing suites cover authoritative answers/timers, chat failure/manual fallback, wire compatibility, completion/persistence, Daily and flight lifecycle; new suites cover settings/search/reset and measured card layouts.

Deferred: new game modes, currencies, achievements, catalogue edits, protocol expansion, stronger network delivery claims and a new animation engine. Native font metrics, cramped screens, animation positions, long character/realm labels and sound need real-client checks. Very small screen space can still require a smaller card/window scale. Source and harness checks cannot certify native rendering.
