# Changelog

## [Unreleased]

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
