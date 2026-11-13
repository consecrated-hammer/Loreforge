# Changelog

## [Unreleased]

- Split Interface into Presentation and Windows, and Quick play into Play, Card, Flights and Daily question. Each tab resets only its own preferences.
- Make hidden timer, next-question, flight and daily preferences searchable through their enabling control. Search also finds individual binding tiles and live Change/Remove actions.
- Measure Quick play questions, answer rows, reveals and summaries so long text has room. Keep category artwork square and open Options on the side with space.
- Keep Categories available with an open Party lobby. Show the active preset or Custom beside the game length; explain which settings presets change.
- Preserve a dismissed flight quiz behind a small book with Resume quiz and New quiz. Landing clears a dismissed quiz, and combat hides and restores the launcher.
- Stop card effects when hidden or animations are off; celebrate a new best once. Make the Party restore pulse respect Lively animations, and recognise shared wins in History.
- Use the same timer preference behaviour in card Options and general settings. Recheck combat before applying a confirmed binding replacement.
- Vendor clean HammerCore 0.5.2 at 3c1eeeb for current settings search, tab links and binding controls. No changes to scoring, Party protocol, question data or saved-record formats.

## [1.3.0] - 2026-11-10

### Added

- **Quick play.** A little solo quiz card for when you're hanging about.
  One click, no setup, nothing posted to chat. `/lf quick`, the **Quick
  play** button on the Play tab, a key binding or the minimap button opens
  it. Right-click the minimap button for a menu of settings, the Hall of
  Fame and every Quick play mode. Four modes:
  - **Quick play:** endless questions.
  - **Streak:** keep going until your first miss.
  - **Lightning:** as many as you can in 60 seconds.
  - **Flight challenge:** as many as you can before you land.
