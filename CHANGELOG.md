# Changelog

## [Unreleased]

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