- **Fancy a question?** Take a flight path and Loreforge offers a quiz,
  with ten ways of asking (and five more if you're a Loremaster on Retail).
  It can start a Flight challenge straight away instead, or keep quiet.
  Your call, on the **Quick play** settings page or right on the prompt.
- **Touchdown!** Land mid-question and you get a few seconds' grace to
  finish it (**Landing grace**, 10 by default), then your flight score, and
  the card closes unless you hit **Keep going**. No more card hovering over
  the flight master forever.
- **Time to read the answer.** Each answer in a Flight challenge stays up for
  3 seconds (**Flight answer pause**) and gets two full lines, so the tavern
  wit doesn't fall off the edge. Lose a Streak and the right answer stays on
  the summary too.
- **Druid flights count.** Flights picked from a flight master's chat, with no
  flight map, now offer a question or start a Flight challenge as well.
- **Against the clock or Relaxed.** One switch for the timer.
- **The art came too.** Every question shows its category painting, with the
  category name across the bottom. Prefer it plain? Turn Artwork off.
- **Personal bests** for your best streak, best Lightning and best flight
  (with where you flew and when), on the card and in the Hall of Fame.
- **An Options tab** slides out of the card: mode, timer, look and flights,
  without opening settings.
- **Daily question.** One question each day, one try and no timer. Answer
  correctly on consecutive days to grow your daily streak. Open `/lf daily`,
  use the Play tab or pick it from the minimap menu. Your answer and streak
  are shared across characters on the same client.
- **A welcome at the tavern.** Choose what happens on flights and whether to
  offer the daily at login. `/lf setup` opens those choices again.

### Changed

- **Better with LibTaxiData.** Install this free library of flight paths and
  the Flight challenge counts down from your very first flight. Without it,
  Loreforge learns each route as you fly it. Optional, and not on WoW
  Forever yet. **Get LibTaxiData** on the Troubleshooting page has the link.
- Diagnostics include Quick play, flights and whether your character has the
  Loremaster title.
- **Quick play first when solo.** The Play tab leads with Quick play, with
  Practice solo beside it. Prefer practice first? Change Main button when
  solo. You can also choose Quick play for a solo minimap left-click.
- **Ask me, Auto-start or Off.** The flight choices use the same names on the
  card, in settings and in the welcome window.
- **One minimap menu.** The shared HammerCore menu includes settings, the
  Hall of Fame, the daily and the Quick play modes. Settings also has search.

### Fixed

- Long settings labels have more room beside compact dropdowns, including
  Main button when solo and Setup on new features.

## [1.1.0] - 2026-11-09

### Changed

- **Auto-advance is on by default**, and switches on once for existing
  saves too. Prefer host-paced? Turn it off under Pacing & chat.
- **A fresh coat of paint.** Settings move to the new Consecrated Hammer look:
  a cleaner header, switches, icons on every heading, page resets and a
  What's new page with the release history. The main window and the player
  window match it, solid by default. **Window opacity** on Interface lets the
  game show through if you like.
- **Roomier main window.** It's wider and a bit taller, with Play, History and
  Hall of Fame as tabs across the top. Game setup is on its own tabs too:
  **Game**, **Categories** and **Pacing & chat**, so long category names fit
  with their counts and Advanced options is gone. The Party lobby gets a tab
  while it's open, and setup reopens on the tab you used last.
- **Answer keys in settings.** A Key Bindings page binds Answer 1 to 4
  directly. Press a key, done, no rummaging through the game's own menu.
- **Support links.** CurseForge, Discord and Buy me a coffee at the bottom of
  the settings window. Hide them on Visibility.
- **A bit more fun.** Storybook titles and parchment, numbered answer badges,
  answers that pop, sparkle or wobble, tavern banter after each question (only
  you see it, the barkeep is discreet) and a flame beside your score from 3 in
  a row. Tone any of it down under **Flair** on Interface.

### Fixed

- **Stop game from the quiz window.** Solo practice and hosts playing along had
  to dig out the minimised main window to stop. Now it's right there.
- **Shorter names.** Players on your realm show without the realm. Forever's
  realm names were turning name tags into small essays.

## [1.0.0] - 2026-11-01

- Every category has its own painting beside the question, with a bell for
  mixed games. Turn it off with **Theme art** on Interface.
- Themed rounds open with a few seconds of their art and name. Turn it off with
  **Round intros** on Interface.

## [0.3.4] - 2026-11-01

- First stable release. Same game as 0.3.4-beta, with no feature changes.

## [0.3.4-beta] - 2026-11-01

- A **What's new** window after updates, shared with any other Consecrated
  Hammer addons you use. It never opens on a fresh install or in combat. Turn
  it off with **Show what's new after updates** on Visibility, and reopen it
  with `/lf whatsnew` or the About page.
- The player window now follows the lore quiz on About: the question, four
  plain answers, a thin timer bar, a one-line result and one score line, with
  standings between questions. Invitations, the lobby and results use the same
  frame.
- A host playing along now answers in that same window, and the host console
  keeps the posting controls and scoreboard. Results stay on the console.
  **Minimise** hides the console while you play: the quiz window offers your
  next step, and the console opens again for the results.
- One **Questions** count replaces rounds, with optional **Themed rounds**
  where each round sticks to one category. Plain games post scores every five
  questions. Saved multi-round settings become the same number of questions.
- Change your answer any time before the countdown ends, by clicking another
  choice or typing another number. The last one counts.
- A host playing along is minimised automatically as the game starts. Turn it
  off with **Minimise when playing along** on Interface.
- The game window holds its height through a game and is pinned by its top
  edge, so it no longer jumps around. It goes back to its default spot once.
- The last question says final scores are coming while they post, and practice
  games post their results faster.
- The transport probe's commands are now buttons on Troubleshooting.
- Updated the bundled HammerCore library.

## [0.3.3-beta] - 2026-10-31

- Send smaller Party updates between compatible addon clients with LibSerialize. Older clients keep the existing protocol, and saved game history stays compatible.
- Show immediate Ready sent feedback, host confirmation and retry states. Answer clicks now get a prominent selected/locked heading, and queue failures are shown immediately.
- Prepare Party questions on updated addon clients before posting begins, then reveal the question on the first host chat message. Hide the host question, choices and posting preview until that same point. Answer timing and scoring still wait for all choices and the authoritative opening notice.
- Replace the last question on both completion screens with a prominent Game complete heading, winner or shared win, personal result and final standings.

## [0.3.2-beta] - 2026-10-30

- Allow the Party player beta in premade Retail Parties inside dungeons when combat, activity restrictions and chat lockdown are inactive. Queued Instance groups and raids remain excluded. The dungeon transport probe has passed; the full player flow still needs an in-game check.
- Default the configurable start countdown to 30 seconds and expose it in the main setup controls. The old 10-second default upgrades once; other saved durations are preserved.
- Show joined players the start countdown and repeat invitations until the first question so players can join during the countdown.

## [0.3.1-beta] - 2026-10-30

- Restore one chat line per answer choice, including on upgrade from the compact default. The compact layout remains optional.
- Keep Party invitations above the main window and let `/lf` reopen an unanswered invitation.
- Print a received-invitation notice in chat and include Party transport, invitation state and window errors in `/lf debug`.

## [0.3.0-beta] - 2026-10-29

A look-and-feel pass over the whole addon.

- One main window with Play, History and Hall of Fame tabs. Settings opens in its own window with a Back to game button.
- Setup has Quick, Standard and Marathon presets, an estimated game length, plus and minus steppers, category question counts with All and None, and advanced options folded away. Problems show in a banner with the fix beside them.
- Practice solo runs a private game for the host at any time. The host now plays along by default.
- Party lobbies show who has joined, count down their 10 minutes, warn a minute before closing and can be kept open. Switching output away from Party asks before closing the lobby.
- The live game shows the phase as a heading, a progress bar, a timer that turns amber then red, tinted reveals, a leaderboard showing who has answered, and a pacing switch. A line that may not have posted raises one banner: Yes, it posted or Post again.
- Questions post their four choices on one chat line, so each question takes two lines instead of five. The chat tag reads `[Loreforge #N]` and the opening line names the categories. One-round games no longer repeat the winner, and closing records are announced for the top three only.
- History lists every finished game on this client, hosted or joined. The Hall of Fame ranks saved records by wins, with accuracy and best streak.
- A game cut short by a reload or disconnect is reported in setup, with an option to post the standings.
- Party players get a top-of-screen invitation with Join quiz and Decline, the same question numbering as the host, a countdown between auto-advance questions, a finish headline with medal colours, and a confirmation before Leave.
- Optional sound cues, answer key bindings (Key Bindings > AddOns > Loreforge) and window size settings.

Party games still need 0.2.0-beta or later on every addon player; joined
players see the between-question countdown from 0.3.0-beta. The new interface
needs in-game checks in both clients.

## [0.2.0-beta] - 2026-10-29

- Party player beta: opt-in invitations, joined-player question buttons, host-confirmed answers, reveals, streaks and shared scores.
- A bounded presentation step keeps addon and chat answers behind the same opening announcement, with a chat fallback for delayed clients.
- Completed matches sync to joined clients with duplicate-safe history, final standings and per-round scores.
- This implementation is currently limited to Retail home Parties outside instances and combat. Full in-game acceptance is still outstanding.

Both host and addon participants need 0.2.0-beta. Choose Party output, click
Open Party lobby, let players join, then click Start game. Other players can
still answer 1-4 in Party chat. The new full-game interface needs in-game
acceptance; the existing paired-client proof covers the transport probe.

## [0.1.1-beta] - 2026-10-28

- The development transport probe now uses ChatThrottleLib throttling and LibDeflate compression/encoding, with a new wire prefix. Both test players need this build.
- Probe send failures now stop with a diagnostic. Probe queues stop on combat, restrictions, zoning or roster changes. Wire retries, incoming decoding, peer counts and question chunks are bounded.

Both test players need 0.1.1-beta for `/lf probe`. This updates the development
transport test; the player question UI and shared history are not implemented.
Real two-client delivery remains unverified on Retail and WoW Forever.

## [0.1.0-beta] - 2026-10-28

First public beta. Loreforge hosts trivia in group or guild chat, and only the
host needs the addon.

### Added

- Host-paced or auto-advancing trivia in Party, Raid, Instance or Guild chat.
  Players answer `1` to `4` in chat.
- Categories and difficulty drawn from HammerCore's shared question bank, with
  separate question pools for Retail and WoW Forever.
- First-answer locking, round and overall scores, shared wins, streaks and
  personal-best callouts.
- An optional ready check and countdown, an inactivity pause, and optional
  Game Master participation with clickable answers.
- Local player records for each client, with optional end-of-game
  announcements and confirmed clearing.
- A click-to-send fallback when the client refuses automatic chat output.
- HammerCore settings, minimap button, standard commands, diagnostics and
  About page.

This is a beta. Chat delivery, timing and rendering haven't been fully checked
in either game client yet.
